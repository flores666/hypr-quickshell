import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: root

    readonly property bool opened: Services.ShellState.workspaceOverviewOpen && Services.ShellState.workspaceOverviewMode === "applications"
    property string query: ""
    property var filteredApps: []

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    visible: opened
    focusable: opened
    implicitHeight: Screen.height
    color: "transparent"
    surfaceFormat.opaque: false

    WlrLayershell.namespace: "quickshell:applications"
    WlrLayershell.layer: WlrLayer.Top
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        x: 0
        y: 0
        width: root.opened ? root.width : 0
        height: root.opened ? root.height : 0
    }

    function iconUrl(value) {
        var icon = String(value || "").trim();
        if (!icon)
            return "";
        if (icon.indexOf("file://") === 0 || icon.indexOf("qrc:/") === 0)
            return icon;
        if (icon.charAt(0) === "/")
            return "file://" + icon;
        var themedPath = Quickshell.iconPath(icon, true);
        if (themedPath && themedPath.length > 0 && themedPath.indexOf("image-missing") < 0) {
            if (themedPath.indexOf("file://") === 0 || themedPath.indexOf("qrc:/") === 0)
                return themedPath;
            if (themedPath.charAt(0) === "/")
                return "file://" + themedPath;
            return themedPath;
        }
        return "";
    }

    function appSearchText(app) {
        if (!app)
            return "";

        var parts = [
            app.name || "",
            app.displayName || "",
            app.desktopId || "",
            app.sourceDesktopId || "",
            app.executable || "",
            app.startupWmClass || ""
        ];
        var keys = app.matchKeys || [];
        for (var i = 0; i < keys.length; i++)
            parts.push(keys[i]);

        return parts.join(" ").toLowerCase();
    }

    function rebuildFilteredApps() {
        var apps = Services.AppPanelService.apps || [];
        var needle = String(query || "").trim().toLowerCase();
        var result = [];

        for (var i = 0; i < apps.length; i++) {
            var app = apps[i] || {};
            if (!app.desktopId)
                continue;
            if (needle.length === 0 || appSearchText(app).indexOf(needle) >= 0)
                result.push(app);
        }

        filteredApps = result;
    }

    function launchApp(app) {
        if (!app || !app.desktopId)
            return;

        Services.AppPanelService.launch(app.desktopId);
        Services.ShellActions.closeWorkspaceOverview();
    }

    onOpenedChanged: {
        if (opened) {
            query = Services.ShellState.applicationsOverviewInitialQuery;
            Services.ShellState.setApplicationsOverviewInitialQuery("");
            Services.AppPanelService.requestRefresh(false);
            rebuildFilteredApps();
            search.forceActiveFocus();
            search.cursorPosition = search.text.length;
        } else {
            query = "";
            filteredApps = [];
        }
    }

    onQueryChanged: {
        if (opened)
            rebuildFilteredApps();
    }

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() {
            if (root.opened)
                root.rebuildFilteredApps();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#00000000"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                search.forceActiveFocus();
                Services.ShellState.requestCloseTopbarPopups();
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: 78
            bottomMargin: 128
            leftMargin: Math.max(52, Math.round(root.width * 0.08))
            rightMargin: Math.max(52, Math.round(root.width * 0.08))
        }
        spacing: 28

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(560, parent.width)
            Layout.preferredHeight: 48
            radius: 24
            color: "#da111821"
            border.width: 1
            border.color: "#22ffffff"
            antialiasing: true

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: "⌕"
                color: "#b8c3cf"
                font.pixelSize: 18
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                font.kerning: false
            }

            TextInput {
                id: search
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 52
                    rightMargin: 22
                }
                text: root.query
                color: "#f5f8fb"
                selectionColor: "#55ffffff"
                selectedTextColor: "#0b1018"
                font.pixelSize: 16
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                font.kerning: false
                clip: true
                onTextChanged: root.query = text

                Text {
                    anchors.fill: parent
                    visible: search.text.length === 0
                    text: "Search applications"
                    color: "#7f8b96"
                    font.pixelSize: search.font.pixelSize
                    verticalAlignment: Text.AlignVCenter
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.kerning: false
                }

                Keys.onEscapePressed: Services.ShellActions.closeWorkspaceOverview()
            }
        }

        GridView {
            id: appGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.opened ? root.filteredApps : []
            cellWidth: 118
            cellHeight: 116
            clip: true
            reuseItems: true
            cacheBuffer: 280
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true

            delegate: Item {
                width: appGrid.cellWidth
                height: appGrid.cellHeight

                Rectangle {
                    id: tile
                    anchors.centerIn: parent
                    width: 96
                    height: 104
                    radius: 22
                    color: appMouse.pressed ? "#26ffffff" : (appMouse.containsMouse ? "#18ffffff" : "transparent")
                    antialiasing: true

                    Behavior on color {
                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 7

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 54
                            Layout.preferredHeight: 54

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: root.iconUrl(modelData.icon || modelData.iconName || "application-x-executable")
                                visible: source.toString().length > 0 && status !== Image.Error
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                smooth: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: !appIcon.visible
                                radius: 16
                                color: "#2affffff"
                                antialiasing: true

                                Text {
                                    anchors.centerIn: parent
                                    text: String(modelData.name || "?").substring(0, 1).toUpperCase()
                                    color: "#f5f8fb"
                                    font.pixelSize: 24
                                    font.weight: Font.DemiBold
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting
                                    font.kerning: false
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name || modelData.displayName || "Application"
                            color: "#f4f7fb"
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }
                    }

                    MouseArea {
                        id: appMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launchApp(modelData)
                    }
                }
            }
        }
    }
}
