import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 38
    color: "transparent"
    surfaceFormat.opaque: false

    WlrLayershell.namespace: "quickshell:taskbar"
    WlrLayershell.layer: WlrLayer.Top

    exclusiveZone: 38

    property date now: new Date()
    property bool calendarOpen: false
    property bool mediaOpen: false
    property date visibleMonth: new Date(now.getFullYear(), now.getMonth(), 1)

    property var activePlayer: null
    property string lastActivePlayerKey: ""

    property bool isDragging: false
    property real pendingSeekPosition: -1
    property string pendingSeekTrackId: ""
    property double pendingSeekStartedAt: 0

    property string currentTrackId: ""
    property string currentTitle: ""
    property string currentArtist: ""
    property string currentAlbum: ""
    property string currentCoverSource: ""
    property int coverNonce: 0
    property real currentPosition: 0
    property real currentLength: 0
    property bool playbackStatus: activePlayer ? activePlayer.isPlaying : false
    property real visualPosition: pendingSeekPosition >= 0 ? pendingSeekPosition : currentPosition

    readonly property color accentColor: "#f4f7fb"
    readonly property color accentStrongColor: "#e8eef6"
    readonly property color softAccentColor: "#cfd8e4"
    readonly property color mutedTextColor: "#929aa7"
    readonly property color darkPanelColor: "#eb202332"
    readonly property color darkPanelSoftColor: "#e0181c27"

    onActivePlayerChanged: {
        if (activePlayer)
            lastActivePlayerKey = playerStableKey(activePlayer);
        syncMetadataFromPlayer(true);
        syncPositionFromPlayer(true);
    }

    function playersList() {
        if (!Mpris || !Mpris.players || !Mpris.players.values)
            return [];
        return Mpris.players.values;
    }

    function playerStableKey(player) {
        if (!player)
            return "";
        return String(player.dbusName || player.desktopEntry || player.identity || player.uniqueId || "player");
    }

    function playerTrackKey(player) {
        if (!player)
            return "";

        var stable = playerStableKey(player);
        var uid = player.uniqueId !== undefined && player.uniqueId !== null ? String(player.uniqueId) : "";
        if (uid !== "")
            return stable + ":" + uid;

        return stable + ":" + String(player.trackTitle || "") + ":" + String(player.trackArtist || "") + ":" + String(player.trackAlbum || "") + ":" + String(player.length || 0) + ":" + String(player.trackArtUrl || "");
    }

    function refreshActivePlayer() {
        const list = playersList();
        if (list.length === 0) {
            activePlayer = null;
            return;
        }

        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].isPlaying) {
                activePlayer = list[i];
                lastActivePlayerKey = playerStableKey(list[i]);
                return;
            }
        }

        if (activePlayer) {
            const currentKey = playerStableKey(activePlayer);
            for (let j = 0; j < list.length; j++) {
                if (list[j] && playerStableKey(list[j]) === currentKey)
                    return;
            }
        }

        if (lastActivePlayerKey !== "") {
            for (let k = 0; k < list.length; k++) {
                if (list[k] && playerStableKey(list[k]) === lastActivePlayerKey) {
                    activePlayer = list[k];
                    return;
                }
            }
        }

        activePlayer = list[0];
        lastActivePlayerKey = playerStableKey(activePlayer);
    }

    function normalizeCoverUrl(url) {
        var value = String(url || "").trim();
        if (value === "")
            return "";

        if (value.indexOf("file://") === 0 || value.indexOf("http://") === 0 || value.indexOf("https://") === 0 || value.indexOf("image://") === 0 || value.indexOf("qrc:/") === 0)
            return value;

        if (value.charAt(0) === "/")
            return "file://" + value;

        return value;
    }

    function syncMetadataFromPlayer(forceCoverReload) {
        const player = activePlayer;
        if (!player) {
            if (currentTrackId !== "") {
                currentTrackId = "";
                currentTitle = "No media";
                currentArtist = "";
                currentAlbum = "";
                currentCoverSource = "";
                currentPosition = 0;
                currentLength = 0;
                coverNonce++;
            }
            closeMediaPopup();
            return;
        }

        const nextTrackId = playerTrackKey(player);
        const nextTitle = player.trackTitle || player.identity || "Unknown Title";
        const nextArtist = player.trackArtist || "";
        const nextAlbum = player.trackAlbum || "";
        const nextCover = normalizeCoverUrl(player.trackArtUrl || "");
        const trackChanged = nextTrackId !== currentTrackId;
        const coverChanged = nextCover !== currentCoverSource;

        if (trackChanged) {
            pendingSeekPosition = -1;
            pendingSeekTrackId = "";
            pendingSeekStartedAt = 0;
        }

        currentTrackId = nextTrackId;
        currentTitle = nextTitle;
        currentArtist = nextArtist;
        currentAlbum = nextAlbum;
        currentLength = Number(player.length || 0);

        if (trackChanged || coverChanged || forceCoverReload) {
            currentCoverSource = nextCover;
            coverNonce++;
        }
    }

    function syncPositionFromPlayer(force) {
        const player = activePlayer;
        if (!player) {
            currentPosition = 0;
            currentLength = 0;
            return;
        }

        currentLength = Number(player.length || 0);
        const actual = Math.max(0, Number(player.position || 0));

        if (isDragging && !force)
            return;

        if (pendingSeekPosition >= 0 && pendingSeekTrackId === currentTrackId && !force) {
            const age = Date.now() - pendingSeekStartedAt;
            if (Math.abs(actual - pendingSeekPosition) <= 2.5) {
                pendingSeekPosition = -1;
                pendingSeekTrackId = "";
                pendingSeekStartedAt = 0;
                currentPosition = actual;
                return;
            }

            if (age < 3500)
                return;

            pendingSeekPosition = -1;
            pendingSeekTrackId = "";
            pendingSeekStartedAt = 0;
        }

        currentPosition = actual;
    }

    function two(n) {
        return n < 10 ? "0" + n : "" + n;
    }

    function formatTime(d) {
        return two(d.getHours()) + ":" + two(d.getMinutes());
    }

    function centerDateText(d) {
        return Qt.formatDateTime(d, "ddd MMM d") + "  " + formatTime(d);
    }

    function monthTitle(d) {
        return Qt.formatDateTime(d, "MMMM yyyy");
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    function mondayOffset(date) {
        return (new Date(date.getFullYear(), date.getMonth(), 1).getDay() + 6) % 7;
    }

    function calendarDay(index) {
        return index - mondayOffset(visibleMonth) + 1;
    }

    function calendarDayValid(index) {
        const day = calendarDay(index);
        return day >= 1 && day <= daysInMonth(visibleMonth.getFullYear(), visibleMonth.getMonth());
    }

    function isToday(day) {
        return day === now.getDate()
            && visibleMonth.getMonth() === now.getMonth()
            && visibleMonth.getFullYear() === now.getFullYear();
    }

    function changeMonth(delta) {
        visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + delta, 1);
    }

    function closeMediaPopup() {
        mediaOpen = false;
    }

    function closePopups() {
        calendarOpen = false;
        closeMediaPopup();
    }

    function toggleCalendar() {
        visibleMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        calendarOpen = !calendarOpen;
        if (calendarOpen) {
                closeMediaPopup();
        }
    }

    function openMediaPopup() {
        if (!activePlayer)
            return;

        calendarOpen = false;
        mediaOpen = true;
    }

    function handleMediaLeftClick() {
        if (mediaOpen) {
            closeMediaPopup();
            return;
        }

        openMediaPopup();
    }

    function mediaTitle() {
        if (!activePlayer)
            return "No media";
        return currentTitle || activePlayer.identity || "Unknown Title";
    }

    function mediaArtist() {
        if (!activePlayer)
            return "";
        return currentArtist || activePlayer.identity || "Media Player";
    }

    function mediaSubtitle() {
        if (!activePlayer)
            return "Open a player with MPRIS support";

        if (currentArtist && currentAlbum)
            return currentArtist + ", " + currentAlbum;
        if (currentArtist)
            return currentArtist;
        return activePlayer.identity || "Media Player";
    }

    function compactLineText() {
        if (!activePlayer)
            return "No media";
        return mediaTitle() + "  •  " + mediaArtist();
    }

    function minimalLineText() {
        if (!activePlayer)
            return "No media";
        return mediaTitle() + "  •  " + mediaArtist();
    }

    function hasDuration() {
        if (!activePlayer)
            return false;
        if (activePlayer.lengthSupported === false)
            return false;
        return currentLength > 0;
    }

    function canSeek() {
        return !!activePlayer && activePlayer.canSeek && hasDuration();
    }

    function formatSeconds(value) {
        if (!value || value < 0)
            return "0:00";

        const total = Math.floor(value);
        const minutes = Math.floor(total / 60);
        const seconds = total % 60;
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    function performSeek(seconds) {
        const player = activePlayer;
        if (!player || !canSeek())
            return;

        const target = Math.max(0, Math.min(Number(seconds || 0), currentLength));
        const previousPosition = Number(player.position || currentPosition || 0);
        pendingSeekPosition = target;
        pendingSeekTrackId = currentTrackId;
        pendingSeekStartedAt = Date.now();
        currentPosition = target;

        try {
            if (player.positionSupported !== false) {
                player.position = target;
            } else {
                player.seek(target - previousPosition);
            }
            seekVerifyTimer.restart();
        } catch (e) {
            pendingSeekPosition = -1;
            pendingSeekTrackId = "";
            pendingSeekStartedAt = 0;
            syncPositionFromPlayer(true);
            console.log("media seek failed", e);
        }
    }

    function togglePlayPause() {
        const player = activePlayer;
        if (!player || !player.canTogglePlaying)
            return;
        player.togglePlaying();
    }

    function popupX(popupWidth) {
        const raw = centerGroup.x + mediaButton.x + mediaButton.width / 2 - popupWidth / 2;
        return Math.max(8, Math.min(raw, root.width - popupWidth - 8));
    }

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
        onDateChanged: root.now = date
    }

    Timer {
        id: playerRefreshTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.refreshActivePlayer()
    }

    Timer {
        id: positionTimer
        interval: 500
        repeat: true
        running: root.activePlayer && root.activePlayer.isPlaying
        onTriggered: {
            if (root.activePlayer)
                root.activePlayer.positionChanged();
            root.syncPositionFromPlayer(false);
            root.syncMetadataFromPlayer(false);
        }
    }

    Timer {
        id: seekVerifyTimer
        interval: 1200
        repeat: false
        onTriggered: root.syncPositionFromPlayer(false)
    }

    Connections {
        target: root.activePlayer

        function onTrackChanged() {
            root.syncMetadataFromPlayer(true);
            root.syncPositionFromPlayer(true);
        }

        function onPostTrackChanged() {
            root.syncMetadataFromPlayer(true);
            root.syncPositionFromPlayer(true);
        }

        function onTrackArtUrlChanged() {
            root.syncMetadataFromPlayer(true);
        }

        function onMetadataChanged() {
            root.syncMetadataFromPlayer(false);
        }

        function onPositionChanged() {
            root.syncPositionFromPlayer(false);
        }

        function onLengthChanged() {
            root.syncPositionFromPlayer(false);
        }

        function onIsPlayingChanged() {
            root.playbackStatus = root.activePlayer ? root.activePlayer.isPlaying : false;
        }
    }

    Component.onCompleted: {
        refreshActivePlayer();
        syncMetadataFromPlayer(true);
        syncPositionFromPlayer(true);
    }

    Components.GlassPanel {
        id: background
        anchors.fill: parent
        anchors.margins: 4
        radiusSize: 12
        glassColor: "#b010131a"
        strokeColor: "#66ffffff"
    }

    Item {
        id: barContent
        anchors.fill: background
        anchors.leftMargin: 8
        anchors.rightMargin: 8

        WorkspaceStrip {
            id: workspaces
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            id: centerGroup
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                id: clockButton
                width: clockText.implicitWidth + 22
                height: 26
                radius: 13
                color: root.calendarOpen ? "#26ffffff" : "transparent"
                border.color: root.calendarOpen ? "#33ffffff" : "transparent"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }

                Text {
                    id: clockText
                    anchors.centerIn: parent
                    text: root.centerDateText(root.now)
                    color: "#eef3f8"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.kerning: false
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleCalendar()
                    onEntered: if (!root.calendarOpen) clockButton.color = "#14ffffff"
                    onExited: if (!root.calendarOpen) clockButton.color = "transparent"
                }
            }

            Rectangle {
                id: mediaButton
                width: root.activePlayer ? 334 : 104
                height: 26
                radius: 13
                color: root.mediaOpen ? "#20ffffff" : "transparent"
                border.color: root.mediaOpen ? "#28ffffff" : "transparent"
                border.width: 1
                clip: true

                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                RowLayout {
                    z: 1
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 7

                    Item {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignVCenter
                        opacity: root.activePlayer && root.activePlayer.canTogglePlaying ? 1.0 : 0.48

                        Text {
                            anchors.centerIn: parent
                            text: root.activePlayer && root.activePlayer.isPlaying ? "Ⅱ" : "▶"
                            color: "#f4f7fb"
                            font.pixelSize: root.activePlayer && root.activePlayer.isPlaying ? 11 : 10
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: root.activePlayer && root.activePlayer.canTogglePlaying ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.togglePlayPause()
                        }
                    }

                    MarqueeText {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        text: root.mediaTitle()
                        textColor: root.activePlayer ? "#f4f7fb" : "#9ba5b2"
                        pixelSize: 12
                        fontWeight: Font.DemiBold
                    }

                    Text {
                        Layout.preferredWidth: root.activePlayer ? 8 : 0
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.activePlayer !== null
                        horizontalAlignment: Text.AlignHCenter
                        text: "•"
                        color: "#7f8896"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        font.kerning: false
                    }

                    MarqueeText {
                        Layout.preferredWidth: root.activePlayer ? 92 : 0
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.activePlayer !== null
                        text: root.mediaArtist()
                        textColor: root.mutedTextColor
                        pixelSize: 12
                        fontWeight: Font.Medium
                    }

                    MediaProgressBar {
                        Layout.preferredWidth: root.activePlayer ? 74 : 0
                        Layout.preferredHeight: 14
                        Layout.alignment: Qt.AlignVCenter
                        value: root.visualPosition
                        duration: root.hasDuration() ? root.currentLength : 0
                        seekEnabled: false
                        barHeight: 3
                        backgroundColor: "#22ffffff"
                        fillColor: root.accentStrongColor
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    z: 0

                    onClicked: function(mouse) {
                        root.handleMediaLeftClick();
                        mouse.accepted = true;
                    }

                    onEntered: if (!root.mediaOpen) mediaButton.color = "#14ffffff"
                    onExited: if (!root.mediaOpen) mediaButton.color = "transparent"
                }
            }
        }
    }

    PopupWindow {
        id: calendarPopup
        anchor.window: root
        anchor.rect.x: root.width / 2 - implicitWidth / 2
        anchor.rect.y: root.implicitHeight + 4
        implicitWidth: 316
        implicitHeight: 356
        visible: root.calendarOpen
        color: "transparent"
        surfaceFormat.opaque: false

        Components.GlassPanel {
            anchors.fill: parent
            radiusSize: 18
            glassColor: "#e010131a"
            strokeColor: "#55ffffff"
        }

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.right: calendarNav.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.monthTitle(root.visibleMonth)
                    color: "#f4f7fb"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.kerning: false
                }

                Row {
                    id: calendarNav
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: ["‹", "›"]
                        delegate: Rectangle {
                            required property string modelData
                            width: 28
                            height: 24
                            radius: 12
                            color: "#14ffffff"

                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: "#eef3f8"
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferFullHinting
                                font.kerning: false
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.changeMonth(modelData === "‹" ? -1 : 1)
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: Qt.formatDateTime(root.now, "dddd, MMMM d")
                color: "#b9c3cf"
                font.pixelSize: 12
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                font.kerning: false
            }

            Grid {
                width: parent.width
                columns: 7
                rowSpacing: 4
                columnSpacing: 4

                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    delegate: Text {
                        required property string modelData
                        width: 36
                        height: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: "#8f9aa8"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        font.kerning: false
                    }
                }

                Repeater {
                    model: 42
                    delegate: Rectangle {
                        required property int index
                        property int day: root.calendarDay(index)
                        property bool validDay: root.calendarDayValid(index)
                        width: 36
                        height: 32
                        radius: 16
                        color: validDay && root.isToday(day) ? "#eef3f8" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: parent.validDay ? parent.day : ""
                            color: parent.validDay && root.isToday(parent.day) ? "#10131a" : "#e8eef5"
                            opacity: parent.validDay ? 1.0 : 0.0
                            font.pixelSize: 12
                            font.weight: parent.validDay && root.isToday(parent.day) ? Font.DemiBold : Font.Medium
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }
                    }
                }
            }

            Item { width: parent.width; height: 1 }

            Rectangle {
                width: parent.width
                height: 42
                radius: 14
                color: "#12ffffff"
                border.color: "#22ffffff"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "Today • " + root.centerDateText(root.now)
                    color: "#eef3f8"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.kerning: false
                }
            }
        }
    }

    PopupWindow {
        id: compactMediaPopup
        anchor.window: root
        anchor.rect.x: root.popupX(implicitWidth)
        anchor.rect.y: root.implicitHeight + 6
        implicitWidth: 424
        implicitHeight: 96
        visible: root.mediaOpen
        color: "transparent"
        surfaceFormat.opaque: false

        Rectangle {
            anchors.fill: parent
            radius: 19
            color: root.darkPanelSoftColor
            border.color: "#35ffffff"
            border.width: 1
            clip: true
            opacity: compactMediaPopup.visible ? 1.0 : 0.0

            Behavior on opacity { NumberAnimation { duration: 140 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 14
                anchors.topMargin: 11
                anchors.bottomMargin: 11
                spacing: 11

                MediaCover {
                    Layout.preferredWidth: 58
                    Layout.preferredHeight: 58
                    Layout.alignment: Qt.AlignVCenter
                    radius: 12
                    sourceUrl: root.currentCoverSource
                    sourceKey: root.coverNonce
                    fallbackPixelSize: 22
                    fallbackTextColor: "#dce6f2"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    MarqueeText {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        text: root.compactLineText()
                        textColor: root.activePlayer ? "#f4f7fb" : "#9ba5b2"
                        pixelSize: 15
                        fontWeight: Font.DemiBold
                        gap: 54
                        speedPixelsPerSecond: 30
                    }

                    MediaProgressBar {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 11
                        value: root.visualPosition
                        duration: root.hasDuration() ? root.currentLength : 0
                        seekEnabled: root.canSeek()
                        showHandle: false
                        barHeight: 5
                        backgroundColor: "#2bffffff"
                        fillColor: root.accentStrongColor
                        onDragStarted: root.isDragging = true
                        onDragEnded: root.isDragging = false
                        onSeekRequested: function(seconds) { root.performSeek(seconds); }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        spacing: 6

                        Row {
                            Layout.preferredWidth: 62
                            Layout.preferredHeight: 18
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Repeater {
                                model: ["previous", "play", "next"]
                                delegate: Item {
                                    required property string modelData
                                    width: modelData === "play" ? 22 : 18
                                    height: 18
                                    opacity: {
                                        if (!root.activePlayer)
                                            return 0.45;
                                        if (modelData === "previous")
                                            return root.activePlayer.canGoPrevious ? 1.0 : 0.35;
                                        if (modelData === "next")
                                            return root.activePlayer.canGoNext ? 1.0 : 0.35;
                                        return root.activePlayer.canTogglePlaying ? 1.0 : 0.35;
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            if (modelData === "previous")
                                                return "‹";
                                            if (modelData === "next")
                                                return "›";
                                            return root.activePlayer && root.activePlayer.isPlaying ? "Ⅱ" : "▶";
                                        }
                                        color: "#eef3f8"
                                        font.pixelSize: modelData === "play" ? 11 : 15
                                        font.weight: Font.DemiBold
                                        renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferFullHinting
                                        font.kerning: false
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            const player = root.activePlayer;
                                            if (!player)
                                                return;

                                            if (modelData === "previous" && player.canGoPrevious)
                                                player.previous();
                                            else if (modelData === "next" && player.canGoNext)
                                                player.next();
                                            else if (modelData === "play" && player.canTogglePlaying)
                                                root.togglePlayPause();
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.preferredWidth: 42
                            Layout.alignment: Qt.AlignVCenter
                            text: root.formatSeconds(root.visualPosition)
                            color: "#cfd8e4"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignLeft
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }

                        Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }

                        Text {
                            Layout.preferredWidth: 42
                            Layout.alignment: Qt.AlignVCenter
                            text: root.formatSeconds(root.currentLength)
                            color: "#cfd8e4"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignRight
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }
                    }
                }
            }
        }
    }

}
