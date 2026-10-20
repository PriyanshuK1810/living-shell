import Quickshell
import QtQuick
import "./common"
import "./common/components" as Comp
import "./services"
import "./modules/Bar" as BarModule
import "./modules/Media" as MediaModule
import "./modules/Launcher" as LauncherModule
import "./modules/QuickSettings" as QuickSettingsModule
import "./modules/Notifications" as NotificationsModule
import "./modules/PowerMenu" as PowerMenuModule
import "./modules/Toast" as ToastModule
import "./modules/Dashboard" as DashboardModule
import "./modules/TaskManager" as TaskManagerModule
import "./modules/WorkspaceOverview" as WorkspaceOverviewModule
import "./modules/StageShelf" as StageShelfModule
import "./modules/Workbench" as WorkbenchModule
import "./modules/LockScreen" as LockScreenModule
import "./modules/WallpaperOverlay" as WallpaperOverlayModule
import "./modules/Island" as IslandModule

// VOID SHELL — config entry point (`qs -c voidshell`).
//
// Services are instantiated eagerly here on purpose:
//  * the notification server must register the instant the shell starts,
//    otherwise applications have nowhere to deliver notifications (PRD 15);
//  * capability probes (brightness, locker, recorder, hibernate, battery)
//    run exactly once at launch instead of per widget (PRD 5.1);
//  * the stats sampler and toast bus are shared long-lived state.
// Modules then bind to these singletons rather than polling themselves.
ShellRoot {
    id: root

    readonly property bool servicesWarmed: [
        PopupManager.activePopup,
        HyprlandService.ready,
        MediaService.available,
        NotificationService.count,
        NetworkService.backendAvailable,
        BluetoothService.available,
        AudioService.available,
        BrightnessService.available,
        PowerService.ready,
        SystemStats.osName !== "",
        WeatherService.status !== "",
        TaskStore.loaded,
        ScreenshotService.available,
        RecordingService.available,
        ToastService.shownCount,
        LauncherModel.allApps.length,
        FocusTimer.remaining >= 0,
        // Island services are instantiated here on purpose (same reason as
        // above): the capability probe and the settings load run once at
        // launch instead of on the first announcement.
        IslandSettings.loaded,
        ActivityStore.loaded,
        IslandProviders.settled,
        TimerStore.loaded,
        PresetStore.loaded,
        ClipboardService.loaded,
        KeepAwake.available,
        JobBridge.demoMode,
        IslandRouter.serial >= 0,
        AnnouncementEngine.serial >= 0,
        IslandController.contextSerial >= 0,
        // Rofi's drawer is exported from these same tokens
        // (services/RofiThemeSync.qml). Touching it here is what makes that
        // singleton instantiate at startup: a colour export nothing reads
        // would never be made, and rofi would keep the stale palette.
        // NB the count below was 26 while the list already held 28 — it is
        // kept honest now that another entry joins it.
        RofiThemeSync.written,
        // Same reasoning for the IPC surface rofi's shell-backed modes
        // call (services/RofiBridge.qml): IpcHandler registers its target
        // when it is constructed, so a handler nothing references would
        // never exist and every rofi selection would return "Target not
        // found."
        RofiBridge.registered,
        // Workbench dock + gesture layer (plan). WorkbenchSettings loads
        // the JSON both sides read, WorkbenchController owns the `workbench`
        // IPC target and GestureRouter the `gesture` one — both targets must
        // exist from the first frame, before any surface references them.
        WorkbenchSettings.loaded,
        WorkbenchController.keyboardMode === false,
        GestureRouter.commitCount >= 0
    ].length === 33

    BarModule.Bar {
    }

    MediaModule.Media {
    }

    LauncherModule.Launcher {
    }

    // One primary popup at a time (PRD 13.1): every panel binds its
    // visibility to PopupManager, so opening one closes the others.
    // (The calendar is not instantiated here — it is a dashboard tab.)

    QuickSettingsModule.QuickSettings {
    }

    NotificationsModule.Notifications {
    }

    PowerMenuModule.PowerMenu {
    }

    // Toasts sit bottom-right and never alter the bar (PRD 15.3).
    ToastModule.Toast {
    }

    // Four-tab dashboard (PRD 22); opened from the keybind/launcher, and
    // from the clock pill which lands on its Calendar tab.
    DashboardModule.Dashboard {
    }

    // System monitor / task manager drawer (PRD 23); samples processes
    // only while it is visible.
    TaskManagerModule.TaskManager {
    }

    // Workspace overview overlay (PRD 24).
    WorkspaceOverviewModule.WorkspaceOverview {
    }

    // Stage shelf (Shadow Spaces §9): opt-in side column of the same
    // previews, suppressed whenever any primary popup is open.
    StageShelfModule.StageShelf {
    }

    // Workbench dock (plan): bottom-centred application dock + its
    // on-demand preview strip, action palette and edge reveal — an
    // overlay surface on its own `voidshell-workbench*` namespaces that
    // never resizes anything and never replaces bar/overview/shelf.
    WorkbenchModule.Workbench {
    }

    // Lock screen surface (PRD 25); hands authentication to hyprlock.
    LockScreenModule.LockScreen {
    }

    // Offscreen wallpaper palette grab (PRD 21.2); transparent and only
    // visible while ThemeService requests a dynamic-tone extraction.
    Comp.PaletteGrab {
    }

    // Living State Island surface (MASTER PROMPT §5 D/E): anchored below
    // the clock on its own `voidshell-island` namespace, visible only
    // while PopupManager reports an Island mode.
    IslandModule.IslandSurface {
    }

    // Optional wallpaper overlay (PRD 29-30): waveform, synced lyrics and
    // central clock behind all windows; hidden entirely while off.
    WallpaperOverlayModule.WallpaperOverlay {
    }

    // QA hook (PRD 43.2): `VOID_POPUP=<name> qs -c voidshell` opens one
    // popup at startup so runtime validation can exercise every panel
    // without manual clicking. Invalid names are ignored by PopupManager.
    Component.onCompleted: {
        const wanted = Quickshell.env("VOID_POPUP");
        if (wanted !== undefined && wanted !== null && wanted !== "") {
            PopupManager.open(wanted);
        }
    }
}
