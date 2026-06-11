import QtQuick
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    property bool pointerReady: false

    signal toggled()

    implicitWidth: 28
    implicitHeight: 24
    radius: 12
    color: buttonMouse.pressed ? "#22000000" : (buttonMouse.containsMouse ? "#18000000" : "transparent")
    border.width: 0
    antialiasing: true

    Components.AnimationTokens { id: motion }

    Behavior on color {
        ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic }
    }

    Image {
        id: icon
        anchors.centerIn: parent
        width: 17
        height: 17
        source: Qt.resolvedUrl("icons/special-workspace.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        opacity: buttonMouse.containsMouse ? 0.95 : 0.72

        Behavior on opacity {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }
    }

    Timer {
        id: pointerDelay
        interval: motion.cursorDelay
        repeat: false
        onTriggered: root.pointerReady = buttonMouse.containsMouse
    }

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: root.pointerReady ? Qt.PointingHandCursor : Qt.ArrowCursor

        onEntered: {
            root.pointerReady = false;
            pointerDelay.restart();
        }

        onExited: {
            pointerDelay.stop();
            root.pointerReady = false;
        }

        onClicked: function(mouse) {
            mouse.accepted = true;
            root.toggled();
            Services.ShellActions.toggleSpecialWorkspace();
        }
    }
}
