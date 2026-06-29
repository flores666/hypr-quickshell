import QtQuick

Rectangle {
    id: root

    property color glassColor: "#98000000"
    property int radiusSize: 18

    radius: radiusSize
    color: "transparent"
    border.width: 0
    clip: true
    antialiasing: true

    GlassPanel {
        anchors.fill: parent
        radiusSize: root.radiusSize
        glassColor: root.glassColor
        clip: true
        antialiasing: true
    }
}
