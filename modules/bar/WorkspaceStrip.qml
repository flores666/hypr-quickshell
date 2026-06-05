import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Item {
    id: root

    // Компактный strip без общего фона.
    // Занятые рабочие столы и активный рабочий стол объединяются
    // в общие glass-капсулы, чтобы это выглядело одним элементом.
    property int workspaceCount: 10
    property int cellWidth: 23
    property int moduleHeight: 26

    // Было 4. Уменьшено, чтобы виджет визуально сместился немного влево.
    property int sidePadding: 0

    property int circleSize: 18
    property int activeDotSize: 6

    // 0 дает одинаковый верхний и нижний отступ:
    // (moduleHeight - circleSize) / 2 = (27 - 18) / 2 = 4.5px.
    property int contentYOffset: 0

    property int activeWorkspace: Services.ShellState.activeWorkspace
    property int previousWorkspace: Services.ShellState.activeWorkspace
    property int lastAnimatedWorkspace: Services.ShellState.activeWorkspace
    property real trailOpacity: 0.0

    implicitWidth: sidePadding * 2 + workspaceCount * cellWidth
    implicitHeight: moduleHeight

    onActiveWorkspaceChanged: {
        if (activeWorkspace === lastAnimatedWorkspace)
            return;
        previousWorkspace = lastAnimatedWorkspace;
        lastAnimatedWorkspace = activeWorkspace;
        trailOpacity = 0.48;
        trailFade.restart();
    }

    NumberAnimation {
        id: trailFade
        target: root
        property: "trailOpacity"
        from: 0.48
        to: 0.0
        duration: 420
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

    function dotTargetX() {
        return workspaceCenterX(activeWorkspace) - activeDotSize / 2;
    }

    function dotCenterX() {
        return activeDot.x + activeDotSize / 2;
    }

    function dotIsOnWorkspace(workspaceId) {
        return Math.abs(dotCenterX() - workspaceCenterX(workspaceId)) < 3;
    }

    function isOccupied(workspaceId) {
        for (var i = 0; i < Services.ShellState.windows.length; i++) {
            var w = Services.ShellState.windows[i];
            if (w.workspace === workspaceId && !w.hiddenByShell)
                return true;
        }

        return false;
    }

    // Для общего фона считаем выделенными:
    // 1) рабочие столы с окнами;
    // 2) активный рабочий стол, даже если на нем нет окон.
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

    // Trail теперь не рисуется поверх/под occupied и active областями.
    // Он разбивается на отдельные видимые группы и пропускает все highlighted workspace.
    function trailCovers(workspaceId) {
        if (previousWorkspace === activeWorkspace)
            return false;

        var from = Math.min(previousWorkspace, activeWorkspace);
        var to = Math.max(previousWorkspace, activeWorkspace);

        return workspaceId >= from && workspaceId <= to;
    }

    function trailVisibleAt(workspaceId) {
        return trailCovers(workspaceId) && !highlightedForGroup(workspaceId);
    }

    function isTrailGroupStart(workspaceId) {
        if (!trailVisibleAt(workspaceId))
            return false;
        if (workspaceId <= 1)
            return true;
        return !trailVisibleAt(workspaceId - 1);
    }

    function trailGroupEnd(workspaceId) {
        var end = workspaceId;
        while (end < workspaceCount && trailVisibleAt(end + 1))
            end++;
        return end;
    }

    function trailGroupWidth(workspaceId) {
        var end = trailGroupEnd(workspaceId);
        return (end - workspaceId) * cellWidth + circleSize;
    }

    // Сплошной стеклянный след только на незанятых участках между old и new workspace.
    Repeater {
        model: root.workspaceCount

        delegate: Rectangle {
            property int workspaceId: index + 1
            visible: root.trailOpacity > 0.01 && root.isTrailGroupStart(workspaceId)
            y: root.contentCenterY() - height / 2
            x: root.groupX(workspaceId)
            width: root.trailGroupWidth(workspaceId)
            height: root.circleSize
            radius: height / 2
            color: "#66ffffff"
            border.width: 1
            border.color: "#55ffffff"
            opacity: visible ? root.trailOpacity : 0.0
            z: 0
        }
    }

    // Общие капсулы для occupied + active.
    // Если активный стоит рядом с занятыми, он входит в ту же капсулу.
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
            color: "#34ffffff"
            border.width: 1
            border.color: "#45ffffff"
            opacity: visible ? 0.98 : 0.0
            z: 1

            Behavior on x {
                NumberAnimation {
                    duration: 210
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: 210
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

    // Точка активного рабочего стола. Без отдельного фонового круга.
    Rectangle {
        id: activeDot
        y: root.contentCenterY() - height / 2
        x: root.dotTargetX()
        width: root.activeDotSize
        height: root.activeDotSize
        radius: width / 2
        color: "#ffffff"
        opacity: 0.98
        z: 4

        Behavior on x {
            NumberAnimation {
                duration: 310
                easing.type: Easing.OutCubic
            }
        }
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
                property bool hiddenByDot: root.dotIsOnWorkspace(workspaceId)

                width: root.cellWidth
                height: root.moduleHeight

                Text {
                    anchors.centerIn: parent
                    text: cell.workspaceId
                    color: "#ffffff"

                    // Цифра исчезает не по факту смены activeWorkspace,
                    // а только когда точка реально доехала до этого рабочего стола.
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
