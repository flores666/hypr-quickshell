import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "../../services" as Services

Item {
    id: root

    property int workspaceCount: 10

    // Размеры считаются от базового 96 DPI и слегка компенсируют разные экраны.
    // Это помогает сохранить одинаковый вид цифр, точки active и капсул на мониторе и ноутбуке.
    readonly property real screenDpi: Screen.pixelDensity > 0 ? Screen.pixelDensity * 25.4 : 96
    readonly property real uiScale: Math.max(0.72, Math.min(1.0, 96 / screenDpi))

    readonly property int cellWidth: Math.round(23 * uiScale)
    readonly property int moduleHeight: Math.max(circleSize + 4, Math.round(26 * uiScale))
    readonly property int sidePadding: 0
    readonly property int circleSize: Math.round(18 * uiScale)
    readonly property int activeDotSize: Math.max(4, Math.round(6 * uiScale))
    readonly property int contentYOffset: 0
    readonly property int textSize: Math.max(9, Math.round(12 * uiScale))

    property int activeWorkspace: Services.ShellState.activeWorkspace
    property int previousWorkspace: Services.ShellState.activeWorkspace
    property int lastAnimatedWorkspace: Services.ShellState.activeWorkspace

    property real activeDotOpacity: 1.0
    property real activeDotCenterX: workspaceCenterX(Services.ShellState.activeWorkspace)

    implicitWidth: sidePadding * 2 + workspaceCount * cellWidth
    implicitHeight: moduleHeight

    onActiveWorkspaceChanged: {
        workspaceCanvas.requestPaint();

        if (activeWorkspace === lastAnimatedWorkspace)
            return;

        previousWorkspace = lastAnimatedWorkspace;
        lastAnimatedWorkspace = activeWorkspace;

        activeDotMove.stop();
        activeDotMove.to = workspaceCenterX(activeWorkspace);
        activeDotMove.start();

        activeDotOpacity = 0.0;
        activeDotFade.restart();
    }

    onUiScaleChanged: workspaceCanvas.requestPaint()
    onCellWidthChanged: workspaceCanvas.requestPaint()
    onCircleSizeChanged: workspaceCanvas.requestPaint()
    onModuleHeightChanged: workspaceCanvas.requestPaint()

    Connections {
        target: Services.ShellState

        function onOccupiedWorkspacesChanged() {
            workspaceCanvas.requestPaint();
        }

        function onWindowsChanged() {
            workspaceCanvas.requestPaint();
        }
    }

    NumberAnimation {
        id: activeDotMove
        target: root
        property: "activeDotCenterX"
        duration: 310
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: activeDotFade
        target: root
        property: "activeDotOpacity"
        from: 0.0
        to: 1.0
        duration: 180
        easing.type: Easing.OutCubic
    }

    function clampWorkspace(workspaceId) {
        if (workspaceId < 1)
            return 1;
        if (workspaceId > workspaceCount)
            return workspaceCount;
        return workspaceId;
    }

    function workspaceCenterX(workspaceId) {
        var id = clampWorkspace(workspaceId);
        return sidePadding + (id - 1) * cellWidth + cellWidth / 2;
    }

    function contentCenterY() {
        return moduleHeight / 2 + contentYOffset;
    }

    function isOccupied(workspaceId) {
        return Services.ShellState.workspaceHasWindows(workspaceId);
    }

    function highlightedForGroup(workspaceId) {
        return workspaceId === activeWorkspace || isOccupied(workspaceId);
    }

    function isGroupStart(workspaceId) {
        if (!highlightedForGroup(workspaceId))
            return false;
        if (workspaceId <= 1)
            return true;
        return !highlightedForGroup(workspaceId - 1);
    }

    function groupEnd(workspaceId) {
        var end = workspaceId;
        while (end < workspaceCount && highlightedForGroup(end + 1))
            end++;
        return end;
    }

    function groupX(workspaceId) {
        return workspaceCenterX(workspaceId) - circleSize / 2;
    }

    function groupWidth(workspaceId) {
        var end = groupEnd(workspaceId);
        return (end - workspaceId) * cellWidth + circleSize;
    }

    function dotIsOnFinalActive(workspaceId) {
        return workspaceId === activeWorkspace
            && activeDotOpacity > 0.72
            && Math.abs(activeDotCenterX - workspaceCenterX(workspaceId)) < Math.max(2, Math.round(3 * uiScale));
    }

    Canvas {
        id: workspaceCanvas
        anchors.fill: parent
        z: 1

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.fillStyle = "#261b2330";
            ctx.globalAlpha = 0.98;

            var y = root.contentCenterY() - root.circleSize / 2;
            var h = root.circleSize;
            var r = h / 2;

            for (var ws = 1; ws <= root.workspaceCount; ws++) {
                if (!root.isGroupStart(ws))
                    continue;

                var x = root.groupX(ws);
                var w = root.groupWidth(ws);

                ctx.beginPath();
                ctx.moveTo(x + r, y);
                ctx.lineTo(x + w - r, y);
                ctx.quadraticCurveTo(x + w, y, x + w, y + r);
                ctx.lineTo(x + w, y + h - r);
                ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
                ctx.lineTo(x + r, y + h);
                ctx.quadraticCurveTo(x, y + h, x, y + h - r);
                ctx.lineTo(x, y + r);
                ctx.quadraticCurveTo(x, y, x + r, y);
                ctx.closePath();
                ctx.fill();
            }
        }
    }

    Rectangle {
        id: activeDot
        y: root.contentCenterY() - height / 2
        x: root.activeDotCenterX - root.activeDotSize / 2
        width: root.activeDotSize
        height: root.activeDotSize
        radius: width / 2
        color: "#ffffff"
        opacity: root.activeDotOpacity * 0.98
        z: 2
    }

    Row {
        id: workspaceRow
        y: root.contentCenterY() - height / 2
        x: root.sidePadding
        spacing: 0
        z: 3

        Repeater {
            model: root.workspaceCount

            delegate: Item {
                id: cell

                property int workspaceId: index + 1
                property bool occupied: root.isOccupied(workspaceId)
                property bool hiddenByDot: root.dotIsOnFinalActive(workspaceId)

                width: root.cellWidth
                height: root.moduleHeight

                Text {
                    anchors.centerIn: parent
                    text: cell.workspaceId
                    color: "#ffffff"
                    opacity: cell.hiddenByDot ? 0.0 : (cell.occupied || cell.workspaceId === root.activeWorkspace ? 0.98 : 0.78)
                    font.pixelSize: root.textSize
                    font.weight: cell.occupied || cell.workspaceId === root.activeWorkspace ? Font.DemiBold : Font.Medium
                    renderType: Text.QtRendering
                    font.hintingPreference: Font.PreferNoHinting

                    Behavior on opacity {
                        enabled: cell.workspaceId === root.activeWorkspace
                        NumberAnimation {
                            duration: 90
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.ShellActions.switchWorkspace(cell.workspaceId)
                }
            }
        }
    }
}
