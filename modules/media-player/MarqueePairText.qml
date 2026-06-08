import QtQuick
import "../../components" as Components

Item {
    id: root

    property string titleText: ""
    property string artistText: ""
    property color titleColor: "#f4f7fb"
    property color artistColor: "#bcc5d0"
    property color separatorColor: "#9aa4b1"
    property int pixelSize: 12
    property int titleWeight: Font.DemiBold
    property int artistWeight: Font.Medium
    property int gap: 42
    property real speedPixelsPerSecond: 14
    property real offset: 0
    property string resetKey: titleText + "\n" + artistText
    property string lastResetKey: ""
    property string displayTitleText: titleText
    property string displayArtistText: artistText
    property string pendingTitleText: titleText
    property string pendingArtistText: artistText
    property real textOpacity: 1.0
    property bool completed: false

    implicitHeight: Math.max(titleA.implicitHeight, artistA.implicitHeight, pixelSize + 4)
    clip: true

    readonly property bool hasArtist: displayArtistText !== ""
    readonly property real contentWidth: titleA.implicitWidth + (hasArtist ? separatorA.implicitWidth + artistA.implicitWidth : 0)
    readonly property bool shouldScroll: contentWidth > width && width > 0
    readonly property real scrollDistance: contentWidth + gap

    function applyIncomingText() {
        displayTitleText = pendingTitleText;
        displayArtistText = pendingArtistText;
        resetScroll();
        textOpacity = 1.0;
    }

    function scheduleTextChange() {
        pendingTitleText = titleText;
        pendingArtistText = artistText;

        if (!completed) {
            displayTitleText = pendingTitleText;
            displayArtistText = pendingArtistText;
            return;
        }

        if (displayTitleText === pendingTitleText && displayArtistText === pendingArtistText)
            return;

        if (textOpacity <= 0.02) {
            textSwapTimer.restart();
            return;
        }

        textOpacity = 0.0;
        textSwapTimer.restart();
    }

    function resetScroll() {
        offset = 0;
        scrollDelay.restart();
    }

    onTitleTextChanged: scheduleTextChange()
    onArtistTextChanged: scheduleTextChange()

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

    Component.onCompleted: {
        completed = true;
        displayTitleText = titleText;
        displayArtistText = artistText;
        lastResetKey = resetKey;
    }

    Behavior on textOpacity {
        NumberAnimation { duration: 68; easing.type: Easing.OutCubic }
    }

    Timer {
        id: textSwapTimer
        interval: 72
        repeat: false
        onTriggered: root.applyIncomingText()
    }

    Timer {
        id: scrollDelay
        interval: 325
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
        opacity: root.textOpacity

        Components.StyledText {
            id: titleA
            x: 0
            y: Math.round((root.height - implicitHeight) / 2)
            text: root.displayTitleText
            color: root.titleColor
            font.pixelSize: root.pixelSize
            font.weight: root.titleWeight
            maximumLineCount: 1
        }

        Components.StyledText {
            id: separatorA
            visible: root.hasArtist
            x: titleA.implicitWidth
            y: Math.round((root.height - implicitHeight) / 2)
            text: "  •  "
            color: root.separatorColor
            font.pixelSize: root.pixelSize
            font.weight: Font.DemiBold
            maximumLineCount: 1
        }

        Components.StyledText {
            id: artistA
            visible: root.hasArtist
            x: titleA.implicitWidth + separatorA.implicitWidth
            y: Math.round((root.height - implicitHeight) / 2)
            text: root.displayArtistText
            color: root.artistColor
            font.pixelSize: root.pixelSize
            font.weight: root.artistWeight
            maximumLineCount: 1
        }
    }

    Item {
        id: copyB
        visible: root.shouldScroll
        width: root.contentWidth
        height: parent.height
        x: copyA.x + root.contentWidth + root.gap
        opacity: root.textOpacity

        Components.StyledText {
            id: titleB
            x: 0
            y: Math.round((root.height - implicitHeight) / 2)
            text: root.displayTitleText
            color: root.titleColor
            font.pixelSize: root.pixelSize
            font.weight: root.titleWeight
            maximumLineCount: 1
        }

        Components.StyledText {
            id: separatorB
            visible: root.hasArtist
            x: titleB.implicitWidth
            y: Math.round((root.height - implicitHeight) / 2)
            text: "  •  "
            color: root.separatorColor
            font.pixelSize: root.pixelSize
            font.weight: Font.DemiBold
            maximumLineCount: 1
        }

        Components.StyledText {
            visible: root.hasArtist
            x: titleB.implicitWidth + separatorB.implicitWidth
            y: Math.round((root.height - implicitHeight) / 2)
            text: root.displayArtistText
            color: root.artistColor
            font.pixelSize: root.pixelSize
            font.weight: root.artistWeight
            maximumLineCount: 1
        }
    }
}
