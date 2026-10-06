import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Wayland
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — Wi-Fi password dialog: a transient layer surface centered
// on the screen, opened when a secured, unsaved, PSK-typed row is clicked
// (NetworkService.needsPsk). The join
// itself is the real backend — WifiNetwork.connectWithPsk — and a wrong
// key returns as connectionFailed(NoSecrets) on the same network, which
// lands here as an inline error (PRD 17.3: no fake controls, failures
// are shown, never swallowed).
//
// Escape and the header × both dismiss through `dismiss()`, which clears
// state and notifies QuickSettings so the panel can take keyboard focus
// back (the panel's own Escape handler is held off while this dialog is
// up — two matching shortcuts would be ambiguous to Qt and neither would
// fire).
PanelWindow {
    id: root

    // The WifiNetwork object (not the visibleNetworks entry).
    property var net: null
    readonly property bool open: root.net !== null
    readonly property bool connecting: root.net !== null && root.net.stateChanging
    property bool showPsw: false
    property string errText: ""

    signal dismissed

    visible: root.open && PopupManager.isOpen("quickSettings")
    readonly property var targetScreen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen
    screen: root.targetScreen
    color: "transparent"
    WlrLayershell.namespace: "voidshell-popup"
    // Take the keyboard while the dialog is up — the password field is
    // useless without key events (Quickshell defaults to None).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // -1: never let this surface lay claim to space the panel doesn't use.
    exclusiveZone: -1

    implicitWidth: card.width + Theme.space16
    implicitHeight: card.height + Theme.space16

    // Centered on the screen, both axes — a modal prompt belongs in the
    // middle of the view, not parked over the panel. Margin bindings
    // re-center automatically when content grows (an error line) because
    // they derive from implicitHeight.
    anchors {
        top: true
        left: true
    }

    margins {
        top: Math.max(Theme.space16, Math.round(((root.targetScreen ? root.targetScreen.height : 720) - root.implicitHeight) / 2))
        left: Math.max(Theme.sideMargin, Math.round(((root.targetScreen ? root.targetScreen.width : 1280) - root.implicitWidth) / 2))
    }

    // Escape dismisses the dialog (not the panel — the panel's handler is
    // gated off while this window is up, see QuickSettings).
    Shortcut {
        enabled: root.visible
        context: Qt.ApplicationShortcut
        sequences: [StandardKey.Cancel]
        onActivated: root.dismiss()
    }

    Item {
        id: escGrab
        anchors.fill: parent
        focus: root.visible
    }

    onVisibleChanged: {
        if (visible) {
            escGrab.forceActiveFocus();
            pw.forceActiveFocus();
            pw.selectAll();
        } else if (root.net !== null) {
            // The panel underneath closed; drop transient state.
            root.net = null;
            root.errText = "";
            pw.text = "";
        }
    }

    function dismiss() {
        root.net = null;
        root.errText = "";
        pw.text = "";
        root.dismissed();
    }

    function tryConnect() {
        if (root.connecting || !root.net) {
            return;
        }
        if (pw.text.length < 8 || pw.text.length > 63) {
            root.errText = "Password must be 8–63 characters";
            return;
        }
        root.errText = "";
        NetworkService.connectWithPsk(root.net, pw.text);
    }

    function reasonText(reason) {
        if (reason === ConnectionFailReason.NoSecrets) {
            return "Wrong password — check it and try again";
        }
        if (reason === ConnectionFailReason.WifiAuthTimeout) {
            return "Authentication timed out";
        }
        if (reason === ConnectionFailReason.WifiClientFailed) {
            return "Couldn't reach the network";
        }
        if (reason === ConnectionFailReason.WifiNetworkLost) {
            return "Network disappeared while joining";
        }
        if (reason === ConnectionFailReason.WifiClientDisconnected) {
            return "Connection dropped";
        }
        return "Connection failed";
    }

    readonly property string securityLabel: {
        if (!root.net) {
            return "";
        }
        const sec = root.net.security;
        if (sec === WifiSecurityType.Sae) {
            return "WPA3 · password required";
        }
        if (sec === WifiSecurityType.Wpa2Psk) {
            return "WPA2 · password required";
        }
        if (sec === WifiSecurityType.WpaPsk) {
            return "WPA · password required";
        }
        return "Secured · password required";
    }

    // Real failure reporting straight off the network object.
    Connections {
        target: root.net
        enabled: root.open
        function onConnectionFailed(reason) {
            if (root.open) {
                root.errText = root.reasonText(reason);
            }
        }
        function onConnectedChanged() {
            if (root.open && root.net && root.net.connected) {
                ToastService.push("Wi-Fi", "Connected to " + root.net.name, "", "success");
                root.dismiss();
            }
        }
    }

    Comp.GlassPanel {
        id: card
        texture: true
        textureSource: InkArt.sourceFor("wifiDialog")
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.space8
        width: 360
        height: body.implicitHeight + Theme.space12 * 2

        Column {
            id: body
            width: parent.width
            spacing: Theme.space12

            Comp.PopupHeader {
                width: parent.width
                title: root.net ? root.net.name : ""
                subtitle: root.securityLabel
                onClosed: root.dismiss()
            }

            // --- password field --------------------------------------------
            Rectangle {
                width: parent.width
                height: 36
                radius: Theme.radiusSm
                color: Colors.bgElevated
                border.width: 1
                border.color: pw.activeFocus ? Colors.borderAccent : Colors.borderSubtle

                TextInput {
                    id: pw
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space12
                    anchors.rightMargin: 34
                    verticalAlignment: Text.AlignVCenter
                    clip: true
                    echoMode: root.showPsw ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: Colors.textPrimary
                    selectionColor: Colors.accentStrong
                    selectedTextColor: Colors.textOnAccent
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    Keys.onReturnPressed: root.tryConnect()
                    Keys.onEnterPressed: root.tryConnect()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password"
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        color: Colors.textDisabled
                        visible: pw.text === "" && !pw.activeFocus
                    }
                }

                Text {
                    id: eyeText
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space8
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(root.showPsw ? 0xF06F : 0xF06E) // fa-eye-slash / fa-eye
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    color: eyeArea.containsMouse ? Colors.textSecondary : Colors.textMuted
                }

                MouseArea {
                    id: eyeArea
                    anchors.fill: parent
                    anchors.leftMargin: parent.width - 34
                    z: 1
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Only the eye glyph is clickable — the rest of the
                    // field belongs to the TextInput below.
                    onClicked: root.showPsw = !root.showPsw
                }
            }

            // --- hint or inline error ---------------------------------------
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.errText !== "" ? root.errText : "WPA password · 8–63 characters"
                font.family: Theme.fontUi
                font.pixelSize: 11
                color: root.errText !== "" ? Colors.danger : Colors.textMuted
            }

            // --- actions -----------------------------------------------------
            Row {
                width: parent.width
                spacing: Theme.space8

                Comp.TextButton {
                    width: (parent.width - Theme.space8) / 2
                    label: "Cancel"
                    onClicked: root.dismiss()
                }

                Comp.TextButton {
                    width: (parent.width - Theme.space8) / 2
                    label: root.connecting ? "Connecting…" : "Join"
                    active: true
                    onClicked: root.tryConnect()
                }
            }
        }
    }
}
