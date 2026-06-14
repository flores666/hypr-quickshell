#include "Overview.hpp"
#include "Globals.hpp"
#include <hyprland/src/config/shared/animation/AnimationTree.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <algorithm>
#include <cmath>

static void notifyQuickshellOverviewState(const char* state) {
    if (g_pEventManager)
        g_pEventManager->postEvent(SHyprIPCEvent{"quickshelloverview", state});
}

CHyprspaceWidget::CHyprspaceWidget(uint64_t inOwnerID) {
    ownerID = inOwnerID;

    curAnimationConfig = *Config::animationTree()->getAnimationPropertyConfig("windows");
    curAnimation = *curAnimationConfig.pValues.lock();
    *curAnimationConfig.pValues.lock() = curAnimation;

    if (Config::overrideAnimSpeed > 0)
        curAnimation.internalSpeed = Config::overrideAnimSpeed;

    g_pAnimationManager->createAnimation(0.F, curYOffset, curAnimationConfig.pValues.lock(), AVARDAMAGE_ENTIRE);
    g_pAnimationManager->createAnimation(0.F, workspaceScrollOffset, curAnimationConfig.pValues.lock(), AVARDAMAGE_ENTIRE);
    curYOffset->setValueAndWarp(0);
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
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



void CHyprspaceWidget::warpWorkspaceTransitionState(int visibleWorkspaceID) {
    auto owner = getOwner();
    if (!owner)
        return;

    const int targetID = visibleWorkspaceID > 0
        ? visibleWorkspaceID
        : std::max(1, static_cast<int>(owner->activeWorkspaceID()));

    auto warpWorkspace = [&](int workspaceID, bool visible) {
        const auto workspace = g_pCompositor->getWorkspaceByID(workspaceID);
        if (!workspace || !workspace->m_monitor)
            return;
        if (workspace->m_monitor->m_id != ownerID)
            return;
        if (workspace->m_isSpecialWorkspace)
            return;

        // Hyprland may already have started its normal workspace slide animation
        // before/around changeWorkspace(). The overview has its own GNOME-like
        // morph, so leave the compositor in the final state immediately.
        if (workspace->m_renderOffset)
            workspace->m_renderOffset->setValueAndWarp(Vector2D{0, 0});

        if (workspace->m_alpha)
            workspace->m_alpha->setValueAndWarp(visible ? 1.F : 0.F);

        workspace->m_forceRendering = visible;
    };

    // Do not access g_pCompositor->m_workspaces directly: it is private in
    // current Hyprland versions. Warp only the public workspace objects we know
    // about from the overview ribbon plus the active and target workspaces.
    for (const int id : overviewWorkspaceIds())
        warpWorkspace(id, id == targetID);

    warpWorkspace(std::max(1, static_cast<int>(owner->activeWorkspaceID())), false);
    warpWorkspace(targetID, true);
}

std::vector<int> CHyprspaceWidget::overviewWorkspaceIds() const {
    std::vector<int> result;

    const auto owner = getOwner();
    if (!owner)
        return result;

    std::vector<int> occupiedWorkspaceIDs;
    for (auto& window : g_pCompositor->m_windows) {
        if (!window || !window->m_isMapped || !window->m_workspace || !window->m_workspace->m_monitor)
            continue;
        if (window->m_workspace->m_monitor->m_id != ownerID)
            continue;
        if (window->m_workspace->m_id < 1)
            continue;

        const int id = static_cast<int>(window->m_workspace->m_id);
        if (std::find(occupiedWorkspaceIDs.begin(), occupiedWorkspaceIDs.end(), id) == occupiedWorkspaceIDs.end())
            occupiedWorkspaceIDs.push_back(id);
    }

    // GNOME-like dynamic workspaces: the overview only shows the compact
    // occupied count plus one trailing empty workspace. Large stale Hyprland
    // workspace ids are ignored here; Quickshell's HyprlandService compacts
    // windows that land there from hotkeys or hyprctl commands.
    int maxWorkspaceID = occupiedWorkspaceIDs.empty() ? 1 : static_cast<int>(occupiedWorkspaceIDs.size()) + 1;
    const int activeWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    if (activeWorkspaceID <= maxWorkspaceID)
        maxWorkspaceID = std::max(maxWorkspaceID, activeWorkspaceID);
    if (centeredWorkspaceID > 0 && centeredWorkspaceID <= maxWorkspaceID)
        maxWorkspaceID = std::max(maxWorkspaceID, centeredWorkspaceID);

    if (Config::showNewWorkspace)
        maxWorkspaceID = std::max(maxWorkspaceID, static_cast<int>(occupiedWorkspaceIDs.size()) + 1);

    for (int id = 1; id <= maxWorkspaceID; ++id)
        result.push_back(id);

    return result;
}

double CHyprspaceWidget::currentWorkspaceStep() const {
    if (workspaceBoxes.size() >= 2) {
        const auto first = std::get<1>(workspaceBoxes[0]);
        const auto second = std::get<1>(workspaceBoxes[1]);
        const double step = std::abs(second.x - first.x);
        if (step > 1.0)
            return step;
    }

    const auto owner = g_pCompositor->getMonitorFromID(ownerID);
    if (owner)
        return std::max<double>(180.0, owner->m_size.x * 0.38);

    return 300.0;
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

    constexpr double WORKSPACE_SELECTION_SECONDS = 0.22;
    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - workspaceSelectionAnimationStartedAt).count();
    return std::clamp(elapsed / WORKSPACE_SELECTION_SECONDS, 0.0, 1.0);
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

    const int currentWorkspaceID = centeredWorkspaceID > 0
        ? centeredWorkspaceID
        : std::max(1, static_cast<int>(owner->activeWorkspaceID()));

    closeOwnerSpecialWorkspace();
    workspaceScrollAccumulator = 0.0;
    workspaceScrollOffset->setValueAndWarp(0);

    if (targetWorkspaceID == currentWorkspaceID) {
        centeredWorkspaceID = targetWorkspaceID;
        if (closeAfterAnimation)
            hide();
        return true;
    }

    workspaceSelectionFromID = currentWorkspaceID;
    workspaceSelectionToID = targetWorkspaceID;
    closeAfterWorkspaceSelectionAnimation = closeAfterAnimation;
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
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    centeredWorkspaceID = targetWorkspaceID;
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    workspaceHoverProgress.clear();
    lastWorkspaceHoverFrameValid = false;

    if (owner && targetWorkspaceID > 0) {
        suppressWorkspaceTransitionAnimation();
        if (owner->activeWorkspaceID() != targetWorkspaceID)
            owner->changeWorkspace(targetWorkspaceID);
        warpWorkspaceTransitionState(targetWorkspaceID);
    }

    if (shouldClose)
        hide();

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
    auto currentIt = std::find(ids.begin(), ids.end(), currentWorkspaceID);
    if (currentIt == ids.end())
        currentIt = std::lower_bound(ids.begin(), ids.end(), currentWorkspaceID);
    if (currentIt == ids.end())
        currentIt = ids.end() - 1;

    const int currentIndex = static_cast<int>(std::distance(ids.begin(), currentIt));
    const int targetIndex = std::clamp(currentIndex + (direction > 0 ? 1 : -1), 0, static_cast<int>(ids.size()) - 1);
    const int targetWorkspaceID = ids[targetIndex];
    if (targetWorkspaceID == currentWorkspaceID)
        return false;

    return startWorkspaceSelectionAnimation(targetWorkspaceID, false);
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
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    centeredWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    curYOffset->setValueAndWarp(0);

    lastWorkspaceHoverFrameValid = false;

    if (!wasActive || wasClosing) {
        overviewAnimationStarted = true;
        overviewAnimationStartedAt = std::chrono::steady_clock::now();
        workspaceHoverProgress.clear();
        notifyQuickshellOverviewState("open");
    }

    // Do not synthesize pointer motion while entering overview. Sending motion
    // to the real client below the cursor made buttons/links under the preview
    // hoverable for a moment. Real pointer events are blocked by the input hooks.

    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
}

