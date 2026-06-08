import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property bool playerActive: false
    property bool popupOpen: false
    property string titleText: ""
    property string artistText: ""
    property string resetKey: ""
    property real position: 0
    property real durationValue: 0
    property color accentStrongColor: "#e8eef6"
    property color mutedTextColor: "#929aa7"

    signal clicked()

    implicitWidth: playerActive ? 270 : 0
    implicitHeight: 24
    visible: playerActive
    radius: 12
    color: popupOpen ? "#20ffffff" : "transparent"
    border.color: popupOpen ? "#28ffffff" : "transparent"
    border.width: 1
    clip: true

    Behavior on color {
        ColorAnimation {
            duration: 140
        }
    }

    Behavior on width {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    RowLayout {
        z: 1
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 5

        MarqueePairText {
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter
            titleText: root.titleText
            artistText: root.artistText
            titleColor: root.playerActive ? "#f4f7fb" : "#9ba5b2"
            artistColor: root.mutedTextColor
            separatorColor: "#7f8896"
            pixelSize: 12
            titleWeight: Font.DemiBold
            artistWeight: Font.Medium
            speedPixelsPerSecond: 22.68
            resetKey: root.resetKey
        }

        MediaProgressBar {
            Layout.preferredWidth: root.playerActive ? 74 : 0
            Layout.preferredHeight: 12
            Layout.alignment: Qt.AlignVCenter
            value: root.position
            duration: root.durationValue
            seekEnabled: false
            barHeight: 3
            backgroundColor: "#22ffffff"
            fillColor: root.accentStrongColor
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        z: 0

        onClicked: function (mouse) {
            root.clicked();
            mouse.accepted = true;
        }

        onEntered: if (!root.popupOpen)
            root.color = "#14ffffff"
        onExited: if (!root.popupOpen)
            root.color = "transparent"
    }
}
