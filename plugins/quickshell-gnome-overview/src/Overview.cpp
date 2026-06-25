#include "Overview.hpp"
#include "Globals.hpp"
#include <hyprland/src/config/shared/animation/AnimationTree.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <algorithm>
#include <cmath>
#include <functional>
#include <string>

extern std::function<void()> overviewAnimatedHideFinishedCallback;

static void notifyQuickshellOverviewState(const char* state) {
    if (g_pEventManager)
        g_pEventManager->postEvent(SHyprIPCEvent{"quickshelloverview", state});
}

CHyprspaceWidget::CHyprspaceWidget(uint64_t inOwnerID) {
    ownerID = inOwnerID;
    workspaceScrollAccumulator = 0.0;
    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    closeNotifiedForWorkspaceSelection = false;
    closeNotifyPendingForAnimatedHide = false;
    releaseAfterCloseNotification = false;
    applicationsModeResetPendingForAnimatedHide = false;
    applicationsTransitionStartedFromOverview = false;
    applicationsLayerReadyForTransition = false;
    applicationsLayerHiddenForClose = false;
    applicationsLayerSettledNotified = false;
    applicationsReturningToOverview = false;
    applyingWorkspaceActivation = false;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
}

CHyprspaceWidget::~CHyprspaceWidget() {
    restoreWorkspaceTransitionAnimation();
}

PHLMONITOR CHyprspaceWidget::getOwner() const {
    return g_pCompositor->getMonitorFromID(ownerID);
}

void CHyprspaceWidget::closeOwnerSpecialWorkspace() {
    auto owner = getOwner();
    if (!owner)
        return;

    // Opening overview must detach any visible special workspace first. If the
    // special overlay is left attached, selecting the underlying workspace can
    // make Hyprland/Quickshell toggle the same special workspace back on.
    owner->setSpecialWorkspace(nullptr);
}

void CHyprspaceWidget::suppressWorkspaceTransitionAnimation() {
    auto workspaceAnimationConfig = Config::animationTree()->getAnimationPropertyConfig("workspaces");
    if (!workspaceAnimationConfig)
        return;

    auto workspaceAnimationValues = workspaceAnimationConfig->pValues.lock();
    if (!workspaceAnimationValues)
        return;

    if (!workspaceAnimationSuppressed) {
        savedWorkspaceAnimation = *workspaceAnimationValues;
        workspaceAnimationSuppressed = true;
    }

    workspaceAnimationValues->internalEnabled = 0;
    workspaceAnimationValues->internalSpeed = 0.F;
}

void CHyprspaceWidget::restoreWorkspaceTransitionAnimation() {
    if (!workspaceAnimationSuppressed)
        return;

    auto workspaceAnimationConfig = Config::animationTree()->getAnimationPropertyConfig("workspaces");
    if (workspaceAnimationConfig) {
        auto workspaceAnimationValues = workspaceAnimationConfig->pValues.lock();
        if (workspaceAnimationValues)
            *workspaceAnimationValues = savedWorkspaceAnimation;
    }

    workspaceAnimationSuppressed = false;
}

void CHyprspaceWidget::setOverviewCursor() {
    if (g_pHyprRenderer)
        g_pHyprRenderer->setCursorFromName("left_ptr", true);
}

void CHyprspaceWidget::warpWorkspaceTransitionState(int visibleWorkspaceID) {
    auto owner = getOwner();
    if (!owner)
        return;

    const int targetID = visibleWorkspaceID > 0
        ? visibleWorkspaceID
        : std::max(1, static_cast<int>(owner->activeWorkspaceID()));

    auto warpWorkspace = [&](int workspaceID) {
        const auto workspace = g_pCompositor->getWorkspaceByID(workspaceID);
        if (!workspace || !workspace->m_monitor)
            return;
        if (workspace->m_monitor->m_id != ownerID)
            return;
        if (workspace->m_isSpecialWorkspace)
            return;

        // Only reset the compositor's slide offset. Do not force alpha or
        // m_forceRendering here: Hyprland owns workspace visibility. Forcing
        // alpha on a non-active workspace is what could leave the desktop in a
        // visually blocked/half-hidden state after the overview released input.
        if (workspace->m_renderOffset)
            workspace->m_renderOffset->setValueAndWarp(Vector2D{0, 0});
    };

    // Do not access g_pCompositor->m_workspaces directly: it is private in
    // current Hyprland versions. Warp only the public workspace objects we know
    // about from the overview ribbon plus the active and target workspaces.
    for (const int id : overviewWorkspaceIds())
        warpWorkspace(id);

    warpWorkspace(std::max(1, static_cast<int>(owner->activeWorkspaceID())));
    warpWorkspace(targetID);
}

