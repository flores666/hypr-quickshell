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

PHLMONITOR CHyprspaceWidget::getOwner() {
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

    const int currentWorkspaceID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    const int targetWorkspaceID = std::max(1, currentWorkspaceID + (direction > 0 ? 1 : -1));
    if (targetWorkspaceID == currentWorkspaceID)
        return false;

    closeOwnerSpecialWorkspace();

    // The overview itself should stay open while the active workspace changes.
    // The renderer always recenters around the current active workspace, so one
    // wheel notch becomes exactly one centered workspace step.
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
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    curYOffset->setValueAndWarp(0);

    lastWorkspaceHoverFrameValid = false;

    if (!wasActive)
        notifyQuickshellOverviewState("open");

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
    workspaceBoxes.clear();
    workspaceScrollOffset->setValueAndWarp(0);
    workspaceScrollAccumulator = 0.0;
    curYOffset->setValueAndWarp(0);

    workspaceHoverProgress.clear();
    lastWorkspaceHoverFrameValid = false;

    if (wasActive)
        notifyQuickshellOverviewState("close");

    // After leaving overview, restore normal pointer focus/cursor state.
    g_pInputManager->refocus();
    g_pInputManager->simulateMouseMovement();

    g_pHyprRenderer->damageMonitor(owner);
    g_pCompositor->scheduleFrameForMonitor(owner);
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
}

bool CHyprspaceWidget::isActive() {
    return active;
}
