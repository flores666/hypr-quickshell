import QtQuick

Item {
    id: root

    property url iconSource: ""
    property bool enabledState: true
    property int iconSize: 15
    property int buttonSize: 24
    property color iconColor: "#eef3f8"
    property bool pointerReady: false

    signal clicked()

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    opacity: enabledState ? 1.0 : 0.34
    scale: !enabledState ? 1.0 : (buttonMouse.pressed ? 0.92 : (buttonMouse.containsMouse ? 1.075 : 1.0))
    transformOrigin: Item.Center

    onEnabledStateChanged: {
        if (!enabledState) {
            pointerDelay.stop();
            pointerReady = false;
        }
    }

    Behavior on opacity {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
        NumberAnimation { duration: buttonMouse.pressed ? 160 : 300; easing.type: Easing.OutCubic }
    }

    Timer {
        id: pointerDelay
        interval: 80
        repeat: false
        onTriggered: root.pointerReady = buttonMouse.containsMouse && root.enabledState
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: height / 2
        color: !root.enabledState
            ? "transparent"
            : (buttonMouse.pressed ? "#28ffffff" : (buttonMouse.containsMouse ? "#18ffffff" : "#00ffffff"))
        border.width: 0
        antialiasing: true

        Behavior on color {
            ColorAnimation { duration: buttonMouse.pressed ? 150 : 320; easing.type: Easing.OutCubic }
        }
    }

    Image {
        id: icon
        anchors.centerIn: parent
        width: root.iconSize + (buttonMouse.containsMouse && root.enabledState ? 1.5 : 0)
        height: width
        source: root.iconSource
        sourceSize.width: Math.ceil(width * Screen.devicePixelRatio * 2)
        sourceSize.height: Math.ceil(height * Screen.devicePixelRatio * 2)
        smooth: true
        mipmap: true
        opacity: !root.enabledState ? 0.7 : (buttonMouse.containsMouse ? 1.0 : 0.86)

        Behavior on width {
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: 270; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        enabled: root.enabledState
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
            root.clicked();
            mouse.accepted = true;
        }
    }
}
