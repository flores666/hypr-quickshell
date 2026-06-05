import QtQuick
import Quickshell

Text {
    id: clock

    property date now: new Date()

    text: Qt.formatDateTime(now, "hh:mm")
    color: "#eef3f8"
    font.pixelSize: 12
    font.weight: Font.Medium

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
        onDateChanged: clock.now = date
    }
}
