import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Services.SystemTray
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — system tray pill (PRD 12.5): available without destroying
// the reference layout. Hidden entirely when nothing registers an item;
// shows at most `visibleLimit` items and folds the rest behind a `+N`
// overflow toggle so a chatty tray can never stretch the bar.
Comp.SlantedPill {
    id: root
    height: Theme.barHeight
    visible: trayItems.length > 0 && root.maxWidth >= root.minNatural
    fillColor: Colors.glassBase
    borderColor: Colors.borderSubtle
    glowEnabled: true

    // --- width budget (set by Bar.qml) ---------------------------------
    // A chatty tray folds items away (its designed behaviour) before any
    // other right-island pill has to give up space, and disappears only
    // when even one item plus the overflow chip cannot fit the budget.
    property int maxWidth: 4000
    readonly property int padBase: (Theme.slantDepth + 14) * 2
    readonly property int slot: 26 + Theme.space8   // icon slot + gap
    readonly property int overflowW: 34             // "+N" chip + gap

    // Natural size of the default (folded) presentation. It reads the
    // tray model and `visibleLimit` only — never `maxWidth` — so Bar can
    // budget from it without a binding loop.
    readonly property int naturalWidth: !trayItems.length ? 0 : Math.min(trayItems.length, visibleLimit) * slot - Theme.space8 + (trayItems.length > visibleLimit ? overflowW : 0) + padBase
    readonly property int minNatural: !trayItems.length ? 0 : 26 + (trayItems.length > visibleLimit ? overflowW : 0) + padBase
    readonly property int foldable: Math.max(0, naturalWidth - minNatural)

    // Live presentation: as many items as the allowance fits, expanded
    // never widens the pill past that allowance.
    readonly property int capacity: Math.max(1, Math.floor((maxWidth - padBase + Theme.space8 - (trayItems.length > visibleLimit ? overflowW : 0)) / slot))
    readonly property int limit: Math.max(1, Math.min(expanded ? trayItems.length : visibleLimit, capacity))

    readonly property var trayItems: SystemTray.items ? SystemTray.items.values : []
    readonly property int visibleLimit: 3
    property bool expanded: false
    readonly property var shownItems: trayItems.slice(0, limit)
    readonly property int overflowCount: Math.max(0, trayItems.length - limit)

    width: Math.min(maxWidth, limit * slot - Theme.space8 + (overflowCount > 0 ? overflowW : 0) + padBase)

    // A tray item is actionable unless it only exposes a menu; items that
    // are passive (no activation, no menu) are still rendered dimmed
    // rather than hidden, so the tray mirrors real registration.
    function iconUrl(item) {
        if (!item || !item.icon) {
            return "";
        }
        return Quickshell.iconPath(item.icon, "");
    }

    function activate(item) {
        if (!item) {
            return;
        }
        if (item.hasMenu || item.onlyMenu) {
            item.display(root.Window.window, Math.round(root.width / 2), root.height);
            return;
        }
        item.activate();
    }

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: Theme.space8

        Repeater {
            model: root.shownItems

            Item {
                required property var modelData
                width: 26
                height: root.height - 14

                Image {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: root.iconUrl(modelData)
                    asynchronous: true
                    visible: source !== ""
                }

                // No themed icon asset (some SNI items only ship a title):
                // fall back to the first letter so the slot stays readable.
                Text {
                    anchors.centerIn: parent
                    text: modelData && modelData.title ? modelData.title.charAt(0).toUpperCase() : ""
                    font.family: Theme.fontUi
                    font.weight: Font.DemiBold
                    font.pixelSize: 13
                    color: Colors.textSecondary
                    visible: root.iconUrl(modelData) === "" && text !== ""
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activate(modelData)
                }
            }
        }

        // Overflow toggle — appears only past the visible limit.
        Item {
            width: overflowText.implicitWidth + 8
            height: root.height - 14
            visible: root.overflowCount > 0

            Text {
                id: overflowText
                anchors.centerIn: parent
                text: root.expanded ? "−" : "+" + root.overflowCount
                font.family: Theme.fontUi
                font.weight: Font.DemiBold
                font.pixelSize: 12
                color: Colors.textMuted
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }
    }
}