void CHyprspaceWidget::activateWorkspaceForOverview(int targetWorkspaceID) {
    auto owner = getOwner();
    if (!owner || targetWorkspaceID < 1)
        return;

    PHLWORKSPACE targetWorkspace = g_pCompositor->getWorkspaceByID(targetWorkspaceID);
    if (!targetWorkspace)
        targetWorkspace = g_pCompositor->createNewWorkspace(targetWorkspaceID, owner->m_id, std::to_string(targetWorkspaceID), true);

    if (targetWorkspace)
        owner->changeWorkspace(targetWorkspace, false, true);
    else
        owner->changeWorkspace(targetWorkspaceID, false, true);
}

int CHyprspaceWidget::maxOccupiedWorkspaceID() const {
    const auto owner = getOwner();
    if (!owner)
        return 1;

    int maxID = 0;
    for (auto& window : g_pCompositor->m_windows) {
        if (!window || !window->m_isMapped || !window->m_workspace || !window->m_workspace->m_monitor)
            continue;
        if (window->m_workspace->m_monitor->m_id != ownerID)
            continue;
        if (window->m_workspace->m_id < 1)
            continue;

        const int id = static_cast<int>(window->m_workspace->m_id);
        maxID = std::max(maxID, id);
    }

    return maxID;
}

int CHyprspaceWidget::maxSelectableWorkspaceID() const {
    return std::max(1, maxOccupiedWorkspaceID() + 1);
}

std::vector<int> CHyprspaceWidget::overviewWorkspaceIds() const {
    std::vector<int> result;

    const auto owner = getOwner();
    if (!owner)
        return result;

    auto pushUnique = [&result](int id) {
        if (id < 1)
            return;
        if (std::find(result.begin(), result.end(), id) == result.end())
            result.push_back(id);
    };

    pushUnique(1);

    for (auto& window : g_pCompositor->m_windows) {
        if (!window || !window->m_isMapped || !window->m_workspace || !window->m_workspace->m_monitor)
            continue;
        if (window->m_workspace->m_monitor->m_id != ownerID)
            continue;
        if (window->m_workspace->m_id < 1)
            continue;

        pushUnique(static_cast<int>(window->m_workspace->m_id));
    }

    const int activeWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    pushUnique(activeWorkspaceID);
    pushUnique(centeredWorkspaceID);
    pushUnique(workspaceSelectionFromID);
    pushUnique(workspaceSelectionToID);
    pushUnique(maxSelectableWorkspaceID());

    std::sort(result.begin(), result.end());

    return result;
}

static double overviewSelectionEase(double value) {
    const double t = std::clamp(value, 0.0, 1.0);
    return t < 0.5
        ? 4.0 * t * t * t
        : 1.0 - std::pow(-2.0 * t + 2.0, 3.0) / 2.0;
}

double CHyprspaceWidget::workspaceSelectionProgress() const {
    if (!workspaceSelectionAnimating)
        return 1.0;

    constexpr double WORKSPACE_SELECTION_SECONDS = 0.24;
    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - workspaceSelectionAnimationStartedAt).count();
    return std::clamp(elapsed / WORKSPACE_SELECTION_SECONDS, 0.0, 1.0);
}

bool CHyprspaceWidget::workspaceSelectionCloseMorphActive() const {
    return workspaceSelectionAnimating && closeAfterWorkspaceSelectionAnimation;
}

