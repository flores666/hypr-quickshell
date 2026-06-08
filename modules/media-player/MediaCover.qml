import QtQuick
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root

    property string sourceUrl: ""
    property string fallbackSourceUrl: ""
    property int sourceKey: 0
    property int fallbackPixelSize: 24
    property string fallbackText: "♪"
    property color fallbackTextColor: "#dfe7f0"
    property bool imageVisible: displayedSource !== "" || incomingSource !== ""
    property string displayedSource: ""
    property string pendingSource: ""
    property string incomingSource: ""
    property bool incomingActive: false
    property bool waitingForShownReady: false
    property real incomingOpacity: 0.0
    property bool triedFallback: false

    color: "#18ffffff"
    border.width: 0
    clip: false
    antialiasing: true

    function clearCover() {
        displayedSource = "";
        pendingSource = "";
        incomingSource = "";
        incomingActive = false;
        waitingForShownReady = false;
        incomingOpacity = 0.0;
        preload.source = "";
        shownReadyTimer.stop();
        commitIncomingTimer.stop();
        incomingFadeTimer.stop();
    }

    function startPreload(value) {
        if (value === "") {
            clearCover();
            return;
        }

        pendingSource = value;
        incomingSource = "";
        incomingActive = false;
        waitingForShownReady = false;
        incomingOpacity = 0.0;
        shownReadyTimer.stop();
        commitIncomingTimer.stop();
        incomingFadeTimer.stop();
        preload.source = "";
        reloadTimer.restart();
    }

    function commitIncomingCover() {
        if (incomingSource === "")
            return;

        waitingForShownReady = true;
        displayedSource = incomingSource;
        shownReadyTimer.restart();
    }

    function finishIncomingCover() {
        incomingSource = "";
        incomingActive = false;
        waitingForShownReady = false;
        incomingOpacity = 0.0;
        shownReadyTimer.stop();
        incomingFadeTimer.stop();
    }

    function reloadCover() {
        const next = sourceUrl || "";
        const fallback = fallbackSourceUrl || "";

        if (next === "") {
            if (fallback !== "") {
                triedFallback = true;
                startPreload(fallback);
            } else {
                clearCover();
            }
            return;
        }

        if (next === displayedSource && shown.status === Image.Ready)
            return;

        if (next === pendingSource && preload.status === Image.Loading)
            return;

        triedFallback = false;
        startPreload(next);
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

    Timer {
        id: commitIncomingTimer
        interval: 260
        repeat: false
        onTriggered: root.commitIncomingCover()
    }

    Timer {
        id: incomingFadeTimer
        interval: 16
        repeat: false
        onTriggered: root.incomingOpacity = 1.0
    }

    Timer {
        id: shownReadyTimer
        interval: 16
        repeat: true
        onTriggered: {
            if (!root.waitingForShownReady) {
                stop();
                return;
            }

            if (shown.status === Image.Ready && String(shown.source) === root.displayedSource)
                root.finishIncomingCover();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.color
        antialiasing: true
    }

    Image {
        id: shown
        anchors.fill: parent
        source: root.displayedSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
        sourceSize.width: Math.max(64, Math.ceil(root.width * Screen.devicePixelRatio * 2))
        sourceSize.height: Math.max(64, Math.ceil(root.height * Screen.devicePixelRatio * 2))
        visible: false

        onStatusChanged: {
            if (root.waitingForShownReady && status === Image.Ready && String(source) === root.displayedSource)
                root.finishIncomingCover();
        }
    }

    Image {
        id: preload
        anchors.fill: parent
        source: ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
        sourceSize.width: Math.max(64, Math.ceil(root.width * Screen.devicePixelRatio * 2))
        sourceSize.height: Math.max(64, Math.ceil(root.height * Screen.devicePixelRatio * 2))
        visible: false

        onStatusChanged: {
            if (status === Image.Ready && source !== "") {
                const readySource = String(source);

                if (readySource === root.displayedSource) {
                    root.incomingSource = "";
                    root.incomingActive = false;
                    root.waitingForShownReady = false;
                    root.incomingOpacity = 0.0;
                    return;
                }

                root.incomingSource = readySource;
                root.incomingOpacity = 0.0;
                root.incomingActive = true;
                incomingFadeTimer.restart();
                commitIncomingTimer.restart();
                return;
            }

            if (status === Image.Error && source !== "") {
                const fallback = root.fallbackSourceUrl || "";
                if (!root.triedFallback && fallback !== "" && fallback !== String(source)) {
                    root.triedFallback = true;
                    root.startPreload(fallback);
                }
            }
        }
    }

    Rectangle {
        id: roundedMask
        anchors.fill: parent
        radius: root.radius
        visible: false
        antialiasing: true
    }

    Item {
        id: currentImageLayer
        anchors.fill: parent
        visible: root.displayedSource !== "" && shown.status === Image.Ready
        layer.enabled: true
        layer.smooth: true
        layer.samples: 4

        OpacityMask {
            anchors.fill: parent
            source: shown
            maskSource: roundedMask
            cached: true
        }
    }

    Item {
        id: incomingImageLayer
        anchors.fill: parent
        visible: root.incomingSource !== "" && preload.status === Image.Ready
        opacity: root.incomingOpacity
        layer.enabled: true
        layer.smooth: true
        layer.samples: 4

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        OpacityMask {
            anchors.fill: parent
            source: preload
            maskSource: roundedMask
            cached: true
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !currentImageLayer.visible && !incomingImageLayer.visible
        text: root.fallbackText
        color: root.fallbackTextColor
        font.pixelSize: root.fallbackPixelSize
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        font.kerning: false
    }
}
