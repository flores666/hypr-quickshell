import QtQuick
import "../../components" as Components

Item {
    id: root

    required property var item
    property var panelRoot: null
    property var motion: null
    property real itemSize: 54
    property real panelHeight: 62
    property int hoverRevealDelay: 135
    property bool externalDragging: false
    property bool canDrag: false
    property bool itemActive: false
    property bool itemOtherWorkspace: false
    property real dragShift: 0
    property var iconSource: ""
    property string firstLetter: "?"

    signal showTooltipRequested(var item, real centerX)
    signal hideTooltipRequested(var item)
    signal openContextRequested(var item, real centerX)
    signal activateRequested(var item)
    signal dragBeginRequested(var item, real panelX)
    signal dragUpdateRequested(real panelX)
    signal dragFinishRequested()
    signal dragCancelRequested()

    width: itemSize
    height: panelHeight
    opacity: item.open || item.pinned ? 1.0 : 0.76
    z: dragging ? 20 : 0

    property bool dragging: false
    property bool blockNextClick: false
    property real pressX: 0
    property real dragOffsetX: 0
    readonly property real visualOffsetX: dragging ? dragOffsetX : dragShift
    property bool hoverActive: false

    function panelXFromMouse(mouse) {
        if (panelRoot)
            return appMouse.mapToItem(panelRoot, mouse.x, mouse.y).x;
        return x + mouse.x;
    }

    function centerXInPanel() {
        if (panelRoot)
            return root.mapToItem(panelRoot, width / 2, height / 2).x;
        return x + width / 2;
    }

    function hoverDuration() {
        return motion ? motion.hoverDuration : 130;
    }

    function pressDuration() {
        return motion ? motion.pressDuration : 90;
    }

    function releaseDuration() {
        return motion ? motion.releaseDuration : 130;
    }

    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Timer {
        id: hoverDelayTimer
        interval: root.hoverRevealDelay
        repeat: false
        onTriggered: root.hoverActive = appMouse.containsMouse && !root.externalDragging
    }

    Item {
        id: visualContent
        width: parent.width
        height: parent.height
        x: root.visualOffsetX
        y: 0
        scale: appMouse.pressed ? 0.96 : 1.0
        transformOrigin: Item.Center

        Behavior on x {
            enabled: !root.dragging
            NumberAnimation { duration: 230; easing.type: Easing.OutCubic }
        }
        Behavior on scale { NumberAnimation { duration: appMouse.pressed ? root.pressDuration() : root.releaseDuration(); easing.type: Easing.OutCubic } }

        Rectangle {
            id: hoverBackground
            anchors.centerIn: parent
            width: 48
            height: 48
            radius: 16
            color: root.itemActive
                ? "#2cffffff"
                : (appMouse.pressed ? "#20ffffff" : (root.hoverActive ? "#16ffffff" : "transparent"))
            border.width: 0
            antialiasing: true

            Behavior on color { ColorAnimation { duration: root.hoverDuration(); easing.type: Easing.OutCubic } }
        }

        Image {
            id: appIcon
            anchors.centerIn: hoverBackground
            width: 37
            height: 37
            source: root.iconSource
            visible: source.toString().length > 0 && status !== Image.Error
            opacity: root.item.launching ? 0.58 : 0.94
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: fallbackBubble
            anchors.centerIn: hoverBackground
            width: 36
            height: 36
            radius: 13
            color: "#1cffffff"
            visible: appIcon.source.toString().length === 0 || appIcon.status === Image.Error
            antialiasing: true

            Components.StyledText {
                anchors.centerIn: parent
                text: root.firstLetter
                color: "#eef3f8"
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            id: launchPulse
            anchors.centerIn: hoverBackground
            width: 46
            height: 46
            radius: 16
            color: "transparent"
            border.width: 1
            border.color: "#55ffffff"
            opacity: root.item.launching ? 0.45 : 0.0
            scale: root.item.launching ? 1.06 : 0.94
            antialiasing: true

            Behavior on opacity { NumberAnimation { duration: 135; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: openIndicator
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            width: root.itemActive ? 24 : (root.item.open ? 11 : 0)
            height: root.item.open ? 4 : 0
            radius: 3
            color: root.itemActive ? "#f4f7fb" : (root.itemOtherWorkspace ? "#86ffffff" : "#c8ffffff")
            opacity: root.item.open ? 0.95 : 0.0
            antialiasing: true

            Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        id: appMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            hoverDelayTimer.stop();
            root.hoverActive = !root.externalDragging;
            root.showTooltipRequested(root.item, root.centerXInPanel());
        }
        onExited: {
            hoverDelayTimer.stop();
            root.hoverActive = false;
            root.hideTooltipRequested(root.item);
        }

        onPressed: function(mouse) {
            root.pressX = root.panelXFromMouse(mouse);
            root.dragging = false;
            root.blockNextClick = false;
        }

        onPositionChanged: function(mouse) {
            if (!root.canDrag || (mouse.buttons & Qt.LeftButton) === 0)
                return;

            var panelX = root.panelXFromMouse(mouse);
            var dx = panelX - root.pressX;
            if (Math.abs(dx) > 8 && !root.dragging) {
                root.dragging = true;
                root.hoverActive = false;
                root.dragBeginRequested(root.item, panelX);
            }
            if (root.dragging) {
                root.dragOffsetX = dx;
                root.dragUpdateRequested(panelX);
            }
        }

        onReleased: function(mouse) {
            if (!root.dragging)
                return;

            root.blockNextClick = true;
            root.dragging = false;
            root.dragOffsetX = 0;
            root.dragFinishRequested();
            mouse.accepted = true;
        }

        onCanceled: {
            root.dragging = false;
            root.dragOffsetX = 0;
            root.blockNextClick = false;
            root.hideTooltipRequested(root.item);
            root.dragCancelRequested();
        }

        onClicked: function(mouse) {
            if (root.blockNextClick) {
                root.blockNextClick = false;
                mouse.accepted = true;
                return;
            }

            if (mouse.button === Qt.RightButton)
                root.openContextRequested(root.item, root.centerXInPanel());
            else
                root.activateRequested(root.item);

            mouse.accepted = true;
        }
    }
}
