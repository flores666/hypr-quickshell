import QtQuick
import "../../components" as Components

Item {
    id: root

    property string value: ""
    property color textColor: "#eef3f8"
    property int pixelSize: 12
    property int weight: Font.DemiBold
    property int horizontalAlignment: Text.AlignLeft
    property int verticalAlignment: Text.AlignVCenter
    property int elideMode: Text.ElideRight
    property int animationDuration: 130

    property string currentText: value
    property string previousText: ""
    property real currentOpacity: 1.0
    property real previousOpacity: 0.0

    implicitHeight: Math.max(currentLabel.implicitHeight, previousLabel.implicitHeight)
    clip: true

    onValueChanged: {
        var nextValue = String(value || "");
        if (nextValue === currentText)
            return;

        previousText = currentText;
        currentText = nextValue;
        previousOpacity = 1.0;
        currentOpacity = 0.0;
        fadeInTimer.restart();
    }

    Timer {
        id: fadeInTimer
        interval: 1
        repeat: false
        onTriggered: {
            root.previousOpacity = 0.0;
            root.currentOpacity = 1.0;
        }
    }

    Components.StyledText {
        id: previousLabel
        anchors.fill: parent
        text: root.previousText
        color: root.textColor
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        horizontalAlignment: root.horizontalAlignment
        verticalAlignment: root.verticalAlignment
        elide: root.elideMode
        opacity: root.previousOpacity

        Behavior on opacity {
            NumberAnimation {
                duration: root.animationDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    Components.StyledText {
        id: currentLabel
        anchors.fill: parent
        text: root.currentText
        color: root.textColor
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        horizontalAlignment: root.horizontalAlignment
        verticalAlignment: root.verticalAlignment
        elide: root.elideMode
        opacity: root.currentOpacity

        Behavior on opacity {
            NumberAnimation {
                duration: root.animationDuration
                easing.type: Easing.OutCubic
            }
        }
    }
}
