import QtQuick

Rectangle {
    id: root

    property string sourceUrl: ""
    property string fallbackSourceUrl: ""
    property int sourceKey: 0
    property int fallbackPixelSize: 24
    property string fallbackText: "♪"
    property color fallbackTextColor: "#dfe7f0"
    property bool imageVisible: displayedSource !== ""
    property string displayedSource: ""
    property string pendingSource: ""
    property bool triedFallback: false

    color: "#18ffffff"
    border.color: "#24ffffff"
    border.width: 1
    clip: true

    function reloadCover() {
        const next = sourceUrl || "";
        const fallback = fallbackSourceUrl || "";

        if (next === "") {
            if (displayedSource === "" && fallback !== "") {
                triedFallback = true;
                pendingSource = fallback;
                preload.source = "";
                reloadTimer.restart();
            }
            return;
        }

        if (next === displayedSource)
            return;

        triedFallback = false;
        pendingSource = next;
        preload.source = "";
        reloadTimer.restart();
    }

    onSourceUrlChanged: reloadCover()
    onFallbackSourceUrlChanged: reloadCover()
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
                root.displayedSource = String(source);
                return;
            }

            if (status === Image.Error && source !== "") {
                const fallback = root.fallbackSourceUrl || "";
                if (!root.triedFallback && fallback !== "" && fallback !== String(source)) {
                    root.triedFallback = true;
                    root.pendingSource = fallback;
                    preload.source = "";
                    reloadTimer.restart();
                }
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
