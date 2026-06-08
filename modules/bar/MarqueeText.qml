import QtQuick

Item {
    id: root

    property string text: ""
    property color textColor: "#f4f7fb"
    property int pixelSize: 12
    property int fontWeight: Font.Medium
    property int gap: 42
    property bool centerWhenStatic: false
    property int horizontalAlignment: Text.AlignLeft
    property real speedPixelsPerSecond: 28
    property real offset: 0

    implicitHeight: Math.max(labelA.implicitHeight, pixelSize + 4)
    clip: true

    readonly property real contentWidth: labelA.implicitWidth
    readonly property bool shouldScroll: contentWidth > width && width > 0
    readonly property real scrollDistance: contentWidth + gap

    function resetScroll() {
        offset = 0;
    }

    onTextChanged: resetScroll()
    onWidthChanged: resetScroll()
    onShouldScrollChanged: resetScroll()

    Timer {
        interval: 16
        repeat: true
        running: root.shouldScroll
        onTriggered: {
            root.offset += root.speedPixelsPerSecond * interval / 1000;
            if (root.offset >= root.scrollDistance)
                root.offset = 0;
        }
    }

    Text {
        id: labelA
        y: Math.round((root.height - implicitHeight) / 2)
        x: root.shouldScroll
            ? -root.offset
            : (root.centerWhenStatic ? Math.max(0, (root.width - implicitWidth) / 2) : 0)
        text: root.text
        color: root.textColor
        font.pixelSize: root.pixelSize
        font.weight: root.fontWeight
        horizontalAlignment: root.horizontalAlignment
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        font.kerning: false
    }

    Text {
        id: labelB
        visible: root.shouldScroll
        y: labelA.y
        x: labelA.x + labelA.implicitWidth + root.gap
        text: root.text
        color: root.textColor
        font.pixelSize: root.pixelSize
        font.weight: root.fontWeight
        horizontalAlignment: root.horizontalAlignment
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        font.kerning: false
    }
}
