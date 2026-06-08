import QtQuick

Item {
    id: root

    property string titleText: ""
    property string artistText: ""
    property color titleColor: "#f4f7fb"
    property color artistColor: "#929aa7"
    property color separatorColor: "#7f8896"
    property int pixelSize: 12
    property int titleWeight: Font.DemiBold
    property int artistWeight: Font.Medium
    property int gap: 42
    property real speedPixelsPerSecond: 22.68
    property real offset: 0
    property string resetKey: titleText + "\n" + artistText
    property string lastResetKey: ""

    implicitHeight: Math.max(titleA.implicitHeight, artistA.implicitHeight, pixelSize + 4)
    clip: true

    readonly property bool hasArtist: artistText !== ""
    readonly property real contentWidth: titleA.implicitWidth + (hasArtist ? separatorA.implicitWidth + artistA.implicitWidth : 0)
    readonly property bool shouldScroll: contentWidth > width && width > 0
    readonly property real scrollDistance: contentWidth + gap

    function resetScroll() {
        offset = 0;
        scrollDelay.restart();
    }

    onResetKeyChanged: {
        if (lastResetKey === resetKey)
            return;

        lastResetKey = resetKey;
        resetScroll();
    }

    onShouldScrollChanged: {
        if (shouldScroll)
            resetScroll();
        else {
            scrollDelay.stop();
            offset = 0;
        }
    }

    Timer {
        id: scrollDelay
        interval: 650
        repeat: false
    }

    Timer {
        id: scrollTimer
        property double lastTick: Date.now()
        interval: 16
        repeat: true
        running: root.shouldScroll && !scrollDelay.running

        onRunningChanged: lastTick = Date.now()

        onTriggered: {
            const now = Date.now();
            const delta = Math.max(0, Math.min(50, now - lastTick));
            lastTick = now;

            root.offset += root.speedPixelsPerSecond * delta / 1000;
            if (root.offset >= root.scrollDistance)
                root.offset = 0;
        }
    }

    Item {
        id: copyA
        width: root.contentWidth
        height: parent.height
        x: root.shouldScroll ? -root.offset : 0

        Text {
            id: titleA
            x: 0
            y: Math.round((root.height - implicitHeight) / 2)
            text: root.titleText
            color: root.titleColor
            font.pixelSize: root.pixelSize
            font.weight: root.titleWeight
            maximumLineCount: 1
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }

        Text {
            id: separatorA
            visible: root.hasArtist
            x: titleA.implicitWidth
            y: Math.round((root.height - implicitHeight) / 2)
            text: "  •  "
            color: root.separatorColor
            font.pixelSize: root.pixelSize
            font.weight: Font.DemiBold
            maximumLineCount: 1
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }

        Text {
            id: artistA
            visible: root.hasArtist
            x: titleA.implicitWidth + separatorA.implicitWidth
            y: Math.round((root.height - implicitHeight) / 2)
            text: root.artistText
            color: root.artistColor
            font.pixelSize: root.pixelSize
            font.weight: root.artistWeight
            maximumLineCount: 1
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }
    }

    Item {
        id: copyB
        visible: root.shouldScroll
        width: root.contentWidth
        height: parent.height
        x: copyA.x + root.contentWidth + root.gap

        Text {
            id: titleB
            x: 0
            y: Math.round((root.height - implicitHeight) / 2)
            text: root.titleText
            color: root.titleColor
            font.pixelSize: root.pixelSize
            font.weight: root.titleWeight
            maximumLineCount: 1
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }

        Text {
            id: separatorB
            visible: root.hasArtist
            x: titleB.implicitWidth
            y: Math.round((root.height - implicitHeight) / 2)
            text: "  •  "
            color: root.separatorColor
            font.pixelSize: root.pixelSize
            font.weight: Font.DemiBold
            maximumLineCount: 1
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }

        Text {
            visible: root.hasArtist
            x: titleB.implicitWidth + separatorB.implicitWidth
            y: Math.round((root.height - implicitHeight) / 2)
            text: root.artistText
            color: root.artistColor
            font.pixelSize: root.pixelSize
            font.weight: root.artistWeight
            maximumLineCount: 1
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }
    }
}
