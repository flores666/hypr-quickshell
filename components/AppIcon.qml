import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    property string icon: "application-x-executable"
    property string label: "App"
    property bool active: false
    property bool marked: false

    signal clicked()

    function iconUrl(value) {
        var icon = String(value || "").trim();
        if (!icon)
            return "";
        if (icon.indexOf("file://") === 0 || icon.indexOf("qrc:/") === 0 || icon.indexOf("http://") === 0 || icon.indexOf("https://") === 0)
            return icon;
        if (icon.charAt(0) === "/")
            return "file://" + icon;
        var themedPath = Quickshell.iconPath(icon, true);
        if (themedPath && themedPath.length > 0 && themedPath.indexOf("image-missing") < 0) {
            if (themedPath.indexOf("file://") === 0 || themedPath.indexOf("qrc:/") === 0)
                return themedPath;
            if (themedPath.charAt(0) === "/")
                return "file://" + themedPath;
            return themedPath;
        }
        return "";
    }

    implicitWidth: 38
    implicitHeight: 34
    radius: 11
    color: active ? "#55ffffff" : "#22000000"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 1

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 20
            implicitHeight: 20

            Image {
                id: appIconImage
                anchors.fill: parent
                source: root.iconUrl(root.icon)
                visible: source.toString().length > 0 && status !== Image.Error
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
            }

            Text {
                anchors.centerIn: parent
                visible: !appIconImage.visible
                text: root.label.substring(0, 1).toUpperCase()
                color: "#edf4fa"
                font.family: "Nunito"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                renderType: Text.QtRendering
                font.hintingPreference: Font.PreferNoHinting
                font.kerning: true
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: root.marked ? 12 : 4
            height: 3
            radius: 2
            color: root.marked ? "#f4f7fb" : "transparent"
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
