import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — system status pill (PRD 12.5 / 42).
// Every symbol is real state from a service singleton:
//   volume <- AudioService, wifi <- NetworkService,
//   bluetooth <- BluetoothService, battery <- PowerService,
//   bell + unread dot <- NotificationService,
//   recording dot + elapsed <- RecordingService.
// Regions whose hardware/backend does not exist are not rendered at all,
// so the pill never invents a value (PRD 37). Glyphs are written as
// verified Nerd Font codepoints (see docs/design-system.md) rather than
// pasted literals so a font fallback can never swap the symbol.
Comp.SlantedPill {
    id: root
    // Screen of the bar island this pill lives on (PRD 38).
    property var shellScreen: null
    height: Theme.barHeight

    // --- width budget (set by Bar.qml) ---------------------------------
    // The pill pays a budget cut with content padding, then segment gaps,
    // then (last resort) the battery percentage — every segment stays
    // visible and nothing is clipped.
    property int maxWidth: 4000
    readonly property int gapBase: Theme.space12
    readonly property int gapMin: 4
    readonly property int padBase: (Theme.slantDepth + 14) * 2
    readonly property int padMin: 6

    // Segment inventory: count and total width come from the segments
    // themselves (each has its own implicitWidth), never from the Row —
    // so `naturalWidth` stays independent of the adaptive spacing below.
    readonly property int segCount: (root.showRecording ? 1 : 0) + (root.showVolume ? 1 : 0) + (root.showWifi ? 1 : 0) + (root.showBluetooth ? 1 : 0) + (root.showBattery ? 1 : 0) + 1
    readonly property int gapCount: Math.max(1, root.segCount - 1)
    readonly property int segSum: (root.showRecording ? recSeg.implicitWidth : 0) + (root.showVolume ? volumeSeg.implicitWidth : 0) + (root.showWifi ? wifiSeg.implicitWidth : 0) + (root.showBluetooth ? btSeg.implicitWidth : 0) + (root.showBattery ? battGlyph.implicitWidth + Theme.space4 + battPct.implicitWidth + 8 : 0) + bellSeg.implicitWidth

    readonly property int naturalWidth: root.segSum + root.gapBase * root.gapCount + root.padBase
    // Levers, spent in this order: content padding, segment gaps, and —
    // only past both — the battery percentage text (the icon still shows
    // the real level and charging state, PRD 37).
    readonly property int padCap: (14 - root.padMin) * 2
    readonly property int gapCap: (root.gapBase - root.gapMin) * root.gapCount
    readonly property int pctWidth: battPct.implicitWidth + Theme.space4
    readonly property int coreCompressible: root.padCap + root.gapCap
    readonly property int compressible: root.coreCompressible + root.pctWidth

    width: Math.min(root.maxWidth, root.naturalWidth)
    readonly property int shrink: Math.max(0, root.naturalWidth - root.width)
    readonly property int padShrink: Math.min(root.shrink, root.padCap)
    readonly property int gapShrink: Math.min(Math.max(0, root.shrink - root.padShrink), root.gapCap)
    readonly property bool pctHidden: root.shrink > root.coreCompressible

    contentPad: 14 - Math.round(root.padShrink / 2)
    mirrored: true
    fillColor: Colors.glassBase
    borderColor: Colors.borderSubtle
    glowEnabled: true
    active: hit.containsMouse

    // fa-volume_off / fa-volume_low / fa-volume_up
    readonly property bool showVolume: AudioService.available
    readonly property string volumeGlyph: String.fromCodePoint(AudioService.muted || AudioService.volumePercent === 0 ? 0xF026 : (AudioService.volumePercent < 50 ? 0xF027 : 0xF028))
    readonly property color volumeColor: AudioService.muted ? Colors.textMuted : Colors.textSecondary

    // md-wifi_off / md-wifi / md-wifi_strength_{1..4}
    readonly property bool showWifi: NetworkService.wifiPresent
    readonly property string wifiGlyph: {
        if (!NetworkService.wifiEnabled) {
            return String.fromCodePoint(0xF05AA);
        }
        if (!NetworkService.wifiConnected) {
            return String.fromCodePoint(0xF05A9);
        }
        const pct = NetworkService.signalPercent;
        if (pct >= 75) {
            return String.fromCodePoint(0xF0928);
        }
        if (pct >= 50) {
            return String.fromCodePoint(0xF0925);
        }
        if (pct >= 25) {
            return String.fromCodePoint(0xF0922);
        }
        return String.fromCodePoint(0xF091F);
    }
    readonly property color wifiColor: {
        if (!NetworkService.wifiEnabled) {
            return Colors.textDisabled;
        }
        return NetworkService.wifiConnected ? Colors.textSecondary : Colors.textMuted;
    }

    // md-bluetooth_off / md-bluetooth_connect / md-bluetooth
    readonly property bool showBluetooth: BluetoothService.available
    readonly property string bluetoothGlyph: {
        if (!BluetoothService.powered) {
            return String.fromCodePoint(0xF00B2);
        }
        return String.fromCodePoint(BluetoothService.connectedCount > 0 ? 0xF00B1 : 0xF00AF);
    }
    readonly property color bluetoothColor: {
        if (!BluetoothService.powered) {
            return Colors.textDisabled;
        }
        return BluetoothService.connectedCount > 0 ? Colors.accentLight : Colors.textSecondary;
    }

    // md-battery* — hidden entirely when there is no laptop battery.
    readonly property bool showBattery: PowerService.hasBattery
    readonly property bool batteryCritical: PowerService.discharging && PowerService.percentage <= 15
    readonly property string batteryGlyph: {
        const pct = PowerService.percentage;
        if (PowerService.charging) {
            if (pct >= 98) {
                return String.fromCodePoint(0xF0085); // charging_100
            }
            if (pct > 90) {
                return String.fromCodePoint(0xF008B); // charging_90
            }
            if (pct > 70) {
                return String.fromCodePoint(0xF008A); // charging_70
            }
            if (pct > 50) {
                return String.fromCodePoint(0xF0089); // charging_50
            }
            if (pct > 30) {
                return String.fromCodePoint(0xF0088); // charging_30
            }
            if (pct > 20) {
                return String.fromCodePoint(0xF0086); // charging_20
            }
            return String.fromCodePoint(0xF0087); // charging_10
        }
        if (pct >= 95) {
            return String.fromCodePoint(0xF0079); // battery
        }
        if (pct <= 15) {
            return String.fromCodePoint(0xF0083); // battery_alert
        }
        return String.fromCodePoint(0xF0079 + Math.min(9, Math.max(1, Math.ceil(pct / 10)))); // battery_10..battery_90
    }
    readonly property color batteryColor: {
        if (root.batteryCritical) {
            return Colors.danger;
        }
        if (PowerService.charging || PowerService.fullyCharged) {
            return Colors.success;
        }
        return Colors.textSecondary;
    }

    // fa-bell / fa-bell_slash (do-not-disturb)
    readonly property string bellGlyph: String.fromCodePoint(NotificationService.dnd ? 0xF1F6 : 0xF0F3)
    readonly property color bellColor: {
        if (NotificationService.dnd) {
            return Colors.textMuted;
        }
        return NotificationService.hasUnread ? Colors.accentLight : Colors.textSecondary;
    }

    // Reserved recording space — visible only while a capture runs.
    readonly property bool showRecording: RecordingService.recording || RecordingService.state === "starting"

    Row {
        id: statusRow
        anchors.centerIn: parent
        // Adaptive: tightens towards gapMin while the pill is over budget.
        spacing: Math.max(root.gapMin, root.gapBase - Math.round(root.gapShrink / root.gapCount))

        // Recording indicator (PRD 12.5): gone again when recording stops.
        Row {
            id: recSeg
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space8
            visible: root.showRecording

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 9
                height: 9
                radius: 5
                color: Colors.danger

                SequentialAnimation on opacity {
                    running: root.showRecording
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.35
                        duration: 700
                    }
                    NumberAnimation {
                        to: 1.0
                        duration: 700
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: RecordingService.elapsedLabel
                font.family: Theme.fontMono
                font.weight: Font.Medium
                font.pixelSize: 12
                color: Colors.danger
            }
        }

        // Volume -> Quick Settings
        Item {
            id: volumeSeg
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showVolume
            implicitWidth: volumeText.implicitWidth + 8
            implicitHeight: root.height - 12

            Text {
                id: volumeText
                anchors.centerIn: parent
                text: root.volumeGlyph
                font.family: Theme.fontMono
                font.pixelSize: 15
                color: root.volumeColor
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: PopupManager.toggle("quickSettings", root.shellScreen, root)
            }
        }

        // Wi-Fi -> Quick Settings (hidden on wired-only machines)
        Item {
            id: wifiSeg
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showWifi
            implicitWidth: wifiText.implicitWidth + 8
            implicitHeight: root.height - 12

            Text {
                id: wifiText
                anchors.centerIn: parent
                text: root.wifiGlyph
                font.family: Theme.fontMono
                font.pixelSize: 15
                color: root.wifiColor
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: PopupManager.toggle("quickSettings", root.shellScreen, root)
            }
        }

        // Bluetooth -> Quick Settings (hidden with no adapter)
        Item {
            id: btSeg
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showBluetooth
            implicitWidth: btText.implicitWidth + 8
            implicitHeight: root.height - 12

            Text {
                id: btText
                anchors.centerIn: parent
                text: root.bluetoothGlyph
                font.family: Theme.fontMono
                font.pixelSize: 15
                color: root.bluetoothColor
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: PopupManager.toggle("quickSettings", root.shellScreen, root)
            }
        }

        // Battery -> Quick Settings (hidden with no battery)
        Item {
            id: battSeg
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showBattery
            implicitWidth: battRow.implicitWidth + 8
            implicitHeight: root.height - 12

            Row {
                id: battRow
                anchors.centerIn: parent
                spacing: Theme.space4

                Text {
                    id: battGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.batteryGlyph
                    font.family: Theme.fontMono
                    font.pixelSize: 15
                    color: root.batteryColor
                }

                Text {
                    id: battPct
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.pctHidden
                    text: PowerService.percentage + "%"
                    font.family: Theme.fontUi
                    font.weight: Font.Medium
                    font.pixelSize: 13
                    color: root.batteryColor
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: PopupManager.toggle("quickSettings", root.shellScreen, root)
            }
        }

        // Bell + unread dot -> Notifications
        Item {
            id: bellSeg
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: bellText.implicitWidth + 10
            implicitHeight: root.height - 12

            Text {
                id: bellText
                anchors.centerIn: parent
                text: root.bellGlyph
                font.family: Theme.fontMono
                font.pixelSize: 15
                color: root.bellColor
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: (root.height - 12 - bellText.implicitHeight) / 2
                width: 7
                height: 7
                radius: 4
                color: Colors.accentLight
                border.color: Colors.bgDeep
                border.width: 1
                visible: NotificationService.hasUnread && !NotificationService.dnd
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: PopupManager.toggle("notifications", root.shellScreen, root)
            }
        }
    }

    // Whole-pill hover state (hit-testing stays per segment above).
    MouseArea {
        id: hit
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}
