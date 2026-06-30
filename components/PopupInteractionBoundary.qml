import QtQuick
import "../services" as Services

Item {
    id: root

    anchors.fill: parent
    visible: active
    enabled: false
    z: 1000000

    property string owner: ""
    property bool active: true
    property real screenX: 0
    property real screenY: 0
    property real screenWidth: width
    property real screenHeight: height

    function normalizedOwner() {
        return String(owner || "").trim();
    }

    function syncBounds() {
        var popupOwner = normalizedOwner();
        if (popupOwner.length === 0)
            return;

        Services.ShellState.setPopupInteractionBounds(
            popupOwner,
            Number(screenX || 0),
            Number(screenY || 0),
            Math.max(0, Number(screenWidth || width || 0)),
            Math.max(0, Number(screenHeight || height || 0)),
            active && visible
        );
    }

    onOwnerChanged: syncBounds()
    onActiveChanged: syncBounds()
    onVisibleChanged: syncBounds()
    onScreenXChanged: syncBounds()
    onScreenYChanged: syncBounds()
    onScreenWidthChanged: syncBounds()
    onScreenHeightChanged: syncBounds()
    onWidthChanged: syncBounds()
    onHeightChanged: syncBounds()

    Component.onCompleted: syncBounds()
    Component.onDestruction: {
        var popupOwner = normalizedOwner();
        if (popupOwner.length > 0)
            Services.ShellState.clearPopupInteractionBounds(popupOwner);
    }
}