double CHyprspaceWidget::visualCenterWorkspaceIndex(const std::vector<int>& ids) const {
    if (ids.empty())
        return 0.0;

    auto indexOfWorkspace = [&](int workspaceID) -> double {
        auto it = std::find(ids.begin(), ids.end(), workspaceID);
        if (it == ids.end()) {
            it = std::lower_bound(ids.begin(), ids.end(), workspaceID);
            if (it == ids.end())
                return static_cast<double>(ids.size() - 1);
        }
        return static_cast<double>(std::distance(ids.begin(), it));
    };

    if (workspaceSelectionAnimating) {
        const double fromIndex = indexOfWorkspace(workspaceSelectionFromID);
        const double toIndex = indexOfWorkspace(workspaceSelectionToID);
        const double progress = overviewSelectionEase(workspaceSelectionProgress());
        return fromIndex + (toIndex - fromIndex) * progress;
    }

    const int centerID = centeredWorkspaceID > 0
        ? centeredWorkspaceID
        : (getOwner() ? std::max(1, static_cast<int>(getOwner()->activeWorkspaceID())) : 1);
    return indexOfWorkspace(centerID);
}

bool CHyprspaceWidget::isSelectingWorkspace() const {
    return workspaceSelectionAnimating;
}

bool CHyprspaceWidget::startWorkspaceSelectionAnimation(int targetWorkspaceID, bool closeAfterAnimation) {
    auto owner = getOwner();
    if (!owner || targetWorkspaceID < 1)
        return false;

    targetWorkspaceID = std::clamp(targetWorkspaceID, 1, maxSelectableWorkspaceID());

    const int currentWorkspaceID = centeredWorkspaceID > 0
        ? centeredWorkspaceID
        : std::max(1, static_cast<int>(owner->activeWorkspaceID()));

    closeOwnerSpecialWorkspace();
    workspaceScrollAccumulator = 0.0;

    if (targetWorkspaceID == currentWorkspaceID && !closeAfterAnimation) {
        centeredWorkspaceID = targetWorkspaceID;
        return true;
    }

    if (targetWorkspaceID == currentWorkspaceID && closeAfterAnimation && owner->activeWorkspaceID() == targetWorkspaceID) {
        centeredWorkspaceID = targetWorkspaceID;
        hide();
        return true;
    }

    // Even when the target is already centered, it can still differ from the
    // real active Hyprland workspace. This happens after the topbar moved the
    // overview ribbon without switching the desktop. In that case we must still
    // run a close/activation morph and call changeWorkspace() at the end instead
    // of just hiding the overlay back to the old workspace.
    workspaceSelectionFromID = currentWorkspaceID;
    workspaceSelectionToID = targetWorkspaceID;
    closeAfterWorkspaceSelectionAnimation = closeAfterAnimation;
    closeNotifiedForWorkspaceSelection = closeAfterAnimation;
    if (closeAfterAnimation)
        notifyQuickshellOverviewState("close");
    workspaceSelectionAnimationStartedAt = std::chrono::steady_clock::now();
    workspaceSelectionAnimating = true;
    workspaceHoverProgress.clear();
    lastWorkspaceHoverFrameValid = false;

    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
    return true;
}

void CHyprspaceWidget::finishWorkspaceSelectionAnimation() {
    if (!workspaceSelectionAnimating)
        return;

    auto owner = getOwner();
    const int targetWorkspaceID = workspaceSelectionToID > 0 ? workspaceSelectionToID : centeredWorkspaceID;
    const bool shouldClose = closeAfterWorkspaceSelectionAnimation;

    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    closeNotifiedForWorkspaceSelection = false;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    centeredWorkspaceID = targetWorkspaceID;
    workspaceScrollAccumulator = 0.0;
    workspaceHoverProgress.clear();
    lastWorkspaceHoverFrameValid = false;

    if (owner && targetWorkspaceID > 0 && shouldClose) {
        suppressWorkspaceTransitionAnimation();

        // This workspace switch is owned by the overview close animation. Keep
        // onWorkspaceChange from treating it as a new external switch, otherwise
        // the strip can briefly sync back to the previous workspace and then to
        // the target again.
        applyingWorkspaceActivation = true;

        // Put Hyprland workspace render vars into the final state before and
        // after the actual change. The overlay covers this frame, but it prevents
        // the compositor's own workspace swipe from leaking through after the
        // GNOME-like morph has finished.
        warpWorkspaceTransitionState(targetWorkspaceID);
        if (owner->activeWorkspaceID() != targetWorkspaceID)
            activateWorkspaceForOverview(targetWorkspaceID);
        warpWorkspaceTransitionState(targetWorkspaceID);

        // Keep the guard enabled until finishHide() flips active to false. Some
        // Hyprland workspace-change notifications can be delivered after
        // changeWorkspace() returns but before the overview overlay is released.
    }

    if (shouldClose) {
        // The preview has already swiped and morphed to fullscreen during the
        // selection animation, so do not start a second exit morph. Switch to
        // the real workspace at the final frame and immediately release the
        // overlay.
        finishHide();
        if (owner)
            g_pHyprRenderer->damageMonitor(owner);
        return;
    }

    if (owner) {
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
    }
}

