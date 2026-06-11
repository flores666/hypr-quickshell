import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Rectangle {
    id: root

    property string icon: "application-x-executable"
    property string label: "App"
    property bool active: false
    property bool marked: false

    signal clicked()

    implicitWidth: 38
    implicitHeight: 34
    radius: 11
    color: active ? "#55ffffff" : "#22000000"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 1

        IconImage {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 20
            implicitHeight: 20
            source: root.icon
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
