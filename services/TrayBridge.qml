import QtQuick
import Quickshell.Services.SystemTray

QtObject {
    id: trayBridge

    // Точка расширения под настоящий StatusNotifier tray.
    // В макете native tray не смешивается с trayed windows.
    // Идея:
    // - native tray items читаются из SystemTray
    // - окна, спрятанные shell, читаются из ShellState.trayedWindows
}