bool CHyprspaceWidget::switchOverviewWorkspaceBy(int direction) {
    auto owner = getOwner();
    if (!owner || direction == 0)
        return false;

    const auto ids = overviewWorkspaceIds();
    if (ids.empty())
        return false;

    const int currentWorkspaceID = centeredWorkspaceID > 0
        ? centeredWorkspaceID
        : std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    const auto currentIt = std::find(ids.begin(), ids.end(), currentWorkspaceID);
    int targetWorkspaceID = currentWorkspaceID;
    if (currentIt != ids.end()) {
        if (direction > 0) {
            const auto nextIt = std::next(currentIt);
            targetWorkspaceID = nextIt != ids.end() ? *nextIt : currentWorkspaceID + 1;
        } else {
            targetWorkspaceID = currentIt != ids.begin() ? *std::prev(currentIt) : std::max(1, currentWorkspaceID - 1);
        }
    } else {
        const auto lowerIt = std::lower_bound(ids.begin(), ids.end(), currentWorkspaceID);
        if (direction > 0)
            targetWorkspaceID = lowerIt != ids.end() ? *lowerIt : currentWorkspaceID + 1;
        else
            targetWorkspaceID = lowerIt != ids.begin() ? *std::prev(lowerIt) : std::max(1, currentWorkspaceID - 1);
    }

    if (targetWorkspaceID == currentWorkspaceID)
        return false;

    targetWorkspaceID = std::clamp(targetWorkspaceID, 1, maxSelectableWorkspaceID());
    if (targetWorkspaceID == currentWorkspaceID)
        return false;

    return startWorkspaceSelectionAnimation(targetWorkspaceID, false);
}

bool CHyprspaceWidget::selectWorkspaceInOverview(int targetWorkspaceID) {
    if (!active || isClosing() || isSelectingWorkspace() || targetWorkspaceID < 1)
        return false;

    return startWorkspaceSelectionAnimation(targetWorkspaceID, false);
}

bool CHyprspaceWidget::activateWorkspaceInOverview(int targetWorkspaceID) {
    if (!active || isClosing() || isSelectingWorkspace() || targetWorkspaceID < 1)
        return false;

    return startWorkspaceSelectionAnimation(targetWorkspaceID, true);
}

bool CHyprspaceWidget::selectWorkspaceInOverviewBy(int direction) {
    if (!active || isClosing() || isSelectingWorkspace() || direction == 0)
        return false;

    return switchOverviewWorkspaceBy(direction);
}

bool CHyprspaceWidget::activateWorkspaceBy(int direction) {
    auto owner = getOwner();
    if (!owner || direction == 0)
        return false;

    closeOwnerSpecialWorkspace();

    const int currentWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    const int targetWorkspaceID = std::clamp(currentWorkspaceID + (direction > 0 ? 1 : -1), 1, maxSelectableWorkspaceID());
    if (targetWorkspaceID == currentWorkspaceID)
        return false;

    activateWorkspaceForOverview(targetWorkspaceID);

    if (owner) {
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
    }

    return true;
}

