import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../services" as Services

Rectangle {
    id: root

    property var window
    property bool active: window && Services.ShellState.isFocused(window.address)
    property bool trayed: window && Services.ShellState.isTrayed(window.address)

    signal clicked
    signal middleClicked
    signal rightClicked

    implicitWidth: Math.max(76, label.implicitWidth + 34)
    implicitHeight: 24
    radius: 8
    color: active ? "#44ffffff" : trayed ? "#1a1b2330" : "#261b2330"
    border.width: 0

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 7
        spacing: 5

        IconImage {
            implicitWidth: 15
            implicitHeight: 15
            source: root.window && root.window.icon ? root.window.icon : "application-x-executable"
        }

        Text {
            id: label
            Layout.fillWidth: true
            text: root.window && root.window.title ? root.window.title : "Window"
            color: root.trayed ? "#88ffffff" : "#eef3f8"
            font.pixelSize: 11
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton)
                root.middleClicked();
            else if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
    }
}
