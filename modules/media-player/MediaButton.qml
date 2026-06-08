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
    property bool pointerReady: false

    signal clicked()

    implicitWidth: playerActive ? 270 : 0
    implicitHeight: 24
    visible: playerActive
    radius: 12
    color: popupOpen
        ? "#22ffffff"
        : (buttonMouse.pressed ? "#1cffffff" : (buttonMouse.containsMouse ? "#14ffffff" : "transparent"))
    border.width: 0
    clip: true
    scale: buttonMouse.pressed ? 0.972 : (buttonMouse.containsMouse || popupOpen ? 1.012 : 1.0)
    transformOrigin: Item.Center

    Behavior on color {
        ColorAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    Behavior on width {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    Timer {
        id: pointerDelay
        interval: 85
        repeat: false
        onTriggered: root.pointerReady = buttonMouse.containsMouse && root.playerActive
    }

    RowLayout {
        z: 1
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 6
        spacing: 5
        opacity: root.playerActive ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        MarqueePairText {
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
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
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: root.pointerReady ? Qt.PointingHandCursor : Qt.ArrowCursor
        z: 2

        onEntered: {
            root.pointerReady = false;
            pointerDelay.restart();
        }

        onExited: {
            pointerDelay.stop();
            root.pointerReady = false;
        }

        onClicked: function (mouse) {
            root.clicked();
            mouse.accepted = true;
        }
    }
}
