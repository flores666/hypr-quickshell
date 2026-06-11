import QtQuick

Rectangle {
    id: root

    property color glassColor: "#66141822"
    property int radiusSize: 16

    radius: radiusSize
    color: glassColor
    border.width: 0

    // Hyprland applies real blur through layerrule. This item only provides
    // the transparent glass layer that makes compositor blur visible.
}
