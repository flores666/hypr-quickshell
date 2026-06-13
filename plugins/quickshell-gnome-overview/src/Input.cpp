#include <hyprland/src/desktop/view/Window.hpp>
#include <algorithm>

#include "Overview.hpp"
#include "Globals.hpp"
#include <cmath>

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
            const auto owner = getOwner();
            closeOwnerSpecialWorkspace();

            // If this is the same regular workspace that was under the special
            // workspace, only close the special/overview layers. Calling
            // changeWorkspace on it again can race with Quickshell's stale
            // activeSpecial state and reopen the special workspace.
            if (!owner || owner->activeWorkspaceID() != targetWorkspace->m_id)
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

    const double step = currentWorkspaceStep();
    const double absDelta = std::abs(delta);

    // Mouse wheel deltas are usually coarse. Move close to one workspace per
    // notch, like GNOME, instead of creeping a few pixels at a time. Touchpad
    // deltas stay smooth but use a higher multiplier than before.
    const double amount = (absDelta >= 8.0 && step > 1.0)
        ? (delta > 0.0 ? step * 0.82 : -step * 0.82)
        : delta * (axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL ? 10.0 : 8.5);

    const double next = std::clamp<double>(workspaceScrollOffset->goal() - amount, workspaceScrollMin, workspaceScrollMax);
    *workspaceScrollOffset = next;
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
