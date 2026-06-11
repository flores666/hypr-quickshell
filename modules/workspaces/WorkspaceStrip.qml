import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    property int workspaceCount: 10

    // Размеры считаются от базового 96 DPI и слегка компенсируют разные экраны.
    // Это помогает сохранить одинаковый вид цифр, точки active и капсул на мониторе и ноутбуке.
    readonly property real screenDpi: Screen.pixelDensity > 0 ? Screen.pixelDensity * 25.4 : 96
    readonly property real uiScale: Math.max(0.72, Math.min(1.0, 96 / screenDpi))

    readonly property int cellWidth: Math.round(27 * uiScale)
    readonly property int sidePadding: 0
    readonly property int circleSize: Math.round(23 * uiScale)
    readonly property int moduleHeight: Math.max(circleSize + 4, Math.round(30 * uiScale))
    readonly property int activeDotSize: Math.max(6, Math.round(8 * uiScale))
    readonly property int contentYOffset: 0
    readonly property int textSize: Math.max(10, Math.round(11 * uiScale))

    property int activeWorkspace: Services.ShellState.activeWorkspace
    property int previousWorkspace: Services.ShellState.activeWorkspace
    property int lastAnimatedWorkspace: Services.ShellState.activeWorkspace
    property int visualActiveWorkspace: Services.ShellState.activeWorkspace

    property real activeDotOpacity: 1.0
    // Важно: это обычное значение, а не binding от activeWorkspace.
    // Иначе QML мгновенно переносит activeDotCenterX в новую позицию,
    // затем анимация стартует уже из конечной точки, из-за чего появляется flash/blink.
    property real activeDotCenterX: 0
    property bool ready: false
    property int animationDuration: 280
    property real lastWheelSwitchAt: 0
    property real wheelRemainder: 0

    signal workspaceScrolled()

    implicitWidth: sidePadding * 2 + workspaceCount * cellWidth
    implicitHeight: moduleHeight

    function repaintWorkspaces() {
        if (typeof workspaceCanvas !== "undefined" && workspaceCanvas)
            workspaceCanvas.requestPaint();
    }

    Component.onCompleted: {
        previousWorkspace = activeWorkspace;
        lastAnimatedWorkspace = activeWorkspace;
        visualActiveWorkspace = activeWorkspace;
        activeDotCenterX = workspaceCenterX(activeWorkspace);
        ready = true;
        repaintWorkspaces();
    }

    onActiveWorkspaceChanged: {
        if (!ready)
            return;

        if (activeWorkspace === lastAnimatedWorkspace) {
            repaintWorkspaces();
            return;
        }

        previousWorkspace = lastAnimatedWorkspace;
        lastAnimatedWorkspace = activeWorkspace;

        var distance = Math.abs(activeWorkspace - previousWorkspace);
        animationDuration = Math.max(150, Math.min(245, 150 + distance * 14));

        commitActiveTimer.stop();

        activeDotMove.stop();
        activeDotMove.duration = animationDuration;
        activeDotMove.from = activeDotCenterX;
        activeDotMove.to = workspaceCenterX(activeWorkspace);
        activeDotMove.start();

        commitActiveTimer.interval = animationDuration;
        commitActiveTimer.restart();

        activeDotOpacity = 0.92;
        activeDotFade.restart();
    }

    onActiveDotCenterXChanged: repaintWorkspaces()
    onUiScaleChanged: {
        if (ready && !activeDotMove.running)
            activeDotCenterX = workspaceCenterX(visualActiveWorkspace);
        repaintWorkspaces();
    }

    onCellWidthChanged: {
        if (ready && !activeDotMove.running)
            activeDotCenterX = workspaceCenterX(visualActiveWorkspace);
        repaintWorkspaces();
    }

    onCircleSizeChanged: repaintWorkspaces()
    onModuleHeightChanged: repaintWorkspaces()

    Connections {
        target: Services.ShellState

        function onOccupiedWorkspacesChanged() {
            repaintWorkspaces();
        }
    }

    NumberAnimation {
        id: activeDotMove
        target: root
        property: "activeDotCenterX"
        duration: root.animationDuration
        easing.type: Easing.OutCubic
        alwaysRunToEnd: false
    }

    NumberAnimation {
        id: activeDotFade
        target: root
        property: "activeDotOpacity"
        from: 0.92
        to: 1.0
        duration: 115
        easing.type: Easing.OutCubic
        alwaysRunToEnd: false
    }

    Timer {
        id: commitActiveTimer
        repeat: false
        onTriggered: {
            root.visualActiveWorkspace = root.activeWorkspace;
            root.repaintWorkspaces();
        }
    }

    function clampWorkspace(workspaceId) {
        if (workspaceId < 1)
            return 1;
        if (workspaceId > workspaceCount)
            return workspaceCount;
        return workspaceId;
    }


    function scrollWorkspace(deltaY) {
        if (deltaY === 0)
            return;

        var now = Date.now();
        if (now - lastWheelSwitchAt < 42)
            return;

        lastWheelSwitchAt = now;
        var direction = deltaY > 0 ? -1 : 1;
        root.workspaceScrolled();
        Services.ShellActions.switchWorkspace(clampWorkspace(activeWorkspace + direction));
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

    function dotCoverAmount(workspaceId) {
        // Цифра пропадает синхронно с белой activeDot: не по таймеру и не после
        // смены visualActiveWorkspace, а прямо по текущей анимируемой позиции точки.
        var distance = Math.abs(activeDotCenterX - workspaceCenterX(workspaceId));
        var fullHideDistance = Math.max(2, activeDotSize * 0.9);
        var fadeDistance = Math.max(fullHideDistance + 1, circleSize * 0.48);

        if (distance <= fullHideDistance)
            return 1.0;
        if (distance >= fadeDistance)
            return 0.0;

        var t = (distance - fullHideDistance) / (fadeDistance - fullHideDistance);
        return 1.0 - t;
    }

    function textOpacityForWorkspace(workspaceId, occupied) {
        // Активность больше не влияет на цвет/прозрачность цифры.
        // Иначе после ухода activeDot было заметно, как текст меняет оттенок.
        var baseOpacity = occupied ? 0.98 : 0.86;
        var cover = dotCoverAmount(workspaceId);
        return baseOpacity * (1.0 - cover);
    }

    Canvas {
        id: workspaceCanvas
        anchors.fill: parent
        z: 1

        function appendInterval(intervals, x1, x2) {
            if (x2 < x1) {
                var tmp = x1;
                x1 = x2;
                x2 = tmp;
            }

            intervals.push({
                start: x1,
                end: x2
            });
        }

        function mergeIntervals(intervals) {
            if (intervals.length <= 1)
                return intervals;

            intervals.sort(function (a, b) {
                return a.start - b.start;
            });

            var merged = [];
            var joinGap = Math.max(1, root.cellWidth - root.circleSize + 0.75);

            for (var i = 0; i < intervals.length; i++) {
                var current = intervals[i];

                if (merged.length === 0) {
                    merged.push({
                        start: current.start,
                        end: current.end
                    });
                    continue;
                }

                var last = merged[merged.length - 1];
                if (current.start <= last.end + joinGap) {
                    last.end = Math.max(last.end, current.end);
                } else {
                    merged.push({
                        start: current.start,
                        end: current.end
                    });
                }
            }

            return merged;
        }

        function drawCapsule(ctx, x, y, w, h) {
            var r = h / 2;

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

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            // Контрастная подложка для занятых/активного workspace.
            // Раньше фон был слишком прозрачным и терялся на светлых обоях.
            ctx.fillStyle = "rgba(8, 10, 16, 0.72)";
            ctx.globalAlpha = 1.0;

            var y = root.contentCenterY() - root.circleSize / 2;
            var radius = root.circleSize / 2;
            var intervals = [];

            // Занятые рабочие столы рисуются как стабильная база.
            // Активный рабочий стол не загорается в конечной точке мгновенно:
            // activeDotCenterX больше не привязан к activeWorkspace, поэтому Canvas
            // видит только плавное движение, а не мгновенный прыжок в новую позицию.
            // Потом интервалы объединяются и заливаются один раз, без наложения прозрачных слоев.
            for (var ws = 1; ws <= root.workspaceCount; ws++) {
                if (root.isOccupied(ws)) {
                    var center = root.workspaceCenterX(ws);
                    appendInterval(intervals, center - radius, center + radius);
                }
            }

            appendInterval(intervals, root.activeDotCenterX - radius, root.activeDotCenterX + radius);

            var merged = mergeIntervals(intervals);
            for (var i = 0; i < merged.length; i++) {
                var item = merged[i];
                drawCapsule(ctx, item.start, y, item.end - item.start, root.circleSize);
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
        opacity: root.activeDotOpacity
        border.width: 0
        antialiasing: true
        smooth: true
        layer.enabled: true
        layer.smooth: true
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
                property bool active: workspaceId === root.visualActiveWorkspace

                width: root.cellWidth
                height: root.moduleHeight

                Components.StyledText {
                    anchors.centerIn: parent
                    text: cell.workspaceId
                    color: "#ffffff"
                    opacity: root.textOpacityForWorkspace(cell.workspaceId, cell.occupied)
                    // Черная обводка держит цифры читаемыми даже на очень светлых обоях.
                    style: Text.Outline
                    styleColor: "#b0000000"
                    font.pixelSize: root.textSize
                    font.weight: cell.occupied ? Font.DemiBold : Font.Medium
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.ShellActions.switchWorkspace(cell.workspaceId)
                    onWheel: function(wheel) {
                        var deltaY = wheel.angleDelta.y;
                        if (!deltaY)
                            deltaY = wheel.pixelDelta.y;
                        if (deltaY)
                            root.scrollWorkspace(deltaY);
                        wheel.accepted = true;
                    }
                }
            }
        }
    }
}
