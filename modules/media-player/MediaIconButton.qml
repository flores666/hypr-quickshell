import QtQuick

Item {
    id: root

    property url iconSource: ""
    property bool enabledState: true
    property int iconSize: 15
    property int buttonSize: 24
    property color iconColor: "#eef3f8"

    signal clicked()

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    opacity: enabledState ? 1.0 : 0.34
    scale: !enabledState ? 1.0 : (buttonMouse.pressed ? 0.94 : (buttonMouse.containsMouse ? 1.06 : 1.0))
    transformOrigin: Item.Center

    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: height / 2
        color: !root.enabledState
            ? "transparent"
            : (buttonMouse.pressed ? "#26ffffff" : (buttonMouse.containsMouse ? "#18ffffff" : "#00ffffff"))
        border.color: !root.enabledState
            ? "transparent"
            : (buttonMouse.containsMouse ? "#20ffffff" : "#00ffffff")
        border.width: 1
        antialiasing: true

        Behavior on color {
            ColorAnimation { duration: 210; easing.type: Easing.OutCubic }
        }

        Behavior on border.color {
            ColorAnimation { duration: 210; easing.type: Easing.OutCubic }
        }
    }

    Image {
        id: icon
        anchors.centerIn: parent
        width: root.iconSize + (buttonMouse.containsMouse && root.enabledState ? 1 : 0)
        height: width
        source: root.iconSource
        sourceSize.width: Math.ceil(width * Screen.devicePixelRatio * 2)
        sourceSize.height: Math.ceil(height * Screen.devicePixelRatio * 2)
        smooth: true
        mipmap: true
        opacity: !root.enabledState ? 0.7 : (buttonMouse.containsMouse ? 1.0 : 0.88)

        Behavior on width {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        enabled: root.enabledState
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: function(mouse) {
            root.clicked();
            mouse.accepted = true;
        }
    }
}
