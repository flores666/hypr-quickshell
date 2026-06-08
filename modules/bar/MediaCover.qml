import QtQuick

Rectangle {
    id: root

    property string sourceUrl: ""
    property int sourceKey: 0
    property int fallbackPixelSize: 24
    property string fallbackText: "♪"
    property color fallbackTextColor: "#dfe7f0"
    property bool imageVisible: displayedSource !== ""
    property string displayedSource: ""
    property string pendingSource: ""

    color: "#18ffffff"
    border.color: "#24ffffff"
    border.width: 1
    clip: true

    function reloadCover() {
        pendingSource = sourceUrl || "";

        if (pendingSource === "") {
            displayedSource = "";
            preload.source = "";
            return;
        }

        preload.source = "";
        reloadTimer.restart();
    }

    onSourceUrlChanged: reloadCover()
    onSourceKeyChanged: reloadCover()

    Timer {
        id: reloadTimer
        interval: 1
        repeat: false
        onTriggered: preload.source = root.pendingSource
    }

    Image {
        id: shown
        anchors.fill: parent
        source: root.displayedSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: root.displayedSource !== "" && status !== Image.Error
        opacity: visible ? 1.0 : 0.0

        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Image {
        id: preload
        visible: false
        asynchronous: true
        cache: false

        onStatusChanged: {
            if (status === Image.Ready && source !== "") {
                root.displayedSource = root.pendingSource;
            } else if (status === Image.Error && source !== "") {
                if (root.pendingSource === root.sourceUrl)
                    root.displayedSource = "";
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !shown.visible
        text: root.fallbackText
        color: root.fallbackTextColor
        font.pixelSize: root.fallbackPixelSize
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        font.kerning: false
    }
}
