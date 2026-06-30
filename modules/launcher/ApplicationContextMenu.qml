import QtQuick
import QtQuick.Layouts
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    anchors.fill: parent
    visible: menuOpen && applicationsInputInteractive
    z: 10000

    property var overview: null
    property real menuWidth: 226
    property real rowHeight: 38
    property real inputTopMargin: 56
    property real inputBottomMargin: 116
    property bool applicationsInputInteractive: false
    property bool menuOpen: false
    property var contextApp: ({})
    property var contextActions: []
    property real menuX: 0
    property real menuY: 0

    function appKey(app) {
        return overview ? overview.appKey(app) : String(app && (app.desktopId || app.sourceDesktopId || app.name || app.displayName) || "");
    }

    function menuHeight() {
        return Math.max(1, contextActions.length) * rowHeight + 12;
    }

    function clampContextX(x) {
        return Math.max(8, Math.min(Number(x || 0), Math.max(8, width - menuWidth - 8)));
    }

    function clampContextY(y) {
        var minY = inputTopMargin + 4;
        var maxY = Math.max(minY, height - inputBottomMargin - menuHeight() - 4);
        return Math.max(minY, Math.min(Number(y || 0), maxY));
    }

    function appContextActions(app) {
        var key = appKey(app);
        var hidden = Services.AppPanelService.isHidden(key) || Boolean(app && app.hidden);
        var favorite = Services.AppPanelService.isFavorite(key) || Boolean(app && app.favorite);
        var pinned = Services.AppPanelService.isPinned(key);
        var actions = [
            { "label": "Launch", "action": "launch" },
            { "label": favorite ? "Remove from favorites" : "Add to favorites", "action": favorite ? "unfavorite" : "favorite" },
            { "label": pinned ? "Unpin from panel" : "Pin to panel", "action": pinned ? "unpin" : "pin" }
        ];
        if (hidden)
            actions.push({ "label": "Show in applications", "action": "show" });
        actions.push({ "label": "Uninstall from system...", "action": "uninstall" });
        return actions;
    }

    function openMenu(app, x, y) {
        if (!app || !app.desktopId)
            return;
        Services.ShellState.requestClosePopups("all");
        contextApp = app;
        contextActions = appContextActions(app);
        menuX = clampContextX(x + 8);
        menuY = clampContextY(y + 8);
        menuOpen = true;
        Services.ShellState.openPopup("launcherContextMenu", "applications");
    }

    function closeMenu() {
        menuOpen = false;
        contextActions = [];
        contextApp = ({});
        Services.ShellState.closePopup("launcherContextMenu");
    }

    function runAction(action) {
        var app = contextApp || {};
        var key = appKey(app);
        closeMenu();
        if (!key)
            return;

        if (action === "launch") {
            if (overview)
                overview.launchApp(app);
            return;
        }

        if (overview)
            overview.beginViewportPreservingMutation();

        if (action === "pin") {
            Services.AppPanelService.pin(key);
        } else if (action === "unpin") {
            Services.AppPanelService.unpin(key);
        } else if (action === "favorite") {
            Services.AppPanelService.addFavorite(key);
        } else if (action === "unfavorite") {
            Services.AppPanelService.removeFavorite(key);
        } else if (action === "hide") {
            Services.AppPanelService.hideFromApplications(key);
        } else if (action === "show") {
            Services.AppPanelService.showInApplications(key);
        } else if (action === "uninstall") {
            Services.ShellActions.closeWorkspaceOverview();
            Services.AppPanelService.uninstallFromSystem(key);
        }
    }

    Components.PopupGlassSurface {
        id: contextMenu
        x: Math.round(root.menuX)
        y: Math.round(root.menuY)
        width: root.menuWidth
        height: contextColumn.implicitHeight + 12
        radiusSize: 18

        Column {
            id: contextColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 6
            }
            spacing: 2

            Repeater {
                model: root.contextActions.length

                delegate: Item {
                    id: actionDelegate
                    required property int index
                    readonly property var actionData: root.contextActions[index] || ({})

                    width: contextColumn.width
                    height: root.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: actionMouse.containsMouse ? "#22ffffff" : "transparent"
                        antialiasing: true

                        Text {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 14
                                rightMargin: 14
                            }
                            text: String(actionDelegate.actionData.label || "")
                            color: "#f4f7fb"
                            font.family: "Nunito"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            renderType: Text.QtRendering
                            font.hintingPreference: Font.PreferNoHinting
                            font.kerning: true
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: overview ? overview.interactiveCursorShape(Qt.PointingHandCursor) : Qt.PointingHandCursor
                            onPositionChanged: {
                                if (overview)
                                    overview.revealPointerAfterMouseMove();
                            }
                            onClicked: root.runAction(String(actionDelegate.actionData.action || ""))
                        }
                    }
                }
            }
        }

        Components.PopupInteractionBoundary {
            owner: "launcherContextMenu"
            active: root.menuOpen && root.applicationsInputInteractive
            screenX: root.menuX
            screenY: root.menuY
            screenWidth: root.menuWidth
            screenHeight: contextColumn.implicitHeight + 12
        }
    }
}
