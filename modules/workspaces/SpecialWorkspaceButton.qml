import QtQuick
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    property bool pointerReady: false
    property bool interactiveEnabled: true
    readonly property bool active: Services.ShellState.isSpecialWorkspaceActive(Services.ShellActions.minimizedWorkspace)

    signal toggled()

    implicitWidth: 28
    implicitHeight: 24
    radius: 12
    color: active
        ? (buttonMouse.pressed ? "#44ffffff" : (buttonMouse.containsMouse ? "#36ffffff" : "#2cffffff"))
        : (buttonMouse.pressed ? "#22000000" : (buttonMouse.containsMouse ? "#18000000" : "transparent"))
    border.width: 0
    antialiasing: true

    Components.AnimationTokens { id: motion }

    Behavior on color {
        ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: activeGlow
        anchors.centerIn: parent
        width: root.active ? 22 : 10
        height: root.active ? 22 : 10
        radius: width / 2
        color: "#24ffffff"
        opacity: root.active ? 1.0 : 0.0
        antialiasing: true

        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
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
        opacity: root.active ? 1.0 : (buttonMouse.containsMouse ? 0.95 : 0.72)

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
        enabled: root.interactiveEnabled
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: root.interactiveEnabled && root.pointerReady ? Qt.PointingHandCursor : Qt.ArrowCursor

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
