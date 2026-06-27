import Quickshell
import QtQuick
import QtQuick.Layouts
import QtCore
import "../../components" as Components
import "../../services" as Services

Item {
    id: root

    property var hostWindow: null
    property real hostWidth: 0
    property real popupBaseX: x
    property real panelHeight: 38
    readonly property real popupTopY: panelHeight
    property date now: new Date()
    property bool popupOpen: false
    property date visibleMonth: new Date(now.getFullYear(), now.getMonth(), 1)
    property bool pointerReady: false

    signal popupOpened()

    implicitWidth: clockButton.width
    implicitHeight: clockButton.height

    Components.AnimationTokens { id: motion }

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
        return day === now.getDate() && visibleMonth.getMonth() === now.getMonth() && visibleMonth.getFullYear() === now.getFullYear();
    }

    function changeMonth(delta) {
        visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + delta, 1);
    }

    function popupXFor(popupWidth) {
        const raw = popupBaseX + width / 2 - popupWidth / 2;
        return Math.max(6, Math.min(raw, hostWidth - popupWidth - 6));
    }

    function openPopup() {
        visibleMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        popupOpen = true;
        popupOpened();
    }

    function closePopup() {
        popupOpen = false;
    }

    function togglePopup() {
        Services.ShellState.requestCloseAppDockPopups();
        if (popupOpen)
            closePopup();
        else
            openPopup();
    }

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
        onDateChanged: root.now = date
    }

    Timer {
        id: pointerDelay
        interval: motion.cursorDelay
        repeat: false
        onTriggered: root.pointerReady = clockMouse.containsMouse
    }

    Rectangle {
        id: clockButton
        anchors.centerIn: parent
        width: clockText.implicitWidth + 16
        height: 24
        radius: 12
        color: root.popupOpen
            ? "#26ffffff"
            : (clockMouse.pressed ? "#1cffffff" : (clockMouse.containsMouse ? "#14ffffff" : "transparent"))
        border.width: 0
        scale: 1.0
        antialiasing: true

        Behavior on color {
            ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic }
        }

        Components.StyledText {
            id: clockText
            anchors.centerIn: parent
            text: root.centerDateText(root.now)
            color: "#eef3f8"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: clockMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            cursorShape: root.pointerReady ? Qt.PointingHandCursor : Qt.ArrowCursor

            onEntered: {
                root.pointerReady = false;
                pointerDelay.restart();
            }

            onExited: {
                pointerDelay.stop();
                root.pointerReady = false;
            }

            onClicked: function(mouse) {
                if (mouse.button === Qt.LeftButton)
                    root.togglePopup();
                else
                    Services.ShellState.requestCloseShellPopups();
                mouse.accepted = true;
            }
        }
    }

    Components.OutsideClickLayer {
        controller: root
        hostWindow: root.hostWindow
        hostWidth: root.hostWidth
        panelHeight: root.panelHeight
        popupX: root.popupXFor(316)
        popupY: root.popupTopY
        popupWidth: 316
        popupHeight: 356
    }

    PopupWindow {
        id: calendarPopup
        anchor.window: root.hostWindow
        anchor.rect.x: root.popupXFor(implicitWidth)
        anchor.rect.y: root.popupTopY
        implicitWidth: 316
        implicitHeight: 356
        visible: popupState.renderVisible
        color: "transparent"
        surfaceFormat.opaque: false

        Shortcut {
            sequence: "Esc"
            context: Qt.ApplicationShortcut
            enabled: Services.ShellState.shellPopupOpen
            onActivated: Services.ShellState.requestCloseShellPopups()
        }

        Components.AnimatedPopupState {
            id: popupState
            targetVisible: root.popupOpen
            openDuration: motion.popupOpenDuration
            closeDuration: motion.popupCloseDuration
            closeSafetyDelay: motion.popupCloseDuration + 55
        }

        Item {
            id: popupMotionLayer
            anchors.fill: parent
            opacity: popupState.reveal
            y: -9 + popupState.reveal * 9
            scale: 0.972 + popupState.reveal * 0.028
            transformOrigin: Item.Top
            enabled: root.popupOpen && popupState.reveal > 0.45
            layer.enabled: popupState.reveal > 0.001 && popupState.reveal < 0.999
            layer.smooth: true

            Components.GlassPanel {
                id: panel
                anchors.fill: parent
                radiusSize: 18
                glassColor: "#98000000"
                clip: true
                antialiasing: true
            }

            Rectangle {
                anchors.fill: parent
                radius: 18
                color: popupMouse.pressed ? "#08ffffff" : "transparent"
                border.width: 0
                antialiasing: true

                Behavior on color {
                    ColorAnimation { duration: popupMouse.pressed ? motion.pressDuration : motion.releaseDuration; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                id: popupMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.ArrowCursor
                onClicked: function(mouse) { mouse.accepted = true; }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                opacity: Math.max(0, Math.min(1, (popupState.reveal - 0.10) / 0.90))

                Item {
                    width: parent.width
                    height: 28
                    opacity: Math.max(0, Math.min(1, (popupState.reveal - 0.12) / 0.74))

                    Components.StyledText {
                        anchors.left: parent.left
                        anchors.right: calendarNav.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.monthTitle(root.visibleMonth)
                        color: "#f4f7fb"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
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
                                property bool pointerReady: false

                                width: 28
                                height: 24
                                radius: 12
                                color: navMouse.pressed ? "#28ffffff" : (navMouse.containsMouse ? "#18ffffff" : "#12ffffff")
                                scale: navMouse.pressed ? 0.94 : (navMouse.containsMouse ? 1.06 : 1.0)
                                border.width: 0
                                antialiasing: true
                                transformOrigin: Item.Center

                                Behavior on color {
                                    ColorAnimation { duration: navMouse.pressed ? motion.pressDuration : motion.hoverDuration; easing.type: Easing.OutCubic }
                                }

                                Behavior on scale {
                                    NumberAnimation { duration: navMouse.pressed ? motion.pressDuration : motion.releaseDuration; easing.type: Easing.OutCubic }
                                }

                                Timer {
                                    id: navPointerDelay
                                    interval: motion.cursorDelay
                                    repeat: false
                                    onTriggered: parent.pointerReady = navMouse.containsMouse
                                }

                                Components.StyledText {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: "#eef3f8"
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: navMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: parent.pointerReady ? Qt.PointingHandCursor : Qt.ArrowCursor

                                    onEntered: {
                                        parent.pointerReady = false;
                                        navPointerDelay.restart();
                                    }

                                    onExited: {
                                        navPointerDelay.stop();
                                        parent.pointerReady = false;
                                    }

                                    onClicked: function(mouse) {
                                        root.changeMonth(modelData === "‹" ? -1 : 1);
                                        mouse.accepted = true;
                                    }
                                }
                            }
                        }
                    }
                }

                Components.StyledText {
                    width: parent.width
                    text: Qt.formatDateTime(root.now, "dddd, MMMM d")
                    color: "#b9c3cf"
                    font.pixelSize: 12
                    opacity: Math.max(0, Math.min(1, (popupState.reveal - 0.18) / 0.72))
                }

                Grid {
                    width: parent.width
                    columns: 7
                    rowSpacing: 4
                    columnSpacing: 4
                    opacity: Math.max(0, Math.min(1, (popupState.reveal - 0.22) / 0.72))

                    Repeater {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        delegate: Components.StyledText {
                            required property string modelData
                            width: 36
                            height: 24
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: "#8f9aa8"
                            font.pixelSize: 12
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
                            border.width: 0
                            antialiasing: true

                            Behavior on color {
                                ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic }
                            }

                            Components.StyledText {
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

                Item {
                    width: parent.width
                    height: 1
                }

                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 14
                    color: "#12ffffff"
                    border.width: 0
                    opacity: Math.max(0, Math.min(1, (popupState.reveal - 0.30) / 0.70))
                    antialiasing: true

                    Behavior on color {
                        ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic }
                    }

                    Components.StyledText {
                        anchors.centerIn: parent
                        text: "Today • " + root.centerDateText(root.now)
                        color: "#eef3f8"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
