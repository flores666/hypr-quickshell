import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Item {
    id: root

    property int workspaceCount: 10
    property int cellWidth: 23
    property int moduleHeight: 26
    property int sidePadding: 0
    property int circleSize: 18
    property int activeDotSize: 6
    property int contentYOffset: 0

    property int activeWorkspace: Services.ShellState.activeWorkspace
    property int previousWorkspace: Services.ShellState.activeWorkspace
    property int lastAnimatedWorkspace: Services.ShellState.activeWorkspace

    property real trailOpacity: 0.0
    property real activeDotOpacity: 1.0
    property real activeDotCenterX: workspaceCenterX(Services.ShellState.activeWorkspace)

    implicitWidth: sidePadding * 2 + workspaceCount * cellWidth
    implicitHeight: moduleHeight

    onActiveWorkspaceChanged: {
        if (activeWorkspace === lastAnimatedWorkspace)
            return;

        previousWorkspace = lastAnimatedWorkspace;
        lastAnimatedWorkspace = activeWorkspace;

        activeDotMove.stop();
        activeDotMove.to = workspaceCenterX(activeWorkspace);
        activeDotMove.start();

        trailOpacity = 0.40;
        activeDotOpacity = 0.0;

        trailFade.restart();
        activeDotFade.restart();
    }

    NumberAnimation {
        id: activeDotMove
        target: root
        property: "activeDotCenterX"
        duration: 310
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: trailFade
        target: root
        property: "trailOpacity"
        from: 0.40
        to: 0.0
        duration: 420
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: activeDotFade
        target: root
        property: "activeDotOpacity"
        from: 0.0
        to: 1.0
        duration: 260
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

    function dotIsOnWorkspace(workspaceId) {
        return activeDotOpacity > 0.72 && Math.abs(activeDotCenterX - workspaceCenterX(workspaceId)) < 3;
    }

    function isOccupied(workspaceId) {
        for (var i = 0; i < Services.ShellState.windows.length; i++) {
            var w = Services.ShellState.windows[i];
            if (w.workspace === workspaceId && !w.hiddenByShell)
                return true;
        }

        return false;
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

    function isOccupiedOnly(workspaceId) {
        return isOccupied(workspaceId);
    }

    function isOccupiedOnlyGroupStart(workspaceId) {
        if (!isOccupiedOnly(workspaceId))
            return false;
        if (workspaceId <= 1)
            return true;
        return !isOccupiedOnly(workspaceId - 1);
    }

    function occupiedOnlyGroupEnd(workspaceId) {
        var end = workspaceId;
        while (end < workspaceCount && isOccupiedOnly(end + 1))
            end++;
        return end;
    }

    function occupiedOnlyGroupWidth(workspaceId) {
        var end = occupiedOnlyGroupEnd(workspaceId);
        return (end - workspaceId) * cellWidth + circleSize;
    }

    function slideFromWorkspace() {
        return previousWorkspace;
    }

    function slideToWorkspace() {
        return activeWorkspace;
    }

    function slideStartWorkspace() {
        return Math.min(slideFromWorkspace(), slideToWorkspace());
    }

    function slideEndWorkspace() {
        return Math.max(slideFromWorkspace(), slideToWorkspace());
    }

    function slideActive() {
        return trailOpacity > 0.01 && previousWorkspace !== activeWorkspace;
    }

    function slideGroupX() {
        return groupX(slideStartWorkspace());
    }

    function slideGroupWidth() {
        return (slideEndWorkspace() - slideStartWorkspace()) * cellWidth + circleSize;
    }

    // Базовые occupied-группы без active. Они нужны как постоянное тело.
    Repeater {
        model: root.workspaceCount

        delegate: Rectangle {
            property int workspaceId: index + 1

            visible: root.isOccupiedOnlyGroupStart(workspaceId)
            y: root.contentCenterY() - height / 2
            x: root.groupX(workspaceId)
            width: root.occupiedOnlyGroupWidth(workspaceId)
            height: root.circleSize
            radius: height / 2
            color: "#261b2330"
            opacity: visible ? 0.98 : 0.0
            z: 1
        }
    }

    // Во время переключения рисуется единая слайд-капсула от старого active до нового.
    // Она остается видимой до конца fade, поэтому конечная active-область не выглядит отдельной.
    Rectangle {
        id: slideBody
        visible: root.slideActive()
        y: root.contentCenterY() - height / 2
        x: root.slideGroupX()
        width: root.slideGroupWidth()
        height: root.circleSize
        radius: height / 2
        color: "#261b2330"
        border.width: 1
        border.color: "#45ffffff"
        opacity: root.trailOpacity
        z: 2
    }

    // Финальная объединенная капсула occupied + active.
    // Появляется поверх slideBody плавно, чтобы в конце active не отделялся от слайда.
    Repeater {
        model: root.workspaceCount

        delegate: Rectangle {
            property int workspaceId: index + 1

            visible: root.isGroupStart(workspaceId)
            y: root.contentCenterY() - height / 2
            x: root.groupX(workspaceId)
            width: root.groupWidth(workspaceId)
            height: root.circleSize
            radius: height / 2
            color: "#261b2330"
            border.width: 1
            border.color: "#45ffffff"
            opacity: visible ? 0.98 : 0.0
            z: 3

            Behavior on x {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
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
        z: 5
    }

    Row {
        id: workspaceRow
        y: root.contentCenterY() - height / 2
        x: root.sidePadding
        spacing: 0
        z: 4

        Repeater {
            model: root.workspaceCount

            delegate: Item {
                id: cell

                property int workspaceId: index + 1
                property bool occupied: root.isOccupied(workspaceId)
                property bool hiddenByDot: root.dotIsOnWorkspace(workspaceId)

                width: root.cellWidth
                height: root.moduleHeight

                Text {
                    anchors.centerIn: parent
                    text: cell.workspaceId
                    color: "#ffffff"
                    opacity: cell.hiddenByDot ? 0.0 : (cell.occupied ? 0.98 : 0.78)
                    font.pixelSize: 12
                    font.weight: cell.occupied ? Font.DemiBold : Font.Medium
                    renderType: Text.NativeRendering

                    Behavior on opacity {
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
