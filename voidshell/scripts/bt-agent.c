// VOID SHELL — BlueZ auto-accept agent (scripts/bt-agent.c)
//
// Quickshell's Bluetooth module speaks to bluetoothd but never registers an
// org.bluez.Agent1, so BlueZ has nobody to ask when a device needs
// authorising. Two concrete failures follow from that (bluetoothd 5.87,
// src/adapter.c ext_auth()):
//
//   * connecting any device that is not Trusted ends in
//       "Authentication attempt without agent" -> org.bluez.Error.Rejected
//     (agent_get(NULL) walks the default-agent queue, which is empty), and
//   * a fresh Pair() has no agent to hand its confirmation to, so pairing a
//     new device from the quick settings cannot complete.
//
// This agent registers itself as the default agent on org.bluez.AgentManager1
// and answers every request with an accept, which is what makes "tap an
// unpaired device to pair it" work without any prompt in the shell.
//
// Capability is NoInputNoOutput: the canonical headless choice. It pins the
// SSP association model to Just Works, so bluetoothd/kernel never come back
// for a passkey or a numeric comparison we have no way to show, and the
// kernel auto-accepts the confirmation (net/bluetooth/hci_event.c
// hci_user_confirm_request_evt) without a round trip at all. Registering an
// agent also flips the adapter to bondable (src/adapter.c
// adapter_set_io_capability, AlwaysPairable=false), which outgoing pairing
// needs — so Pairable turns on by itself, we never set it by hand.
//
// Lifecycle / robustness:
//   * flock on $XDG_RUNTIME_DIR/voidshell-bt-agent.lock — one instance only.
//     quickshell's Process kills us on config reload, and the replacement
//     waits (rather than exiting) so a live agent always exists.
//   * prctl(PR_SET_PDEATHSIG) so we die with quickshell too.
//   * RegisterAgent failures (bluetoothd down) retry every 2s; a
//     NameOwnerChanged match on org.bluez re-registers straight after a
//     bluetoothd restart. All flag setting happens in the filter, the
//     blocking D-Bus calls happen outside dispatch.
//   * Each distinct error is logged once so a stopped bluetoothd cannot
//     flood the journal.
//   * Exit 0 on SIGTERM (deliberate stop -> no restart), exit 1 if the bus
//     connection is lost (quickshell restarts us after its backoff timer).
//
// Build:
//   gcc -O2 -Wall -Wextra -o bt-agent bt-agent.c $(pkg-config --cflags --libs dbus-1)

#define _GNU_SOURCE

#include <dbus/dbus.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define AGENT_PATH "/org/voidshell/agent"
#define AGENT_IFACE "org.bluez.Agent1"
#define MGR_IFACE "org.bluez.AgentManager1"
#define BLUEZ_DEST "org.bluez"
#define BLUEZ_PATH "/org/bluez"
#define CAPABILITY "NoInputNoOutput"
#define LOCK_NAME "voidshell-bt-agent.lock"

#define RETRY_SECONDS 2

static DBusConnection *bus;
static volatile sig_atomic_t g_stop;
static int g_registered;   /* bluetoothd currently knows about us */
static time_t g_retry_at;  /* 0 => try now; otherwise earliest retry */
static char g_last_error[256];

static const char introspection[] =
    "<node>"
    "  <interface name=\"" AGENT_IFACE "\">"
    "    <method name=\"Release\"/>"
    "    <method name=\"Cancel\"/>"
    "    <method name=\"RequestPinCode\">"
    "      <arg name=\"device\" type=\"o\" direction=\"in\"/>"
    "      <arg name=\"pincode\" type=\"s\" direction=\"out\"/>"
    "    </method>"
    "    <method name=\"RequestPasskey\">"
    "      <arg name=\"device\" type=\"o\" direction=\"in\"/>"
    "      <arg name=\"passkey\" type=\"u\" direction=\"out\"/>"
    "    </method>"
    "    <method name=\"DisplayPasskey\">"
    "      <arg name=\"device\" type=\"o\" direction=\"in\"/>"
    "      <arg name=\"passkey\" type=\"u\" direction=\"in\"/>"
    "      <arg name=\"entered\" type=\"q\" direction=\"in\"/>"
    "    </method>"
    "    <method name=\"DisplayPinCode\">"
    "      <arg name=\"device\" type=\"o\" direction=\"in\"/>"
    "      <arg name=\"pincode\" type=\"s\" direction=\"in\"/>"
    "    </method>"
    "    <method name=\"RequestConfirmation\">"
    "      <arg name=\"device\" type=\"o\" direction=\"in\"/>"
    "      <arg name=\"passkey\" type=\"u\" direction=\"in\"/>"
    "    </method>"
    "    <method name=\"RequestAuthorization\">"
    "      <arg name=\"device\" type=\"o\" direction=\"in\"/>"
    "    </method>"
    "    <method name=\"AuthorizeService\">"
    "      <arg name=\"device\" type=\"o\" direction=\"in\"/>"
    "      <arg name=\"uuid\" type=\"s\" direction=\"in\"/>"
    "    </method>"
    "  </interface>"
    "</node>";

