import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

RowLayout {
    id: root

    required property var modelData
    required property var popupRoot

    width: parent ? parent.width : 1
    height: 31
    spacing: 8

    Rectangle {
        id: appIconBox
        width: 22
        height: 22
        radius: 11
        color: appIconImage.status === Image.Ready ? "#1b000000" : "#26000000"
        border.width: appIconImage.status === Image.Ready ? 0 : 1
        border.color: "#28000000"
        antialiasing: true
        clip: true

        readonly property string iconSource: root.popupRoot.fileIconSource(root.modelData.icon || "")

        Image {
            id: appIconImage
            anchors.fill: parent
            anchors.margins: 3
            source: appIconBox.iconSource
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
        }

        Components.StyledText {
            anchors.centerIn: parent
            visible: appIconImage.status !== Image.Ready
            text: root.popupRoot.firstLetter(root.modelData.app, root.modelData.name || "A")
            color: "#eef3f8"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    Components.StyledText {
        Layout.preferredWidth: 92
        text: root.modelData.name || root.modelData.app || "App"
        color: "#c4ceda"
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    SystemSlider {
        Layout.fillWidth: true
        value: root.modelData.volume || 0
        minValue: 0
        maxValue: 100
        onValueCommitted: function (value) {
            Services.SystemStatus.setAppVolume(root.modelData.index, value);
        }
    }
}
