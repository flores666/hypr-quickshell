import QtQuick

Rectangle {
    id: root

    property color glassColor: "#66141822"
    property int radiusSize: 16

    radius: radiusSize
    color: glassColor
    border.width: 0

    // Настоящий blur делает Hyprland через layerrule.
    // Здесь только прозрачный glass-слой, чтобы blur было видно.
}
