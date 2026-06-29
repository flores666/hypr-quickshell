import QtQuick
import "../services" as Services

Shortcut {
    sequence: "Esc"
    context: Qt.ApplicationShortcut
    enabled: Services.ShellState.hasActivePopup
    onActivated: Services.ShellState.requestClosePopups("all")
}
