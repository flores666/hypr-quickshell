#include <hyprland/src/desktop/view/Window.hpp>
#include <algorithm>

#include "Overview.hpp"
#include "Globals.hpp"
#include <cmath>

bool CHyprspaceWidget::buttonEvent(bool pressed, Vector2D coords) {
    if (!active)
        return true;

    if (isClosing() || isSelectingWorkspace())
        return false;

    if (pressed) {
        lastPressedTime = std::chrono::high_resolution_clock::now();
        return false;
    }

    const bool quickClick = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now() - lastPressedTime).count() < 250;

    int targetWorkspaceID = SPECIAL_WORKSPACE_START - 1;
    bool clickedWorkspacePreview = false;
    // workspaceBoxes are stored in render order. Iterate from back to front so
    // the hovered/zoomed workspace, which is drawn last, also wins clicks in
    // the small overlap area.
    for (auto it = workspaceBoxes.rbegin(); it != workspaceBoxes.rend(); ++it) {
        const auto id = std::get<0>(*it);
        const auto box = std::get<1>(*it);
        if (box.containsPoint(coords)) {
            targetWorkspaceID = id;
            clickedWorkspacePreview = true;
            break;
        }
    }

    const auto targetWorkspace = g_pCompositor->getWorkspaceByID(targetWorkspaceID);
    if (clickedWorkspacePreview) {
        if (targetWorkspace && targetWorkspace->m_isSpecialWorkspace) {
            getOwner()->activeSpecialWorkspaceID() == targetWorkspaceID ? getOwner()->setSpecialWorkspace(nullptr) : getOwner()->setSpecialWorkspace(targetWorkspaceID);
        } else {
            startWorkspaceSelectionAnimation(targetWorkspaceID, true);
        }
        return false;
    }

    if (quickClick)
        hide();

    return false;
}

bool CHyprspaceWidget::axisEvent(double delta, wl_pointer_axis axis, Vector2D coords) {
    if (!active)
        return true;

    if (isClosing() || isSelectingWorkspace())
        return false;

    if (delta == 0.0)
        return false;

    const double absDelta = std::abs(delta);

    // A real mouse-wheel notch should move exactly one workspace. Do not use a
    // pixel scroll offset here: changing the active workspace lets draw() keep
    // that workspace centered, which matches the GNOME overview feeling better.
    if (absDelta >= 8.0) {
        switchOverviewWorkspaceBy(delta > 0.0 ? 1 : -1);
        return false;
    }

    // Touchpads send many small axis events. Accumulate them and emit one
    // workspace switch only after a deliberate gesture threshold is crossed.
    const double multiplier = axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL ? 1.0 : 1.0;
    workspaceScrollAccumulator += delta * multiplier;

    constexpr double TOUCHPAD_WORKSPACE_STEP_THRESHOLD = 6.0;
    if (std::abs(workspaceScrollAccumulator) >= TOUCHPAD_WORKSPACE_STEP_THRESHOLD) {
        const int direction = workspaceScrollAccumulator > 0.0 ? 1 : -1;
        workspaceScrollAccumulator = 0.0;
        switchOverviewWorkspaceBy(direction);
    }

    return false;
}

bool CHyprspaceWidget::isSwiping() {
    return false;
}

bool CHyprspaceWidget::beginSwipe(IPointer::SSwipeBeginEvent e) {
    return true;
}

bool CHyprspaceWidget::updateSwipe(IPointer::SSwipeUpdateEvent e) {
    return true;
}

bool CHyprspaceWidget::endSwipe(IPointer::SSwipeEndEvent e) {
    return true;
}