bool CHyprspaceWidget::syncExternalWorkspaceSwitch(int targetWorkspaceID) {
    if (applyingWorkspaceActivation)
        return false;

    if (!active || isClosing() || targetWorkspaceID < 1)
        return false;

    const auto owner = getOwner();
    if (!owner)
        return false;

    // If Hyprland has already switched while overview is open, the user has
    // performed a real workspace switch outside the topbar ribbon command
    // path, for example mainMod+N or a custom hyprctl bind. Do not keep the
    // overlay open on top of that new workspace. Animate the overview to the
    // same target and release it at the end. This also fixes the race where
    // Hyprland's bind fires before our key hook can cancel it.
    if (isSelectingWorkspace()) {
        workspaceSelectionToID = targetWorkspaceID;
        closeAfterWorkspaceSelectionAnimation = true;
        if (!closeNotifiedForWorkspaceSelection) {
            closeNotifiedForWorkspaceSelection = true;
            notifyQuickshellOverviewState("close");
        }
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
        return true;
    }

    const int currentWorkspaceID = centeredWorkspaceID > 0
        ? centeredWorkspaceID
        : std::max(1, static_cast<int>(owner->activeWorkspaceID()));

    if (currentWorkspaceID == targetWorkspaceID) {
        centeredWorkspaceID = targetWorkspaceID;
        hide();
        return true;
    }

    return startWorkspaceSelectionAnimation(targetWorkspaceID, true);
}

void CHyprspaceWidget::show() {
    const bool wasActive = active;
    const bool wasClosing = overviewClosing;
    auto owner = getOwner();
    if (!owner)
        return;

    // Treat live overview as a regular-workspace mode. Close the special
    // workspace before overview becomes active, no matter whether overview was
    // opened from the dock button, the hot corner, or the single Super key.
    closeOwnerSpecialWorkspace();
    suppressWorkspaceTransitionAnimation();

    active = true;
    overviewClosing = false;
    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    closeNotifiedForWorkspaceSelection = false;
    closeNotifyPendingForAnimatedHide = false;
    releaseAfterCloseNotification = false;
    applicationsModeResetPendingForAnimatedHide = false;
    applicationsTransitionStartedFromOverview = false;
    applicationsLayerReadyForTransition = false;
    applicationsLayerHiddenForClose = false;
    applicationsLayerSettledNotified = false;
    applicationsReturningToOverview = false;
    applyingWorkspaceActivation = false;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    centeredWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    workspaceScrollAccumulator = 0.0;

    lastWorkspaceHoverFrameValid = false;

    if (!wasActive || wasClosing) {
        overviewAnimationStarted = true;
        overviewAnimationStartedAt = std::chrono::steady_clock::now();
        workspaceHoverProgress.clear();
        workspaceAppearProgress.clear();
        notifyQuickshellOverviewState("open");
    }

    // Refresh pointer focus after enabling overview so stale client cursors
    // like text/select/resize do not remain visible over the overview. The input
    // hooks above keep this synthetic motion from reaching normal windows.
    g_pInputManager->refocus();
    g_pInputManager->simulateMouseMovement();
    setOverviewCursor();

    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
}

void CHyprspaceWidget::startApplicationsTransitionFromOverview() {
    auto owner = getOwner();
    if (!owner)
        return;

    if (!active) {
        applicationsTransitionStartedFromOverview = false;
        applicationsLayerReadyForTransition = false;
        applicationsLayerHiddenForClose = false;
        applicationsLayerSettledNotified = false;
        show();
        return;
    }

    closeOwnerSpecialWorkspace();
    suppressWorkspaceTransitionAnimation();

    overviewClosing = false;
    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    closeNotifiedForWorkspaceSelection = false;
    closeNotifyPendingForAnimatedHide = false;
    releaseAfterCloseNotification = false;
    applicationsModeResetPendingForAnimatedHide = false;
    applicationsTransitionStartedFromOverview = true;
    applicationsLayerReadyForTransition = false;
    applicationsLayerHiddenForClose = false;
    applicationsLayerSettledNotified = false;
    applicationsReturningToOverview = false;
    applyingWorkspaceActivation = false;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    if (centeredWorkspaceID <= 0)
        centeredWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    workspaceScrollAccumulator = 0.0;
    workspaceHoverProgress.clear();
    lastWorkspaceHoverFrameValid = false;

    overviewAnimationStarted = true;
    overviewAnimationStartedAt = std::chrono::steady_clock::now() - std::chrono::duration_cast<std::chrono::steady_clock::duration>(
        std::chrono::duration<double>(APPLICATIONS_OPEN_ANIMATION_SECONDS * APPLICATIONS_FROM_OVERVIEW_START_PROGRESS));

    setOverviewCursor();
    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
}

double CHyprspaceWidget::applicationsReturnProgress() const {
    if (!applicationsReturningToOverview)
        return 1.0;

    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - applicationsReturnStartedAt).count();
    return std::clamp(elapsed / APPLICATIONS_RETURN_ANIMATION_SECONDS, 0.0, 1.0);
}

