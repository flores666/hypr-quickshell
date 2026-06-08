import QtQuick

Item {
    id: root

    property bool targetVisible: false
    property bool renderVisible: false
    property bool inputEnabled: targetVisible && reveal > 0.72
    property real reveal: 0.0
    property int openDuration: 170
    property int closeDuration: 130
    property int closeSafetyDelay: closeDuration + 70
    property bool animating: revealAnimation.running || openKick.running || closeSafetyTimer.running

    signal opened()
    signal closed()

    visible: false
    width: 0
    height: 0

    function show() {
        closeSafetyTimer.stop();
        renderVisible = true;
        openKick.restart();
    }

    function hide() {
        openKick.stop();
        reveal = 0.0;
        closeSafetyTimer.restart();
    }

    function finishClose() {
        if (!targetVisible) {
            reveal = 0.0;
            renderVisible = false;
            closed();
        }
    }

    onTargetVisibleChanged: {
        if (targetVisible)
            show();
        else
            hide();
    }

    Component.onCompleted: {
        if (targetVisible) {
            renderVisible = true;
            reveal = 1.0;
        }
    }

    Behavior on reveal {
        NumberAnimation {
            id: revealAnimation
            duration: root.targetVisible ? root.openDuration : root.closeDuration
            easing.type: root.targetVisible ? Easing.OutCubic : Easing.InOutCubic
            onStopped: {
                if (root.targetVisible)
                    root.opened();
                else
                    root.finishClose();
            }
        }
    }

    Timer {
        id: openKick
        interval: 1
        repeat: false
        onTriggered: root.reveal = 1.0
    }

    Timer {
        id: closeSafetyTimer
        interval: root.closeSafetyDelay
        repeat: false
        onTriggered: root.finishClose()
    }
}
