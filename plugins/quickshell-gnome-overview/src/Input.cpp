#include <hyprland/src/desktop/view/Window.hpp>

#include "Overview.hpp"
#include "Globals.hpp"

bool CHyprspaceWidget::buttonEvent(bool pressed, Vector2D coords) {
    if (!active)
        return true;

    if (pressed) {
        lastPressedTime = std::chrono::high_resolution_clock::now();
        return false;
    }

    const bool quickClick = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now() - lastPressedTime).count() < 250;

    int targetWorkspaceID = SPECIAL_WORKSPACE_START - 1;
    for (auto& w : workspaceBoxes) {
        const auto id = std::get<0>(w);
        const auto box = std::get<1>(w);
        if (box.containsPoint(coords)) {
            targetWorkspaceID = id;
            break;
        }
    }

    const auto targetWorkspace = g_pCompositor->getWorkspaceByID(targetWorkspaceID);
    if (targetWorkspace) {
        if (targetWorkspace->m_isSpecialWorkspace) {
            getOwner()->activeSpecialWorkspaceID() == targetWorkspaceID ? getOwner()->setSpecialWorkspace(nullptr) : getOwner()->setSpecialWorkspace(targetWorkspaceID);
        } else if (targetWorkspace->m_monitor) {
            g_pCompositor->getMonitorFromID(targetWorkspace->m_monitor->m_id)->changeWorkspace(targetWorkspace->m_id);
        }
        hide();
        return false;
    }

    if (quickClick)
        hide();

    return false;
}

bool CHyprspaceWidget::axisEvent(double delta, wl_pointer_axis axis, Vector2D coords) {
    if (!active)
        return true;

    const double speed = axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL ? 2.0 : 1.5;
    *workspaceScrollOffset = workspaceScrollOffset->goal() - delta * speed;
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