void CHyprspaceWidget::startApplicationsReturnToOverview() {
    auto owner = getOwner();
    if (!owner || !active)
        return;

    closeOwnerSpecialWorkspace();
    suppressWorkspaceTransitionAnimation();

    overviewClosing = false;
    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    closeNotifiedForWorkspaceSelection = false;
    closeNotifyPendingForAnimatedHide = false;
    releaseAfterCloseNotification = false;
    applicationsModeResetPendingForAnimatedHide = false;
    applicationsTransitionStartedFromOverview = true;
    applicationsLayerReadyForTransition = true;
    applicationsLayerHiddenForClose = false;
    applicationsLayerSettledNotified = false;
    applicationsReturningToOverview = true;
    applicationsReturnStartedAt = std::chrono::steady_clock::now();
    notifyQuickshellOverviewState("applications-closing");
    applyingWorkspaceActivation = false;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    if (centeredWorkspaceID <= 0)
        centeredWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    workspaceScrollAccumulator = 0.0;
    workspaceHoverProgress.clear();
    lastWorkspaceHoverFrameValid = false;
    overviewAnimationStarted = true;

    setOverviewCursor();
    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
}

void CHyprspaceWidget::finishHide() {
    const int visibleWorkspaceID = centeredWorkspaceID;
    const bool shouldNotifyClose = closeNotifyPendingForAnimatedHide;
    const bool shouldResetApplicationsMode = applicationsModeResetPendingForAnimatedHide;
    active = false;
    overviewClosing = false;
    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    closeNotifiedForWorkspaceSelection = false;
    closeNotifyPendingForAnimatedHide = false;
    releaseAfterCloseNotification = false;
    applicationsModeResetPendingForAnimatedHide = false;
    applicationsTransitionStartedFromOverview = false;
    applicationsLayerReadyForTransition = false;
    applicationsLayerHiddenForClose = false;
    applicationsLayerSettledNotified = false;
    applicationsReturningToOverview = false;
    applyingWorkspaceActivation = false;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    centeredWorkspaceID = 0;
    workspaceBoxes.clear();
    workspaceScrollAccumulator = 0.0;

    workspaceHoverProgress.clear();
    workspaceAppearProgress.clear();
    lastWorkspaceHoverFrameValid = false;
    overviewAnimationStarted = false;
    warpWorkspaceTransitionState(visibleWorkspaceID);
    restoreWorkspaceTransitionAnimation();

    // After leaving overview, restore normal pointer focus/cursor state. Do it
    // only after the exit morph finishes, otherwise the real windows below the
    // shrinking preview can receive hover/focus while the overview is visible.
    g_pInputManager->refocus();
    g_pInputManager->simulateMouseMovement();

    if (shouldNotifyClose) {
        notifyQuickshellOverviewState("close");
    }

    if (shouldResetApplicationsMode) {
        if (overviewAnimatedHideFinishedCallback)
            overviewAnimatedHideFinishedCallback();
    }
}

bool CHyprspaceWidget::holdFinalFrameForCloseNotification() {
    if (!closeNotifyPendingForAnimatedHide && !releaseAfterCloseNotification)
        return false;

    auto owner = getOwner();
    if (!owner)
        return false;

    const auto now = std::chrono::steady_clock::now();
    if (closeNotifyPendingForAnimatedHide) {
        closeNotifyPendingForAnimatedHide = false;
        releaseAfterCloseNotification = true;
        releaseAfterCloseNotificationStartedAt = now;
        notifyQuickshellOverviewState("close");
    }

    constexpr auto CLOSE_RELEASE_HOLD = std::chrono::milliseconds(50);
    if (now - releaseAfterCloseNotificationStartedAt < CLOSE_RELEASE_HOLD) {
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
        return true;
    }

    return false;
}