void CHyprspaceWidget::finishHide() {
    const int visibleWorkspaceID = centeredWorkspaceID;
    active = false;
    overviewClosing = false;
    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    centeredWorkspaceID = 0;
    workspaceBoxes.clear();
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    curYOffset->setValueAndWarp(0);

    workspaceHoverProgress.clear();
    lastWorkspaceHoverFrameValid = false;
    overviewAnimationStarted = false;
    warpWorkspaceTransitionState(visibleWorkspaceID);
    restoreWorkspaceTransitionAnimation();

    // After leaving overview, restore normal pointer focus/cursor state. Do it
    // only after the exit morph finishes, otherwise the real windows below the
    // shrinking preview can receive hover/focus while the overview is visible.
    g_pInputManager->refocus();
    g_pInputManager->simulateMouseMovement();
}

void CHyprspaceWidget::hide() {
    const bool wasActive = active;
    auto owner = getOwner();
    if (!owner)
        return;

    if (!wasActive)
        return;

    if (workspaceSelectionAnimating) {
        closeAfterWorkspaceSelectionAnimation = true;
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

double CHyprspaceWidget::overviewOpenProgress() const {
    constexpr double OVERVIEW_OPEN_ANIMATION_SECONDS = 0.24;
    constexpr double OVERVIEW_CLOSE_ANIMATION_SECONDS = 0.22;

    if (overviewClosing) {
        const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - overviewClosingStartedAt).count();
        return 1.0 - std::clamp(elapsed / OVERVIEW_CLOSE_ANIMATION_SECONDS, 0.0, 1.0);
    }

    if (!overviewAnimationStarted)
        return 1.0;

    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - overviewAnimationStartedAt).count();
    return std::clamp(elapsed / OVERVIEW_OPEN_ANIMATION_SECONDS, 0.0, 1.0);
}

bool CHyprspaceWidget::isClosing() const {
    return overviewClosing;
}

void CHyprspaceWidget::updateConfig() {
    curAnimationConfig = *Config::animationTree()->getAnimationPropertyConfig("windows");
    curAnimation = *curAnimationConfig.pValues.lock();
    *curAnimationConfig.pValues.lock() = curAnimation;

    if (Config::overrideAnimSpeed > 0)
        curAnimation.internalSpeed = Config::overrideAnimSpeed;

    g_pAnimationManager->createAnimation(0.F, curYOffset, curAnimationConfig.pValues.lock(), AVARDAMAGE_ENTIRE);
    g_pAnimationManager->createAnimation(0.F, workspaceScrollOffset, curAnimationConfig.pValues.lock(), AVARDAMAGE_ENTIRE);
    curYOffset->setValueAndWarp(0);
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    workspaceSelectionAnimating = false;
    closeAfterWorkspaceSelectionAnimation = false;
    workspaceSelectionFromID = 0;
    workspaceSelectionToID = 0;
    overviewClosing = false;
    overviewAnimationStarted = active;
    overviewAnimationStartedAt = std::chrono::steady_clock::now();
}

bool CHyprspaceWidget::isActive() {
    return active;
}
