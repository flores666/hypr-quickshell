import QtQuick

Rectangle {
    id: root

    property color glassColor: "#66141822"
    property color strokeColor: "#33ffffff"
    property int radiusSize: 16

    radius: radiusSize
    color: glassColor
    border.color: strokeColor
    border.width: 1

    // Настоящий blur делает Hyprland через layerrule.
    // Здесь только прозрачный glass-слой, чтобы blur было видно.
}
