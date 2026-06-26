import QtQuick
import QtQuick.Layouts
import "../../components" as Components

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
    property color mutedTextColor: "#bcc5d0"
    property bool pointerReady: false
    property real reveal: playerActive ? 1.0 : 0.0
    readonly property bool renderVisible: playerActive || reveal > 0.001

    signal clicked()
    signal closeRequested()

    implicitWidth: Math.round(270 * reveal)
    implicitHeight: 24
    visible: renderVisible
    radius: 12
    color: popupOpen
        ? "#22ffffff"
        : (buttonMouse.pressed ? "#1cffffff" : (buttonMouse.containsMouse ? "#14ffffff" : "transparent"))
    border.width: 0
    clip: true
    opacity: reveal
    scale: 0.965 + reveal * 0.035
    transformOrigin: Item.Center

    Components.AnimationTokens { id: motion }

    Behavior on color {
        ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic }
    }

    Behavior on reveal {
        NumberAnimation { duration: 165; easing.type: Easing.OutCubic }
    }

    Behavior on implicitWidth {
        NumberAnimation { duration: 165; easing.type: Easing.OutCubic }
    }

    Behavior on opacity {
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
        NumberAnimation { duration: 165; easing.type: Easing.OutCubic }
    }

    Timer {
        id: pointerDelay
        interval: motion.cursorDelay
        repeat: false
        onTriggered: root.pointerReady = buttonMouse.containsMouse && root.playerActive
    }

    RowLayout {
        z: 1
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 6
        spacing: 5
        opacity: root.reveal

        Behavior on opacity {
            NumberAnimation { duration: 125; easing.type: Easing.OutCubic }
        }

        MarqueePairText {
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            titleText: root.titleText
            artistText: root.artistText
            titleColor: root.playerActive ? "#f4f7fb" : "#9ba5b2"
            artistColor: root.mutedTextColor
            separatorColor: "#9aa4b1"
            pixelSize: 11
            titleWeight: Font.DemiBold
            artistWeight: Font.Medium
            speedPixelsPerSecond: 22.68
            resetKey: root.resetKey
        }

        MediaProgressBar {
            Layout.preferredWidth: Math.round(74 * root.reveal)
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
        hoverEnabled: root.renderVisible
        enabled: root.renderVisible && root.reveal > 0.72
        acceptedButtons: Qt.LeftButton | Qt.RightButton
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
            if (mouse.button === Qt.RightButton)
                root.closeRequested();
            else
                root.clicked();
            mouse.accepted = true;
        }
    }
}
