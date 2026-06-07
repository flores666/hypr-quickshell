import QtQuick
import QtQuick.Layouts
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: 28

    RowLayout {
        anchors.fill: parent
        spacing: 6

        Repeater {
            model: Services.ShellState.windows

            delegate: Components.WindowButton {
                required property var modelData

                Layout.alignment: Qt.AlignVCenter
                window: modelData
                active: Services.ShellState.isFocused(modelData.address)
                trayed: Services.ShellState.isTrayed(modelData.address)

                onClicked: {
                    if (Services.ShellState.isTrayed(modelData.address))
                        Services.ShellActions.restoreFromTray(modelData);
                    else
                        Services.ShellActions.focusWindow(modelData);
                }

                // Средняя кнопка мыши: свернуть в кастомный tray.
                onMiddleClicked: Services.ShellActions.toggleTray(modelData)

                // Правая кнопка пока тоже демонстрирует tray-логику.
                onRightClicked: Services.ShellActions.toggleTray(modelData)
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
