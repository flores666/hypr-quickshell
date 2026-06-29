import QtQuick
import "../services" as Services

Item {
    id: root

    anchors.fill: parent
    visible: true
    enabled: true
    z: 1000000

    // This boundary must not participate in hover. A HoverHandler overlay steals
    // hover from real menu rows and sliders. We only need to mark the current
    // mouse press as an inside-popup press, then immediately let the event
    // propagate to the actual control below.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: false
        propagateComposedEvents: true
        preventStealing: false

        onPressed: function(mouse) {
            Services.ShellState.suppressCurrentExternalPointerClose();
            mouse.accepted = false;
        }

        onReleased: function(mouse) { mouse.accepted = false; }
        onClicked: function(mouse) { mouse.accepted = false; }
        onDoubleClicked: function(mouse) { mouse.accepted = false; }
        onPressAndHold: function(mouse) { mouse.accepted = false; }
    }
}
