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

    function iconUrl(value) {
        var icon = String(value || "").trim();
        if (!icon)
            return "";
        if (icon.indexOf("file://") === 0 || icon.indexOf("qrc:/") === 0 || icon.indexOf("http://") === 0 || icon.indexOf("https://") === 0)
            return icon;
        if (icon.charAt(0) === "/")
            return "file://" + icon;
        return "";
    }

    implicitWidth: Math.max(76, label.implicitWidth + 34)
    implicitHeight: 24
    radius: 8
    color: active ? "#44ffffff" : trayed ? "#1a000000" : "#26000000"
    border.width: 0

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 7
        spacing: 5

        Item {
            implicitWidth: 15
            implicitHeight: 15

            Image {
                id: windowIconImage
                anchors.fill: parent
                source: root.iconUrl(root.window && root.window.icon ? root.window.icon : "")
                visible: source.toString().length > 0 && status !== Image.Error
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
            }

            Text {
                anchors.centerIn: parent
                visible: !windowIconImage.visible
                text: root.window && root.window.title ? String(root.window.title).substring(0, 1).toUpperCase() : "W"
                color: "#dff4f7fb"
                font.family: "Montserrat"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                font.kerning: false
            }
        }

        StyledText {
            id: label
            Layout.fillWidth: true
            text: root.window && root.window.title ? root.window.title : "Window"
            color: root.trayed ? "#9affffff" : "#f4f7fb"
            font.pixelSize: 11
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
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
