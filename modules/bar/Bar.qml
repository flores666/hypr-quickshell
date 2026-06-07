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
    property var activePlayer: pickPlayer()

    function playersList() {
        if (!Mpris || !Mpris.players || !Mpris.players.values)
            return [];
        return Mpris.players.values;
    }

    function pickPlayer() {
        const list = playersList();

        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].isPlaying)
                return list[i];
        }

        return list.length > 0 ? list[0] : null;
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

    function closePopups() {
        calendarOpen = false;
        mediaOpen = false;
    }

    function toggleCalendar() {
        visibleMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        calendarOpen = !calendarOpen;
        if (calendarOpen)
            mediaOpen = false;
    }

    function toggleMedia() {
        mediaOpen = !mediaOpen;
        if (mediaOpen)
            calendarOpen = false;
    }

    function mediaTitle(player) {
        if (!player)
            return "No media playing";
        return player.trackTitle || player.identity || "Unknown Title";
    }

    function mediaSubtitle(player) {
        if (!player)
            return "Open a player with MPRIS support";

        const artist = player.trackArtist || "";
        const album = player.trackAlbum || "";
        if (artist && album)
            return artist + " • " + album;
        if (artist)
            return artist;
        return player.identity || "Media Player";
    }

    function formatSeconds(value) {
        if (!value || value < 0)
            return "0:00";

        const total = Math.floor(value);
        const minutes = Math.floor(total / 60);
        const seconds = total % 60;
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
        onDateChanged: root.now = date
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.mediaOpen && root.activePlayer && root.activePlayer.isPlaying
        onTriggered: {
            if (root.activePlayer)
                root.activePlayer.positionChanged();
        }
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
                width: 30
                height: 26
                radius: 13
                color: root.mediaOpen ? "#26ffffff" : "transparent"
                border.color: root.mediaOpen ? "#33ffffff" : "transparent"
                border.width: 1
                opacity: root.activePlayer ? 1.0 : 0.58

                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on opacity { NumberAnimation { duration: 140 } }

                Text {
                    anchors.centerIn: parent
                    text: root.activePlayer && root.activePlayer.isPlaying ? "Ⅱ" : "♪"
                    color: "#eef3f8"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleMedia()
                    onEntered: if (!root.mediaOpen) mediaButton.color = "#14ffffff"
                    onExited: if (!root.mediaOpen) mediaButton.color = "transparent"
                }
            }
        }
    }

    PopupWindow {
        id: calendarPopup
        anchor.window: root
        anchor.rect.x: root.width / 2 - width / 2
        anchor.rect.y: root.implicitHeight + 4
        width: 316
        height: 356
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

            Row {
                width: parent.width
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 72
                    text: root.monthTitle(root.visibleMonth)
                    color: "#f4f7fb"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Row {
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
                }
            }
        }
    }

    PopupWindow {
        id: mediaPopup
        anchor.window: root
        anchor.rect.x: root.width / 2 - width / 2
        anchor.rect.y: root.implicitHeight + 4
        width: 340
        height: 190
        visible: root.mediaOpen
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

            Row {
                width: parent.width
                height: 72
                spacing: 12

                Rectangle {
                    width: 72
                    height: 72
                    radius: 14
                    color: "#18ffffff"
                    border.color: "#22ffffff"
                    border.width: 1
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: root.activePlayer ? root.activePlayer.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== ""
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.activePlayer || !root.activePlayer.trackArtUrl
                        text: "♪"
                        color: "#dfe7f0"
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    width: parent.width - 84
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        width: parent.width
                        text: root.mediaTitle(root.activePlayer)
                        color: "#f4f7fb"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width
                        text: root.mediaSubtitle(root.activePlayer)
                        color: "#b9c3cf"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width
                        visible: root.activePlayer !== null
                        text: root.activePlayer ? root.activePlayer.identity : ""
                        color: "#7f8a98"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: "#22ffffff"
                visible: root.activePlayer !== null

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: "#eef3f8"
                    width: {
                        if (!root.activePlayer || !root.activePlayer.length || root.activePlayer.length <= 0)
                            return 0;
                        return Math.max(0, Math.min(parent.width, parent.width * (root.activePlayer.position / root.activePlayer.length)));
                    }
                }
            }

            Row {
                width: parent.width
                height: 34
                spacing: 8

                Text {
                    width: 54
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.activePlayer !== null
                    text: root.activePlayer ? root.formatSeconds(root.activePlayer.position) : ""
                    color: "#8f9aa8"
                    font.pixelSize: 11
                }

                Item { width: 1; height: 1 }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Repeater {
                        model: ["previous", "play", "next"]
                        delegate: Rectangle {
                            required property string modelData
                            width: modelData === "play" ? 36 : 30
                            height: modelData === "play" ? 34 : 30
                            radius: height / 2
                            color: modelData === "play" ? "#eef3f8" : "#18ffffff"
                            opacity: root.activePlayer ? 1.0 : 0.45

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (modelData === "previous")
                                        return "‹";
                                    if (modelData === "next")
                                        return "›";
                                    return root.activePlayer && root.activePlayer.isPlaying ? "Ⅱ" : "▶";
                                }
                                color: modelData === "play" ? "#10131a" : "#eef3f8"
                                font.pixelSize: modelData === "play" ? 13 : 18
                                font.weight: Font.DemiBold
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
                                        player.togglePlaying();
                                }
                            }
                        }
                    }
                }

                Text {
                    width: 54
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    visible: root.activePlayer !== null
                    text: root.activePlayer ? root.formatSeconds(root.activePlayer.length) : ""
                    color: "#8f9aa8"
                    font.pixelSize: 11
                }
            }
        }
    }
}