void CHyprspaceWidget::hide() {
    const bool wasActive = active;
    auto owner = getOwner();
    if (!owner)
        return;

    if (!wasActive)
        return;

    if (!workspaceSelectionAnimating && !overviewClosing && centeredWorkspaceID > 0) {
        const int activeWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
        if (centeredWorkspaceID != activeWorkspaceID) {
            // Closing commits the workspace currently targeted by the overview
            // ribbon. This lets scroll/dock/Super/Escape behave like one flow:
            // browse first, activate on close.
            startWorkspaceSelectionAnimation(centeredWorkspaceID, true);
            return;
        }
    }

    if (workspaceSelectionAnimating) {
        closeAfterWorkspaceSelectionAnimation = true;
        if (!closeNotifiedForWorkspaceSelection) {
            closeNotifiedForWorkspaceSelection = true;
            notifyQuickshellOverviewState("close");
        }
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
        return;
    }

    if (!overviewClosing) {
        overviewClosing = true;
        overviewClosingStartedAt = std::chrono::steady_clock::now();
        overviewAnimationStarted = false;
        workspaceHoverProgress.clear();
        lastWorkspaceHoverFrameValid = false;
        workspaceScrollAccumulator = 0.0;
        notifyQuickshellOverviewState("close");
    }

    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
}

void CHyprspaceWidget::hideKeepingWorkspace(int workspaceID) {
    const auto owner = getOwner();
    if (!owner || !active)
        return;

    const int targetWorkspaceID = workspaceID > 0
        ? workspaceID
        : std::max(1, static_cast<int>(owner->activeWorkspaceID()));

    if (overviewClosing && releaseAfterCloseNotification) {
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
        return;
    }

    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    closeNotifiedForWorkspaceSelection = false;
    closeNotifyPendingForAnimatedHide = true;
    releaseAfterCloseNotification = false;
    applicationsModeResetPendingForAnimatedHide = true;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    applicationsReturningToOverview = false;
    applicationsLayerHiddenForClose = false;
    applicationsLayerSettledNotified = false;
    centeredWorkspaceID = targetWorkspaceID;

    if (!overviewClosing) {
        overviewClosing = true;
        overviewClosingStartedAt = std::chrono::steady_clock::now();
        overviewAnimationStarted = false;
        workspaceHoverProgress.clear();
        lastWorkspaceHoverFrameValid = false;
        workspaceScrollAccumulator = 0.0;
        notifyQuickshellOverviewState("applications-closing");
    }

    applyingWorkspaceActivation = true;
    suppressWorkspaceTransitionAnimation();
    warpWorkspaceTransitionState(targetWorkspaceID);
    if (owner->activeWorkspaceID() != targetWorkspaceID)
        activateWorkspaceForOverview(targetWorkspaceID);
    warpWorkspaceTransitionState(targetWorkspaceID);

    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
}

static double animationProgressFromStart(const std::chrono::steady_clock::time_point& startedAt, double durationSeconds) {
    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - startedAt).count();
    return std::clamp(elapsed / std::max(0.001, durationSeconds), 0.0, 1.0);
}

double CHyprspaceWidget::overviewOpenProgress() const {
    if (overviewClosing)
        return 1.0 - animationProgressFromStart(overviewClosingStartedAt, OVERVIEW_CLOSE_ANIMATION_SECONDS);

    if (!overviewAnimationStarted)
        return 1.0;

    return animationProgressFromStart(overviewAnimationStartedAt, OVERVIEW_OPEN_ANIMATION_SECONDS);
}

double CHyprspaceWidget::applicationsOverviewOpenProgress() const {
    if (overviewClosing)
        return 1.0 - animationProgressFromStart(overviewClosingStartedAt, APPLICATIONS_CLOSE_ANIMATION_SECONDS);

    if (!overviewAnimationStarted)
        return 1.0;

    return animationProgressFromStart(overviewAnimationStartedAt, APPLICATIONS_OPEN_ANIMATION_SECONDS);
}

bool CHyprspaceWidget::isClosing() const {
    return overviewClosing;
}

bool CHyprspaceWidget::isAnimating() const {
    if (!active)
        return false;

    if (overviewClosing || workspaceSelectionAnimating || applicationsReturningToOverview)
        return true;

    if (!overviewAnimationStarted)
        return false;

    return overviewOpenProgress() < 0.995 || applicationsOverviewOpenProgress() < 0.995;
}

bool CHyprspaceWidget::isApplyingWorkspaceActivation() const {
    return applyingWorkspaceActivation;
}

bool CHyprspaceWidget::isActive() {
    return active;
}
