import QtQuick
import "../../components" as Components

Item {
    id: root

    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    property real visualValue: value
    property bool dragging: false
    property bool pointerReady: false
    property color fillColor: "#eef3f8"
    property color backgroundColor: "#30000000"

    signal valueCommitted(real value)

    implicitHeight: 24

    Components.AnimationTokens { id: motion }

    function clamp(v, min, max) {
        return Math.max(min, Math.min(max, v));
    }

    function ratio() {
        if (maxValue <= minValue)
            return 0;
        return clamp((visualValue - minValue) / (maxValue - minValue), 0, 1);
    }

    function valueFromX(x) {
        if (track.width <= 0)
            return minValue;
        return minValue + clamp(x / track.width, 0, 1) * (maxValue - minValue);
    }

    function updateDrag(x) {
        visualValue = valueFromX(x);
        commitDelay.restart();
    }

    onValueChanged: {
        if (!dragging)
            visualValue = value;
    }

    Behavior on visualValue {
        NumberAnimation { duration: root.dragging ? 55 : 190; easing.type: Easing.OutCubic }
    }

    Timer {
        id: pointerDelay
        interval: motion.cursorDelay
        repeat: false
        onTriggered: root.pointerReady = sliderMouse.containsMouse
    }

    Timer {
        id: commitDelay
        interval: 85
        repeat: false
        onTriggered: root.valueCommitted(root.visualValue)
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: sliderMouse.containsMouse || root.dragging ? 7 : 5
        radius: height / 2
        color: root.backgroundColor
        border.width: 0
        antialiasing: true

        Behavior on height {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * root.ratio()
            radius: parent.radius
            color: root.fillColor
            opacity: 0.95
            border.width: 0
            antialiasing: true
        }

    }

    MouseArea {
        id: sliderMouse
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

        onPressed: function(mouse) {
            root.dragging = true;
            root.updateDrag(mouse.x);
            mouse.accepted = true;
        }

        onPositionChanged: function(mouse) {
            if (!pressed)
                return;
            root.updateDrag(mouse.x);
        }

        onReleased: function(mouse) {
            root.updateDrag(mouse.x);
            commitDelay.stop();
            root.valueCommitted(root.visualValue);
            root.dragging = false;
            mouse.accepted = true;
        }

        onCanceled: root.dragging = false
    }
}
