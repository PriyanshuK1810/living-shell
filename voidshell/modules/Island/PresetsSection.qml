import QtQuick
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — preset block (MASTER PROMPT F18): apply one of the saved
// control bundles, or snapshot the machine's current control state under
// a name. Applying reports how many actions actually landed — a preset
// step whose backend is missing is skipped, never faked.
Item {
    id: root

    property string status: ""

    implicitHeight: col.implicitHeight

    Timer {
        interval: 4000
        repeat: false
        running: root.status !== ""
        onTriggered: root.status = ""
    }

    Column {
        id: col
        width: parent.width
        spacing: Theme.space8

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.status
            font.family: Theme.fontUi
            font.pixelSize: 11
            color: Colors.accentLight
            visible: root.status !== ""
        }

        Flow {
            width: parent.width
            spacing: Theme.space4

            Repeater {
                model: PresetStore.presets

                Comp.TextButton {
                    required property var modelData
                    label: modelData.name
                    height: 28
                    onClicked: {
                        const applied = PresetStore.apply(modelData.id);
                        root.status = applied > 0
                            ? modelData.name + " applied (" + applied + " changes)"
                            : modelData.name + " could not be applied";
                    }
                }
            }
        }

        // Snapshot the live control state (real values, never guessed).
        Row {
            width: parent.width
            spacing: Theme.space4

            TextInput {
                id: nameField
                width: parent.width - 96
                height: 28
                verticalAlignment: Text.AlignVCenter
                color: Colors.textPrimary
                selectionColor: Colors.accentStrong
                font.family: Theme.fontUi
                font.pixelSize: 12
                clip: true
                // No shell, no paste target: a plain label.
                validator: RegularExpressionValidator {
                    regularExpression: /^.{0,24}$/
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Preset name"
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Colors.textDisabled
                    visible: nameField.text === "" && !nameField.activeFocus
                }
            }

            Comp.TextButton {
                width: 92
                height: 28
                label: "Save"
                onClicked: {
                    const ok = PresetStore.saveCurrent(nameField.text);
                    root.status = ok ? "Preset saved" : "Name the preset first";
                    if (ok) {
                        nameField.text = "";
                    }
                }
            }
        }
    }
}
