import Quickshell.Services.Mpris
import QtQuick
import "../../components" as Components
import "../../services" as Services

Item {
    id: root

    property var hostWindow: null
    property real hostWidth: 0
    property real popupBaseX: x
    property real panelHeight: 38
    readonly property real popupTopY: panelHeight

    property bool popupOpen: false
    property var activePlayer: null
    property string lastActivePlayerKey: ""
    property bool isDragging: false
    property real pendingSeekPosition: -1
    property string pendingSeekTrackId: ""
    property double pendingSeekStartedAt: 0
    property real pendingSeekPreviousPosition: -1

    property string currentTrackId: ""
    property string currentTitle: ""
    property string currentArtist: ""
    property string currentAlbum: ""
    property string currentCoverSource: ""
    property string currentCoverFallbackSource: ""
    property int coverNonce: 0
    property real currentPosition: 0
    property real currentLength: 0
    property bool playbackStatus: activePlayer ? activePlayer.isPlaying : false
    property real visualPosition: pendingSeekPosition >= 0 ? pendingSeekPosition : currentPosition

    readonly property color accentStrongColor: "#e8eef6"
    readonly property color mutedTextColor: "#bcc5d0"
    readonly property color darkPanelSoftColor: "#98000000"

    signal popupOpened()

    implicitWidth: mediaButton.implicitWidth
    implicitHeight: mediaButton.implicitHeight
    visible: activePlayer !== null || mediaButton.renderVisible

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

        return String(player.desktopEntry || player.identity || player.dbusName || "player");
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
                if (list[j] && playerStableKey(list[j]) === currentKey) {
                    if (activePlayer !== list[j])
                        activePlayer = list[j];
                    return;
                }
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

    function enhancedCoverUrl(url) {
        var value = normalizeCoverUrl(url);
        if (value === "")
            return "";

        if (value.indexOf("avatars.yandex.net/get-music-content") >= 0) {
            value = value.replace(/\/\d+x\d+(\?.*)?$/, "/1000x1000$1");
            value = value.replace(/\/%%(\?.*)?$/, "/1000x1000$1");
            value = value.replace(/size=\d+x\d+/, "size=1000x1000");
        }

        return value;
    }

    function clearPendingSeek() {
        pendingSeekPosition = -1;
        pendingSeekTrackId = "";
        pendingSeekStartedAt = 0;
        pendingSeekPreviousPosition = -1;
    }

    function lowerText(value) {
        return String(value || "").toLowerCase();
    }

    function cleanBrowserTabTitle(title) {
        var value = String(title || "").trim();
        value = value.replace(/\s+[—-]\s*(yandex music|яндекс\.?\s*музыка).*$/i, "");
        value = value.replace(/\s+[—-]\s*(mozilla firefox|google chrome|chromium|yandex browser|яндекс браузер).*$/i, "");
        return value.trim();
    }

    function looksLikeBrowserTabTitle(player, title, artist) {
        const value = lowerText(title).trim();
        const playerName = lowerText(player ? player.identity : "").trim();

        if (value === "")
            return true;

        if (playerName !== "" && value === playerName)
            return true;

        if ((value.indexOf("yandex") >= 0 && value.indexOf("music") >= 0)
                || (value.indexOf("яндекс") >= 0 && value.indexOf("музык") >= 0)
                || value.indexOf("music.yandex") >= 0)
            return true;

        if (value.indexOf("mozilla firefox") >= 0
                || value.indexOf("google chrome") >= 0
                || value.indexOf("chromium") >= 0
                || value.indexOf("yandex browser") >= 0
                || value.indexOf("яндекс браузер") >= 0)
            return true;

        return false;
    }

    function syncMetadataFromPlayer(forceCoverReload) {
        const player = activePlayer;
        if (!player) {
            if (currentTrackId !== "") {
                currentTrackId = "";
                currentTitle = "";
                currentArtist = "";
                currentAlbum = "";
                currentCoverSource = "";
                currentCoverFallbackSource = "";
                currentPosition = 0;
                currentLength = 0;
                clearPendingSeek();
                coverNonce++;
            }
            closePopup();
            return;
        }

        const rawTitle = String(player.trackTitle || "").trim();
        const rawArtist = String(player.trackArtist || "").trim();
        const rawAlbum = String(player.trackAlbum || "").trim();
        const cleanedTitle = cleanBrowserTabTitle(rawTitle);
        const titleWasCleaned = cleanedTitle !== "" && cleanedTitle !== rawTitle;
        const badBrowserTitle = looksLikeBrowserTabTitle(player, rawTitle, rawArtist) && !titleWasCleaned;
        const nextTitle = badBrowserTitle
            ? (currentTitle || player.identity || "Unknown Title")
            : (cleanedTitle || rawTitle || player.identity || "Unknown Title");
        const nextArtist = badBrowserTitle ? currentArtist : rawArtist;
        const nextAlbum = badBrowserTitle ? currentAlbum : rawAlbum;
        const nextTrackId = playerStableKey(player) + ":" + nextTitle + ":" + nextArtist + ":" + nextAlbum;
        const rawCover = normalizeCoverUrl(player.trackArtUrl || "");
        const nextCover = enhancedCoverUrl(rawCover);
        const trackChanged = nextTrackId !== currentTrackId;
        const coverChanged = nextCover !== "" && nextCover !== currentCoverSource;

        if (trackChanged)
            clearPendingSeek();

        currentTrackId = nextTrackId;
        currentTitle = nextTitle;
        currentArtist = nextArtist;
        currentAlbum = nextAlbum;
        currentLength = Number(player.length || 0);

        if (nextCover !== "" && (trackChanged || coverChanged || forceCoverReload)) {
            currentCoverSource = nextCover;
            currentCoverFallbackSource = rawCover;
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
            const targetDiff = Math.abs(actual - pendingSeekPosition);

            if (targetDiff <= 2.5) {
                clearPendingSeek();
                currentPosition = actual;
                return;
            }

            if (pendingSeekPosition <= 0.35 && age >= 850 && actual > 2.0) {
                clearPendingSeek();
                currentPosition = actual;
                return;
            }

            if (age < 2200)
                return;

            clearPendingSeek();
        }

        currentPosition = actual;
    }

    function mediaTitle() {
        if (!activePlayer)
            return "";
        return currentTitle || activePlayer.identity || "Unknown Title";
    }

    function mediaArtist() {
        if (!activePlayer)
            return "";
        if (currentArtist)
            return currentArtist;
        if (currentTitle)
            return "";
        return activePlayer.identity || "Media Player";
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
        const previousPosition = Math.max(0, Number(player.position || currentPosition || 0));
        const delta = target - previousPosition;

        if (Math.abs(delta) < 0.25) {
            clearPendingSeek();
            syncPositionFromPlayer(true);
            return;
        }

        try {
            if (player.positionSupported !== false) {
                player.position = target;
            } else if (typeof player.seek === "function") {
                player.seek(delta);
            } else {
                return;
            }

            pendingSeekPosition = target;
            pendingSeekTrackId = currentTrackId;
            pendingSeekStartedAt = Date.now();
            pendingSeekPreviousPosition = previousPosition;
            seekVerifyTimer.restart();
        } catch (e) {
            clearPendingSeek();
            syncPositionFromPlayer(true);
        }
    }

    function togglePlayPause() {
        const player = activePlayer;
        if (!player || !player.canTogglePlaying)
            return;
        player.togglePlaying();
    }

    function popupXFor(popupWidth) {
        const raw = popupBaseX + width / 2 - popupWidth / 2;
        return Math.max(6, Math.min(raw, hostWidth - popupWidth - 6));
    }

    function openPopup() {
        if (!activePlayer)
            return;

        popupOpen = true;
        Services.ShellState.openPopup("mediaPopup", "topbar");
        popupOpened();
    }

    function closePopup() {
        popupOpen = false;
        Services.ShellState.closePopup("mediaPopup");
    }

    function closeStalePlayerIfNoSources() {
        Services.ShellState.requestClosePopups("all");
        if (playersList().length > 0)
            return;

        activePlayer = null;
        lastActivePlayerKey = "";
        currentTrackId = "";
        currentTitle = "";
        currentArtist = "";
        currentAlbum = "";
        currentCoverSource = "";
        currentCoverFallbackSource = "";
        currentPosition = 0;
        currentLength = 0;
        clearPendingSeek();
        closePopup();
        coverNonce++;
    }

    function togglePopup() {
        Services.ShellState.requestClosePopups("appDock");
        if (popupOpen)
            closePopup();
        else
            openPopup();
    }

    Timer {
        id: playerRefreshTimer
        interval: root.activePlayer ? 1800 : 900
        repeat: true
        running: true
        onTriggered: {
            root.refreshActivePlayer();
            root.syncMetadataFromPlayer(false);
        }
    }

    Timer {
        id: positionTimer
        interval: 250
        repeat: true
        running: root.activePlayer && root.activePlayer.isPlaying
        onTriggered: {
            if (!root.activePlayer || root.isDragging || root.pendingSeekPosition >= 0)
                return;

            if (root.currentLength > 0)
                root.currentPosition = Math.min(root.currentLength, root.currentPosition + interval / 1000);
            else
                root.currentPosition = Math.max(0, root.currentPosition + interval / 1000);
        }
    }

    Timer {
        id: metadataPollTimer
        interval: 3200
        repeat: true
        running: root.activePlayer !== null
        onTriggered: root.syncMetadataFromPlayer(false)
    }

    Timer {
        id: seekVerifyTimer
        interval: 850
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

    MediaButton {
        id: mediaButton
        anchors.fill: parent
        playerActive: root.activePlayer !== null
        popupOpen: root.popupOpen
        titleText: root.mediaTitle()
        artistText: root.activePlayer ? root.mediaArtist() : ""
        resetKey: root.currentTrackId
        position: root.visualPosition
        durationValue: root.hasDuration() ? root.currentLength : 0
        accentStrongColor: root.accentStrongColor
        mutedTextColor: root.mutedTextColor
        onClicked: root.togglePopup()
        onCloseRequested: root.closeStalePlayerIfNoSources()
    }

    Components.OutsideClickLayer {
        controller: root
        hostWindow: root.hostWindow
        hostWidth: root.hostWidth
        panelHeight: root.panelHeight
        popupX: root.popupXFor(402)
        popupY: root.popupTopY
        popupWidth: 402
        popupHeight: 66
    }

    MediaPopup {
        id: mediaPopup
        controller: root
        hostWindow: root.hostWindow
        popupX: root.popupXFor(implicitWidth)
        popupY: root.popupTopY
    }
}