static void log_line(const char *fmt, ...)
{
    va_list ap;
    char buf[256];

    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);

    fprintf(stderr, "bt-agent: %s\n", buf);
    fflush(stderr);
}

// Log a failure the first time we see that exact message only. Any later
// successful registration clears the record so the error can be reported
// again if it comes back.
static void log_error_once(const char *msg)
{
    if (msg == NULL || *msg == '\0') {
        msg = "unknown D-Bus error";
    }
    if (strcmp(g_last_error, msg) == 0) {
        return;
    }
    snprintf(g_last_error, sizeof g_last_error, "%s", msg);
    log_line("%s", msg);
}

// Single instance. quickshell reloads its config on file change and rebuilds
// the Process, so a replacement can show up while the old agent has not been
// reaped yet — waiting is correct here, because quitting would leave no agent
// at all. flock is released by the kernel when the holder dies, so the wait
// always ends.
static int acquire_lock(void)
{
    char path[512];
    const char *rt = getenv("XDG_RUNTIME_DIR");
    int fd;
    int waited = 0;

    if (rt != NULL && rt[0] != '\0') {
        snprintf(path, sizeof path, "%s/%s", rt, LOCK_NAME);
    } else {
        snprintf(path, sizeof path, "/tmp/%s.%ld", LOCK_NAME, (long) getuid());
    }

    fd = open(path, O_RDWR | O_CREAT, 0644);
    if (fd < 0) {
        log_line("cannot open lock file %s: %s", path, strerror(errno));
        return -1;
    }

    for (;;) {
        if (flock(fd, LOCK_EX | LOCK_NB) == 0) {
            return fd;
        }
        if (errno != EWOULDBLOCK && errno != EINTR) {
            log_line("cannot lock %s: %s", path, strerror(errno));
            close(fd);
            return -1;
        }
        if (waited > 0 && waited % 30000 == 0) {
            log_line("still waiting for the previous agent to exit");
        } else if (waited == 10000) {
            log_line("waiting for the previous agent to exit");
        }
        usleep(100 * 1000);
        waited += 100;
    }
}

static void send_reply(DBusMessage *orig, DBusMessage *reply)
{
    if (reply == NULL) {
        return;
    }
    // Never answer a call that opted out of a reply; the sender would drop it
    // anyway and bluetoothd logs the unexpected serial.
    if (dbus_message_get_no_reply(orig)) {
        dbus_message_unref(reply);
        return;
    }
    dbus_connection_send(bus, reply, NULL);
    dbus_message_unref(reply);
}

static void reply_empty(DBusMessage *orig)
{
    send_reply(orig, dbus_message_new_method_return(orig));
}

static void reply_string(DBusMessage *orig, const char *value)
{
    DBusMessage *reply = dbus_message_new_method_return(orig);

    if (reply != NULL && !dbus_message_append_args(reply, DBUS_TYPE_STRING, &value,
                                                   DBUS_TYPE_INVALID)) {
        dbus_message_unref(reply);
        reply = NULL;
    }
    send_reply(orig, reply);
}

static void reply_uint32(DBusMessage *orig, dbus_uint32_t value)
{
    DBusMessage *reply = dbus_message_new_method_return(orig);

    if (reply != NULL && !dbus_message_append_args(reply, DBUS_TYPE_UINT32, &value,
                                                   DBUS_TYPE_INVALID)) {
        dbus_message_unref(reply);
        reply = NULL;
    }
    send_reply(orig, reply);
}

