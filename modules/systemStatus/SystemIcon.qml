import QtQuick

Item {
    id: root

    property url source
    property real iconOpacity: 1.0

    implicitWidth: 18
    implicitHeight: 18

    Image {
        id: iconImage
        anchors.centerIn: parent
        width: 17
        height: 17
        source: root.source
        sourceSize.width: 34
        sourceSize.height: 34
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        opacity: root.iconOpacity

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }
    }
}
