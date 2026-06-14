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
}

CHyprspaceWidget::~CHyprspaceWidget() {}

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

    closeOwnerSpecialWorkspace();

    // Move the overview selection first. This makes empty in-between
    // workspaces scrollable even when Hyprland has not created an actual
    // workspace object for that number yet. If Hyprland can switch to the
    // workspace, the workspace-change hook will keep this value in sync with
    // the real active workspace. If it cannot, the visual strip still advances
    // by exactly one slot and the next wheel notch can continue to the next
    // occupied workspace.
    centeredWorkspaceID = targetWorkspaceID;
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    owner->changeWorkspace(targetWorkspaceID);

    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
    return true;
}

void CHyprspaceWidget::show() {
    const bool wasActive = active;
    auto owner = getOwner();
    if (!owner)
        return;

    // Treat live overview as a regular-workspace mode. Close the special
    // workspace before overview becomes active, no matter whether overview was
    // opened from the dock button, the hot corner, or the single Super key.
    closeOwnerSpecialWorkspace();

    active = true;
    centeredWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    curYOffset->setValueAndWarp(0);

    lastWorkspaceHoverFrameValid = false;

    if (!wasActive) {
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

void CHyprspaceWidget::hide() {
    const bool wasActive = active;
    auto owner = getOwner();
    if (!owner)
        return;

    active = false;
    centeredWorkspaceID = 0;
    workspaceBoxes.clear();
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    curYOffset->setValueAndWarp(0);

    workspaceHoverProgress.clear();
    lastWorkspaceHoverFrameValid = false;
    overviewAnimationStarted = false;

    if (wasActive)
        notifyQuickshellOverviewState("close");

    // After leaving overview, restore normal pointer focus/cursor state.
    g_pInputManager->refocus();
    g_pInputManager->simulateMouseMovement();

    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
}

double CHyprspaceWidget::overviewOpenProgress() const {
    if (!overviewAnimationStarted)
        return 1.0;

    constexpr double OVERVIEW_OPEN_ANIMATION_SECONDS = 0.24;
    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - overviewAnimationStartedAt).count();
    return std::clamp(elapsed / OVERVIEW_OPEN_ANIMATION_SECONDS, 0.0, 1.0);
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
    overviewAnimationStarted = active;
    overviewAnimationStartedAt = std::chrono::steady_clock::now();
}

bool CHyprspaceWidget::isActive() {
    return active;
}
