import QtQuick

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

    readonly property bool interactive: seekEnabled && safeDuration() > 0
    readonly property bool hovered: progressMouse.containsMouse && interactive
    readonly property real animatedBarHeight: barHeight + (hovered || dragging ? 2 : 0)

    signal seekRequested(real seconds)
    signal dragStarted()
    signal dragEnded()

    implicitHeight: Math.max(14, barHeight + 8)

    function clamp(v, min, max) {
        return Math.max(min, Math.min(max, v));
    }

    function safeDuration() {
        return duration > 0 ? duration : 0;
    }

    function currentValue() {
        if (dragging)
            return dragValue;
        return clamp(value || 0, 0, safeDuration());
    }

    function valueFromX(x) {
        if (safeDuration() <= 0 || track.width <= 0)
            return 0;
        return clamp(x / track.width, 0, 1) * safeDuration();
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.animatedBarHeight
        radius: height / 2
        color: root.backgroundColor
        opacity: root.safeDuration() > 0 ? (root.hovered || root.dragging ? 1.0 : 0.86) : 0.42
        antialiasing: true

        Behavior on height {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
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
            opacity: root.hovered || root.dragging ? 1.0 : 0.92
            antialiasing: true

            Behavior on width {
                enabled: !root.dragging
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            id: handle
            width: root.hovered || root.dragging ? 11 : 8
            height: width
            radius: width / 2
            color: root.handleColor
            visible: root.showHandle && root.interactive
            anchors.verticalCenter: parent.verticalCenter
            x: root.clamp(fill.width - width / 2, 0, parent.width - width)
            opacity: root.hovered || root.dragging ? 1.0 : 0.0
            scale: progressMouse.pressed ? 0.92 : (root.hovered ? 1.05 : 1.0)
            antialiasing: true

            Behavior on width {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Behavior on scale {
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
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

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
