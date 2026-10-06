import QtQuick
import ".."

// VOID SHELL — toggle tile (quick-settings grid cell).
// Mockup: circular icon badge, title + subtitle, explicit ON/OFF pill on
// the right; the active tile washes purple over the dark glass.
// State is never color-only: the pill writes the state out in words (and
// when the pill is dropped — Wi-Fi/Bluetooth — the subtitle does), and
// an unavailable control is `enabled: false` with its reason written in
// place rather than silently dead (PRD 17.3 / 37).
Item {
    id: root
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property bool checked: false
    property bool enabled: true
    property bool busy: false
    // The ON/OFF pill on the right. Wi-Fi and Bluetooth set this false:
    // their subtitle already names the state, and the detail-dropdown
    // chevron takes the pill's slot instead (expandable tiles are always
    // pill-less, so they never overlap).
    property bool showStatePill: true
    // Optional detail dropdown affordance (Wi-Fi / Bluetooth): a chevron
    // in the right-center slot; set showStatePill false alongside it.
    property bool expandable: false
    property bool expanded: false
    signal toggled
    signal expandToggled

    implicitWidth: 160
    implicitHeight: 64
    opacity: root.enabled ? 1.0 : 0.55
    scale: tileArea.pressed && root.enabled ? Theme.pressedScale : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: Theme.durationFast
        }
    }

    // --- surface: dark glass / purple wash, crossfaded on toggle --------
    Rectangle {
        id: surfaceOff
        anchors.fill: parent
        radius: Theme.radiusMd
        color: tileArea.containsMouse && root.enabled ? Colors.glassHover : Colors.glassCard
        border.width: 1
        border.color: tileArea.containsMouse && root.enabled ? Colors.borderGlass : Colors.borderSubtle
        opacity: root.checked ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durationNormal
            }
        }
    }

    Rectangle {
        id: surfaceOn
        anchors.fill: parent
        radius: Theme.radiusMd
        border.width: 1
        border.color: Colors.borderAccentStrong
        // Vertical accent ladder — the mockup's diagonal sheen reads the
        // same at tile scale and keeps the whole shell on preset tokens.
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Colors.accentPrimary
            }
            GradientStop {
                position: 1.0
                color: Colors.accentStrong
            }
        }
        opacity: root.checked ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durationNormal
            }
        }
    }

    // --- circular icon badge --------------------------------------------
    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        radius: 18
        color: root.checked ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: root.checked ? Qt.rgba(1, 1, 1, 0.26) : Colors.borderSubtle

        Text {
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.fontMono
            font.pixelSize: 18
            color: root.checked ? Colors.textOnAccent : (root.enabled ? Colors.textSecondary : Colors.textDisabled)
            visible: root.icon !== ""
        }
    }

    // --- title / subtitle ------------------------------------------------
    Column {
        anchors.left: badge.right
        anchors.leftMargin: 10
        anchors.right: pill.left
        anchors.rightMargin: Theme.space8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.title
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 13
            color: root.checked ? Colors.textOnAccent : Colors.textPrimary
        }

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.subtitle
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: root.checked ? Qt.rgba(1, 1, 1, 0.78) : Colors.textMuted
            visible: root.subtitle !== ""
        }
    }

    // --- ON / OFF pill ---------------------------------------------------
    Rectangle {
        id: pill
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(36, pillLabel.implicitWidth + 14)
        height: 20
        radius: 10
        visible: root.showStatePill
        color: root.checked ? Colors.accentPrimary : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: root.checked ? Colors.accentLight : Colors.borderGlass

        Text {
            id: pillLabel
            anchors.centerIn: parent
            text: root.checked ? "ON" : "OFF"
            font.family: Theme.fontUi
            font.weight: Font.DemiBold
            font.pixelSize: 10
            font.letterSpacing: 0.5
            color: root.checked ? Colors.textOnAccent : Colors.textMuted
            visible: !root.busy
        }

        // Busy keeps the pill footprint and spins instead of lying about
        // the state (the backend has not answered yet).
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF110) // fa-spinner
            font.family: Theme.fontMono
            font.pixelSize: 12
            color: root.checked ? Colors.textOnAccent : Colors.textMuted
            visible: root.busy

            RotationAnimation on rotation {
                running: root.busy
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
            }
        }
    }

    MouseArea {
        id: tileArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled()
    }

    // --- detail-dropdown affordance --------------------------------------
    // Owns the right-center slot — the same spot the state pill occupies,
    // which is why expandable tiles set showStatePill: false (the two
    // never share the corner). Declared after the tile MouseArea so it
    // swallows its own clicks instead of toggling the radio. Rotates to
    // point up while the dropdown is open.
    Rectangle {
        id: chev
        visible: root.expandable
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        radius: 8
        scale: chevArea.pressed ? Theme.pressedScale : 1.0
        color: root.expanded ? Qt.rgba(1, 1, 1, 0.22) : (chevArea.containsMouse ? Colors.glassHover : Qt.rgba(1, 1, 1, 0.06))
        border.width: 1
        border.color: root.expanded ? Qt.rgba(1, 1, 1, 0.32) : (chevArea.containsMouse ? Colors.borderGlass : Colors.borderSubtle)

        Behavior on scale {
            NumberAnimation {
                duration: Theme.durationFast
            }
        }

        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF078) // fa-chevron-down
            font.family: Theme.fontMono
            font.pixelSize: 8
            color: root.expanded ? Colors.accentLight : (root.checked ? Qt.rgba(1, 1, 1, 0.85) : (chevArea.containsMouse ? Colors.textSecondary : Colors.textMuted))
            rotation: root.expanded ? 180 : 0

            Behavior on rotation {
                NumberAnimation {
                    duration: Theme.durationNormal
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: chevArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expandToggled()
        }
    }
}
