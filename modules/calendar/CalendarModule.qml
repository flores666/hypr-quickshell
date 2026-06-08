import Quickshell
import QtQuick
import QtQuick.Layouts
import QtCore
import "../../components" as Components

Item {
    id: root

    property var hostWindow: null
    property real hostWidth: 0
    property real popupBaseX: x
    property real panelHeight: 38
    property date now: new Date()
    property bool popupOpen: false
    property date visibleMonth: new Date(now.getFullYear(), now.getMonth(), 1)

    signal popupOpened()

    implicitWidth: clockButton.width
    implicitHeight: clockButton.height

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

    Rectangle {
        id: clockButton
        anchors.centerIn: parent
        width: clockText.implicitWidth + 16
        height: 24
        radius: 12
        color: root.popupOpen ? "#26ffffff" : "transparent"
        border.color: root.popupOpen ? "#33ffffff" : "transparent"
        border.width: 1

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 140
            }
        }

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
            onClicked: root.togglePopup()
            onEntered: if (!root.popupOpen)
                clockButton.color = "#14ffffff"
            onExited: if (!root.popupOpen)
                clockButton.color = "transparent"
        }
    }

    PopupWindow {
        id: calendarPopup
        anchor.window: root.hostWindow
        anchor.rect.x: root.popupXFor(implicitWidth)
        anchor.rect.y: root.panelHeight + 4
        implicitWidth: 316
        implicitHeight: 356
        visible: root.popupOpen
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

            Item {
                width: parent.width
                height: 1
            }

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
}
