import QtQuick
import "../../services" as Services

Item {
    id: controller

    visible: false

    property var overview: null
    property var searchController: null
    property real inputWindowHeight: 0
    property real animationProgress: 0
    property bool animationBehaviorEnabled: true
    property bool closingVisualActive: false
    property bool closingInputContentActive: false

    readonly property bool applicationsOpen: Services.ShellState.applicationsOverviewOpen
    readonly property bool applicationsClosing: Services.ShellState.applicationsOverviewClosing
    readonly property bool applicationsVisualLayerHidden: Services.ShellState.applicationsOverviewVisualLayerHidden
    readonly property bool applicationsVisualLayerSettled: Services.ShellState.applicationsOverviewVisualLayerSettled
    readonly property bool applicationsClosingState: applicationsClosing || closingVisualActive
    readonly property bool applicationsInteractiveState: applicationsOpen && applicationsVisualLayerSettled && !applicationsClosingState
    readonly property bool applicationsOpeningState: applicationsOpen && !applicationsClosingState && !applicationsInteractiveState
    readonly property bool applicationsRendering: applicationsOpen || closingVisualActive || animationProgress > 0.001
    readonly property string applicationsState: applicationsClosingState ? "closing" : applicationsInteractiveState ? "interactive" : applicationsOpeningState ? "opening" : applicationsRendering ? "settling" : "hidden"
    readonly property bool ownsApplicationsInput: Services.ShellState.inputCaptureOwner === "applicationsOverview"
    readonly property bool applicationsInputInteractive: applicationsState === "interactive" && ownsApplicationsInput
    readonly property int inputTopMargin: 56
    readonly property int inputBottomMargin: 116
    readonly property int visualContentYOffset: 38
    readonly property int inputContentYOffset: 0
    readonly property real desktopCardPhaseEnd: 0.48
    readonly property int closeAnimationDuration: 300
    readonly property int openAnimationDuration: 340
    readonly property real applicationsRiseProgress: smoothStep(desktopCardPhaseEnd, 1.0, animationProgress)
    readonly property bool panelVisuallySettled: applicationsRiseProgress >= 0.998
    readonly property bool applicationsClosingHandoffVisible: applicationsState === "closing" && closingInputContentActive && panelVisuallySettled && !applicationsVisualLayerHidden
    readonly property bool applicationsInputCaptureRequired: applicationsState === "opening" || applicationsState === "interactive" || applicationsState === "closing"
    readonly property int inputPanelMaskHeight: Math.max(0, Math.round(inputWindowHeight) - inputBottomMargin)
    readonly property bool applicationsVisualWindowVisible: applicationsRendering && !applicationsVisualLayerHidden
    readonly property bool applicationsInputContentVisible: applicationsInputInteractive || applicationsClosingHandoffVisible
    readonly property bool applicationsInputWindowVisible: applicationsInputCaptureRequired || applicationsInputContentVisible

    function clamp01(value) {
        return Math.max(0, Math.min(1, Number(value || 0)));
    }

    function smoothStep(edge0, edge1, value) {
        var range = Math.max(0.0001, edge1 - edge0);
        var t = clamp01((value - edge0) / range);
        return t * t * (3 - 2 * t);
    }

    function startOpenAnimation() {
        if (!overview)
            return;

        closeAnimationKickTimer.stop();
        closeCleanupTimer.stop();
        closingVisualActive = false;
        closingInputContentActive = false;
        overview.resetInputReadiness(false);
        overview.closeContextMenu();
        animationBehaviorEnabled = false;
        animationProgress = Services.ShellState.applicationsOverviewFromWorkspaceOverview ? desktopCardPhaseEnd + 0.04 : 0;
        animationBehaviorEnabled = true;
        animationKickTimer.restart();
    }

    function startCloseAnimation() {
        if (!overview || closingVisualActive)
            return;

        animationKickTimer.stop();
        closeCleanupTimer.stop();
        overview.closeContextMenu();
        overview.clearSelection();
        overview.clearPointerSuppression();
        overview.captureContentYForClose();
        closingInputContentActive = applicationsInputInteractive || panelVisuallySettled || applicationsRiseProgress > 0.001;
        closingVisualActive = true;
        animationBehaviorEnabled = false;
        animationProgress = clamp01(animationProgress);
        animationBehaviorEnabled = true;
        closeAnimationKickTimer.restart();
    }

    function finishCloseAnimation() {
        if (!overview || applicationsOpen)
            return;

        closingVisualActive = false;
        closingInputContentActive = false;
        animationBehaviorEnabled = false;
        animationProgress = 0;
        animationBehaviorEnabled = true;
        Services.ShellState.setApplicationsOverviewClosing(false);
        Services.ShellState.setApplicationsOverviewVisualLayerSettled(false);
        if (searchController)
            searchController.query = "";
        overview.resetInputReadiness(false);
        overview.clearSearchFocus();
        overview.clearPointerSuppression();
        overview.closeContextMenu();
        overview.clearSelection();
        overview.rebuildSections(false);
        overview.resetGridContentY();
    }

    function beginApplicationsSession() {
        if (!overview)
            return;

        overview.hiddenSectionExpanded = false;
        if (searchController)
            searchController.query = Services.ShellState.applicationsOverviewInitialQuery;
        Services.ShellState.setApplicationsOverviewInitialQuery("");
        Services.AppPanelService.requestRefresh(false);
        overview.resetGridContentY();
        overview.clearSelection();
        overview.rebuildSections(true);
        startOpenAnimation();
    }

    function handleApplicationsSessionClosed() {
        if (!overview)
            return;

        overview.clearSearchFocus();
        if (closingVisualActive) {
            if (animationProgress <= 0.001)
                finishCloseAnimation();
            else
                closeCleanupTimer.restart();
        } else if (animationProgress > 0.001 || applicationsVisualLayerSettled) {
            startCloseAnimation();
        }
    }

    function setApplicationsInputCapture(active) {
        if (!overview)
            return;

        Services.ShellState.setInputCaptureOwner("applicationsOverview", active);
        if (!active) {
            overview.clearPointerSuppression();
            overview.closeContextMenu();
            overview.clearSelection();
        }
    }

    Behavior on animationProgress {
        enabled: controller.animationBehaviorEnabled
        NumberAnimation {
            duration: controller.closingVisualActive || controller.applicationsClosing ? controller.closeAnimationDuration : controller.openAnimationDuration
            easing.type: Easing.InOutCubic
        }
    }

    Timer {
        id: animationKickTimer
        interval: 0
        repeat: false
        onTriggered: controller.animationProgress = 1
    }

    Timer {
        id: closeAnimationKickTimer
        interval: 0
        repeat: false
        onTriggered: {
            controller.animationProgress = 0;
            closeCleanupTimer.restart();
        }
    }

    Timer {
        id: closeCleanupTimer
        interval: controller.closeAnimationDuration + 40
        repeat: false
        onTriggered: controller.finishCloseAnimation()
    }

    Timer {
        id: inputReleaseWatchdogTimer
        interval: controller.closeAnimationDuration + 260
        repeat: false
        running: controller.closingVisualActive && !controller.applicationsOpen
        onTriggered: controller.finishCloseAnimation()
    }
}