static void reply_error(DBusMessage *orig, const char *name, const char *message)
{
    DBusMessage *reply = dbus_message_new_error(orig, name, message);

    send_reply(orig, reply);
}

static DBusHandlerResult handle_message(DBusMessage *msg)
{
    const char *iface = dbus_message_get_interface(msg);
    const char *member = dbus_message_get_member(msg);

    if (member == NULL) {
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (dbus_message_is_method_call(msg, "org.freedesktop.DBus.Introspectable",
                                    "Introspect")) {
        reply_string(msg, introspection);
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (iface == NULL || strcmp(iface, AGENT_IFACE) != 0) {
        // Everything else addressed at our path is unsupported; answer
        // straight away instead of letting the caller time out.
        reply_error(msg, "org.freedesktop.DBus.Error.UnknownMethod",
                    "voidshell bt-agent only implements org.bluez.Agent1");
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    // Release/Cancel/DisplayPasskey are sent with g_dbus_send_message (no
    // reply expected), the rest are sent with a pending reply we must
    // complete. handle_* below only replies where bluetoothd waits for one.
    if (strcmp(member, "Release") == 0) {
        // bluetoothd is dropping us — usually because it is going away.
        // Try again as soon as control returns to the main loop.
        g_registered = 0;
        g_retry_at = 0;
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (strcmp(member, "Cancel") == 0 || strcmp(member, "DisplayPasskey") == 0) {
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (strcmp(member, "RequestPinCode") == 0) {
        // No display to show a real code from; the peer either accepts the
        // default or the pairing fails, which the shell reports.
        reply_string(msg, "0000");
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (strcmp(member, "RequestPasskey") == 0) {
        reply_uint32(msg, 0);
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    // DisplayPinCode, RequestConfirmation, RequestAuthorization,
    // AuthorizeService — accept.
    reply_empty(msg);
    return DBUS_HANDLER_RESULT_HANDLED;
}

static DBusHandlerResult on_path_message(DBusConnection *conn, DBusMessage *msg,
                                         void *data)
{
    (void) conn;
    (void) data;
    return handle_message(msg);
}

static DBusHandlerResult on_filter(DBusConnection *conn, DBusMessage *msg, void *data)
{
    const char *name;
    const char *old_owner;
    const char *new_owner;

    (void) conn;
    (void) data;

    if (!dbus_message_is_signal(msg, "org.freedesktop.DBus", "NameOwnerChanged")) {
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }

    if (dbus_message_get_args(msg, NULL, DBUS_TYPE_STRING, &name,
                              DBUS_TYPE_STRING, &old_owner,
                              DBUS_TYPE_STRING, &new_owner,
                              DBUS_TYPE_INVALID)) {
        if (name != NULL && strcmp(name, BLUEZ_DEST) == 0) {
            // Flags only: blocking calls inside a filter can deadlock. The
            // main loop picks this up as soon as dispatch returns.
            g_registered = 0;
            g_retry_at = 0;
        }
    }

    return DBUS_HANDLER_RESULT_HANDLED;
}

enum call_status {
    CALL_OK,       /* method returned normally */
    CALL_HELD,     /* org.bluez.Error.AlreadyExists: we already hold it */
    CALL_FAILED,   /* bluetoothd down, bad arguments, ... */
};

// Send one AgentManager1 call and block for the reply. Any reply the caller
// needs to keep is handed back through *reply_out; AlreadyExists is reported
// as CALL_HELD rather than a failure, since it only means we raced a
// previous attempt (bluetoothd keys agents by connection, not by path).
static enum call_status call_agent_manager(const char *method, int nargs,
                                           DBusMessage **reply_out, ...)
{
    DBusError err;
    DBusMessage *msg;
    DBusMessage *reply;
    va_list ap;
    int i;

    *reply_out = NULL;

    msg = dbus_message_new_method_call(BLUEZ_DEST, BLUEZ_PATH, MGR_IFACE, method);
    if (msg == NULL) {
        log_error_once("out of memory building AgentManager1 call");
        return CALL_FAILED;
    }

    va_start(ap, reply_out);
    for (i = 0; i < nargs; i++) {
        int type = va_arg(ap, int);
        const void *value = va_arg(ap, const void *);

        if (!dbus_message_append_args(msg, type, value, DBUS_TYPE_INVALID)) {
            va_end(ap);
            dbus_message_unref(msg);
            log_error_once("out of memory building AgentManager1 call");
            return CALL_FAILED;
        }
    }
    va_end(ap);

    dbus_error_init(&err);
    reply = dbus_connection_send_with_reply_and_block(bus, msg, 5000, &err);
    dbus_message_unref(msg);

    if (reply == NULL) {
        enum call_status status = CALL_FAILED;

        if (err.name != NULL && strcmp(err.name, "org.bluez.Error.AlreadyExists") == 0) {
            status = CALL_HELD;
        } else {
            log_error_once(err.message);
        }
        dbus_error_free(&err);
        return status;
    }

    dbus_error_free(&err);
    *reply_out = reply;
    return CALL_OK;
}

static void try_register(void)
{
    DBusMessage *reply;
    const char *path = AGENT_PATH;
    const char *capability = CAPABILITY;
    enum call_status status;

    status = call_agent_manager("RegisterAgent", 2, &reply, DBUS_TYPE_OBJECT_PATH,
                                &path, DBUS_TYPE_STRING, &capability);
    if (status == CALL_FAILED) {
        g_retry_at = time(NULL) + RETRY_SECONDS;
        return;
    }
    if (reply != NULL) {
        dbus_message_unref(reply);
    }

    // Without being the *default* agent, ext_auth() still finds an empty
    // default-agent queue and service authorization keeps failing.
    status = call_agent_manager("RequestDefaultAgent", 1, &reply,
                                DBUS_TYPE_OBJECT_PATH, &path);
    if (status == CALL_FAILED) {
        g_retry_at = time(NULL) + RETRY_SECONDS;
        return;
    }
    if (reply != NULL) {
        dbus_message_unref(reply);
    }

    g_registered = 1;
    g_retry_at = 0;
    if (g_last_error[0] != '\0') {
        g_last_error[0] = '\0';
    }
    log_line("registered as default agent on %s (capability %s)", AGENT_PATH,
             CAPABILITY);
}

static void on_term_signal(int sig)
{
    (void) sig;
    g_stop = 1;
}

int main(void)
{
    static const DBusObjectPathVTable vtable = {
        .message_function = on_path_message,
    };
    DBusError err;
    int lock_fd;
    int bus_lost = 0;

    signal(SIGTERM, on_term_signal);
    signal(SIGINT, on_term_signal);
    signal(SIGPIPE, SIG_IGN);

    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() == 1) {
        // quickshell was already gone when we started.
        return 0;
    }

    lock_fd = acquire_lock();
    if (lock_fd < 0) {
        return 1;
    }

    dbus_error_init(&err);
    bus = dbus_bus_get(DBUS_BUS_SYSTEM, &err);
    if (bus == NULL) {
        log_error_once(err.message);
        dbus_error_free(&err);
        return 1;
    }

    if (!dbus_connection_register_object_path(bus, AGENT_PATH, &vtable, NULL)) {
        log_line("cannot register object path %s", AGENT_PATH);
        return 1;
    }

    dbus_connection_add_filter(bus, on_filter, NULL, NULL);
    dbus_bus_add_match(bus,
                       "type='signal',sender='org.freedesktop.DBus',"
                       "interface='org.freedesktop.DBus',"
                       "member='NameOwnerChanged',arg0='" BLUEZ_DEST "'",
                       &err);
    if (dbus_error_is_set(&err)) {
        log_line("cannot watch %s: %s", BLUEZ_DEST, err.message);
        dbus_error_free(&err);
        return 1;
    }

    try_register();

    while (!g_stop) {
        if (!dbus_connection_read_write(bus, 250)) {
            bus_lost = 1;
            break;
        }

        while (dbus_connection_get_dispatch_status(bus) == DBUS_DISPATCH_DATA_REMAINS) {
            dbus_connection_dispatch(bus);
        }

        if (!g_registered && (g_retry_at == 0 || time(NULL) >= g_retry_at)) {
            try_register();
        }
    }

    close(lock_fd);
    dbus_connection_unref(bus);

    if (bus_lost) {
        log_line("system bus connection lost, exiting for restart");
        return 1;
    }

    log_line("stopped");
    return 0;
}
