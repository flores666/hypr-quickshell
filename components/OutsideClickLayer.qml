import QtQuick

Item {
    id: root

    property var controller: null
    property var hostWindow: null
    property real hostWidth: 1
    property real panelHeight: 38
    property real popupX: 0
    property real popupY: panelHeight
    property real popupWidth: 1
    property real popupHeight: 1
    property bool bottomMode: false

    // Intentionally passive.
    //
    // Older implementation created transparent PopupWindow regions around every popup.
    // That closed the popup, but Wayland delivered the first outside click to the
    // transparent layer, so the real target below did not receive the click.
    //
    // Popup ownership is now handled by ShellState:
    // - opening a new popup requests the previous owner to close;
    // - clicks that focus a normal client are handled from Hyprland activewindow events;
    // - Esc still closes the active popup.
    //
    // Keeping this component preserves call sites without reintroducing an input grab.
    visible: false
}
