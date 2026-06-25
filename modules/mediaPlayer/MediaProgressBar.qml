import QtQuick
import "../../components" as Components

Item {
    id: root

    property real value: 0
    property real duration: 0
    property bool seekEnabled: false
    property int barHeight: 5
    property color backgroundColor: "#2affffff"
    property color fillColor: "#eef3f8"
    property color handleColor: "#eef3f8"
    property bool showHandle: false
    property bool dragging: false
    property real dragValue: 0
    property bool pointerReady: false
    property real animatedValue: clampedValue

    readonly property bool interactive: seekEnabled && safeDuration() > 0
    readonly property bool hovered: progressMouse.containsMouse && interactive
    readonly property real animatedBarHeight: barHeight + (hovered || dragging ? 2 : 0)
    readonly property real clampedValue: safeDuration() > 0 ? clamp(value || 0, 0, safeDuration()) : 0

    signal seekRequested(real seconds)
    signal dragStarted()
    signal dragEnded()

    implicitHeight: Math.max(14, barHeight + 8)

    Components.AnimationTokens { id: motion }

    onClampedValueChanged: {
        if (!dragging)
            animatedValue = clampedValue;
    }

    onDragValueChanged: {
        if (dragging)
            animatedValue = dragValue;
    }

    onDraggingChanged: {
        if (dragging)
            animatedValue = dragValue;
        else
            animatedValue = clampedValue;
    }

    onInteractiveChanged: {
        if (!interactive) {
            pointerDelay.stop();
            pointerReady = false;
        }
    }

    Behavior on animatedValue {
        NumberAnimation {
            duration: root.dragging ? 58 : 260
            easing.type: root.dragging ? Easing.OutQuad : Easing.OutCubic
        }
    }

    function clamp(v, min, max) {
        return Math.max(min, Math.min(max, v));
    }

    function safeDuration() {
        return duration > 0 ? duration : 0;
    }

    function currentValue() {
        return clamp(animatedValue || 0, 0, safeDuration());
    }

    function valueFromX(x) {
        if (safeDuration() <= 0 || track.width <= 0)
            return 0;
        return clamp(x / track.width, 0, 1) * safeDuration();
    }

    Timer {
        id: pointerDelay
        interval: motion.cursorDelay
        repeat: false
        onTriggered: root.pointerReady = progressMouse.containsMouse && root.interactive
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.animatedBarHeight
        radius: height / 2
        color: root.backgroundColor
        opacity: root.safeDuration() > 0 ? (root.hovered || root.dragging ? 1.0 : 0.82) : 0.42
        border.width: 0
        antialiasing: true

        Behavior on height {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.safeDuration() > 0
                ? root.clamp(parent.width * (root.currentValue() / root.safeDuration()), 0, parent.width)
                : 0
            radius: parent.radius
            color: root.fillColor
            opacity: root.hovered || root.dragging ? 1.0 : 0.9
            border.width: 0
            antialiasing: true

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        id: progressMouse
        anchors.fill: parent
        enabled: root.interactive
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
            root.dragValue = root.valueFromX(mouse.x);
            root.dragStarted();
            mouse.accepted = true;
        }

        onPositionChanged: function(mouse) {
            if (!pressed)
                return;
            root.dragValue = root.valueFromX(mouse.x);
        }

        onReleased: function(mouse) {
            root.dragValue = root.valueFromX(mouse.x);
            root.seekRequested(root.dragValue);
            root.dragging = false;
            root.dragEnded();
            mouse.accepted = true;
        }

        onCanceled: {
            root.dragging = false;
            root.dragEnded();
        }
    }
}
