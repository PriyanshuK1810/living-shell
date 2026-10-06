import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// VOID SHELL — wallpaper palette grab surface (PRD §21.2).
// Canvas pixel reads require a rendered window and ThemeService is a
// singleton without one, so this component hosts the offscreen 48×48
// draw: it exists only while ThemeService publishes a grabUrl, and its
// content is fully transparent (opacity 0), so nothing flickers. The
// extracted buffer goes back to ThemeService, which owns the math and
// the token state.
PanelWindow {
    id: win

    readonly property bool grabbing: ThemeService.grabUrl !== ""
    property bool grabPending: false

    visible: win.grabbing
    color: "transparent"
    anchors {
        top: true
        left: true
    }
    implicitWidth: 48
    implicitHeight: 48
    // Fully transparent draw target: blur here would halo, zones ignored.
    WlrLayershell.namespace: "voidshell-palette-grab"
    exclusiveZone: -1

    Image {
        id: swatch
        visible: false
        asynchronous: true
        source: ThemeService.grabUrl
        onStatusChanged: {
            if (status === Image.Ready) {
                Qt.callLater(win.tryGrab);
            } else if (status === Image.Error) {
                console.warn("[voidshell] could not read wallpaper for palette:", source);
                ThemeService.grabDone();
            }
        }
    }

    Canvas {
        id: canvas
        width: 48
        height: 48
        visible: true
        opacity: 0

        // The image can finish loading before the canvas has a context;
        // retry the queued grab as soon as it is ready.
        onAvailableChanged: {
            if (available && win.grabPending) {
                win.grabPending = false;
                Qt.callLater(win.tryGrab);
            }
        }
    }

    function tryGrab() {
        if (swatch.status !== Image.Ready) {
            return;
        }
        if (!canvas.available) {
            win.grabPending = true;
            return;
        }
        const ctx = canvas.getContext("2d");
        ctx.clearRect(0, 0, 48, 48);
        ctx.drawImage(swatch, 0, 0, 48, 48);
        let data;
        try {
            data = ctx.getImageData(0, 0, 48, 48).data;
        } catch (e) {
            console.warn("[voidshell] palette extraction failed:", e);
            ThemeService.grabDone();
            return;
        }
        ThemeService.adoptPixelData(data);
        ThemeService.grabDone();
    }
}
