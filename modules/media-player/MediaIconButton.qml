import QtQuick

Item {
    id: root

    property url iconSource: ""
    property bool enabledState: true
    property int iconSize: 13

    signal clicked()

    implicitWidth: iconSize + 4
    implicitHeight: 18
    opacity: enabledState ? 1.0 : 0.35

    Image {
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: root.iconSource
        sourceSize.width: root.iconSize * 2
        sourceSize.height: root.iconSize * 2
        smooth: true
        mipmap: true
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabledState
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
