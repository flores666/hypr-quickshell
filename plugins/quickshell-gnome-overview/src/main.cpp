#include <hyprland/src/plugins/PluginSystem.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/devices/IKeyboard.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/debug/log/Logger.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprutils/memory/SharedPtr.hpp>
#include <xkbcommon/xkbcommon.h>
#include <algorithm>
#include <any>
#include <chrono>
#include <cmath>
#include <functional>
#include <optional>
#include <string>
#include "Overview.hpp"
#include "Globals.hpp"

std::vector<std::shared_ptr<CHyprspaceWidget>> g_overviewWidgets;


CHyprColor Config::workspaceActiveBackground = CHyprColor(0, 0, 0, 0);
CHyprColor Config::workspaceInactiveBackground = CHyprColor(0, 0, 0, 0);

int Config::workspaceMargin = 16;
int Config::reservedArea = 110;
bool Config::showNewWorkspace = false;

bool Config::disableBlur = false;

bool Config::mainModToggle = true;
std::string Config::mainModKey = "Super_L";
bool Config::hotCorner = true;
int Config::hotCornerSize = 1;
int Config::hotCornerCooldown = 450;
int Config::hotCornerApproachDistance = 72;
int Config::hotCornerMinTravel = 18;
float Config::hotCornerMinSpeed = 0.18;

// Event listener handles (auto-unregister when destroyed)
CHyprSignalListener g_pRenderHook;
CHyprSignalListener g_pConfigReloadHook;
CHyprSignalListener g_pOpenLayerHook;
CHyprSignalListener g_pCloseLayerHook;
CHyprSignalListener g_pMouseMoveHook;
CHyprSignalListener g_pMouseButtonHook;
CHyprSignalListener g_pMouseAxisHook;
CHyprSignalListener g_pTouchDownHook;
CHyprSignalListener g_pTouchMoveHook;
CHyprSignalListener g_pTouchUpHook;
CHyprSignalListener g_pSwipeBeginHook;
CHyprSignalListener g_pSwipeUpdateHook;
CHyprSignalListener g_pSwipeEndHook;
CHyprSignalListener g_pKeyPressHook;
CHyprSignalListener g_pSwitchWorkspaceHook;
CHyprSignalListener g_pAddMonitorHook;
CHyprSignalListener g_pStartHook;

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

std::shared_ptr<CHyprspaceWidget> getWidgetForMonitor(PHLMONITORREF pMonitor) {
    for (auto& widget : g_overviewWidgets) {
        if (!widget) continue;
        if (!widget->getOwner()) continue;
        if (widget->getOwner() == pMonitor) {
            return widget;
        }
    }
    return nullptr;
}

// used to enforce the layout
void refreshWidgets() {
    for (auto& widget : g_overviewWidgets) {
        if (!widget || !widget->isActive())
            continue;

        const auto owner = widget->getOwner();
        if (!owner)
            continue;

        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
    }
}

bool g_layoutNeedsRefresh = true;

static bool g_mainModDown = false;
static bool g_mainModCancelled = false;
static xkb_keysym_t g_mainModKeysym = XKB_KEY_Super_L;
static bool g_hotCornerInside = false;
static bool g_hotCornerHasLastCoords = false;
static Vector2D g_hotCornerLastCoords;
static bool g_hotCornerApproachActive = false;
static Vector2D g_hotCornerApproachStartCoords;
static std::chrono::steady_clock::time_point g_hotCornerApproachStartTime;
static bool g_mouseButtonDown = false;
static std::chrono::steady_clock::time_point g_hotCornerLastOpen = std::chrono::steady_clock::now() - std::chrono::seconds(10);
static double g_mainModAxisAccumulator = 0.0;
static std::chrono::steady_clock::time_point g_mainModLastAxisSwitch = std::chrono::steady_clock::now() - std::chrono::milliseconds(120);
static constexpr auto MAIN_MOD_AXIS_SWITCH_MIN_INTERVAL = std::chrono::milliseconds(120);
static bool g_overviewApplicationsMode = false;
static int g_overviewApplicationsOriginWorkspaceID = 0;
static int g_pointerRefreshFrames = 0;
static std::chrono::steady_clock::time_point g_pointerRefreshUntil = std::chrono::steady_clock::now() - std::chrono::seconds(2);
static std::chrono::steady_clock::time_point g_mainModLastSafeRelease = std::chrono::steady_clock::now() - std::chrono::seconds(2);
static std::chrono::steady_clock::time_point g_mainModLastOverviewAction = std::chrono::steady_clock::now() - std::chrono::seconds(2);
static constexpr auto MAIN_MOD_DOUBLE_PRESS_INTERVAL = std::chrono::milliseconds(360);
static constexpr auto MAIN_MOD_OVERVIEW_ACTION_MIN_INTERVAL = std::chrono::milliseconds(140);

static bool isAnyOverviewActive();

static void notifyQuickshellOverviewState(const std::string& state) {
    if (g_pEventManager)
        g_pEventManager->postEvent(SHyprIPCEvent{"quickshelloverview", state});
}

static void queuePointerRefresh(int frames = 10) {
    g_pointerRefreshFrames = std::max(g_pointerRefreshFrames, frames);
    g_pointerRefreshUntil = std::max(
        g_pointerRefreshUntil,
        std::chrono::steady_clock::now() + std::chrono::milliseconds(420));
}

static void damageActiveOverviewMonitors() {
    if (!g_pHyprRenderer || !g_pCompositor)
        return;

    for (auto& widget : g_overviewWidgets) {
        if (!widget || !widget->isActive())
            continue;

        const auto owner = widget->getOwner();
        if (!owner)
            continue;

        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
    }
}

static void requestPointerRefresh(int frames = 14) {
    queuePointerRefresh(frames);
    if (g_pInputManager) {
        g_pInputManager->refocus();
        g_pInputManager->simulateMouseMovement();
    }
    damageActiveOverviewMonitors();
}

static void refreshPointerFocusIfQueued() {
    const auto now = std::chrono::steady_clock::now();
    if (g_pointerRefreshFrames <= 0 && now >= g_pointerRefreshUntil)
        return;

    if (g_pointerRefreshFrames > 0)
        --g_pointerRefreshFrames;

    if (g_pInputManager) {
        g_pInputManager->refocus();
        g_pInputManager->simulateMouseMovement();
    }

    if (now < g_pointerRefreshUntil)
        refreshWidgets();
}

static int activeWorkspaceIDForMonitor(PHLMONITORREF monitor) {
    if (!monitor)
        return 0;

    return std::max(1, static_cast<int>(monitor->activeWorkspaceID()));
}

static int activeWorkspaceIDFromCursor() {
    return activeWorkspaceIDForMonitor(g_pCompositor->getMonitorFromCursor());
}

static int applicationsReturnWorkspaceID() {
    return g_overviewApplicationsOriginWorkspaceID > 0
        ? g_overviewApplicationsOriginWorkspaceID
        : activeWorkspaceIDFromCursor();
}

static void rememberApplicationsOriginWorkspace(PHLMONITORREF monitor) {
    if (g_overviewApplicationsOriginWorkspaceID <= 0)
        g_overviewApplicationsOriginWorkspaceID = activeWorkspaceIDForMonitor(monitor);
}

static void closeWidgetForCurrentOverviewMode(const std::shared_ptr<CHyprspaceWidget>& widget) {
    if (!widget || !widget->isActive())
        return;

    if (g_overviewApplicationsMode)
        widget->hideKeepingWorkspace(applicationsReturnWorkspaceID());
    else
        widget->hide();
}

static void resetApplicationsOverviewMode() {
    g_overviewApplicationsMode = false;
    g_overviewApplicationsOriginWorkspaceID = 0;
}

static void showWorkspaceOverviewFromApplications(const std::shared_ptr<CHyprspaceWidget>& widget) {
    if (!widget || !widget->isActive())
        return;

    widget->startApplicationsReturnToOverview();
}

std::function<void()> overviewAnimatedHideFinishedCallback = []() {
    resetApplicationsOverviewMode();
};

std::function<void()> applicationsReturnToOverviewFinishedCallback = []() {
    resetApplicationsOverviewMode();
    notifyQuickshellOverviewState("open");
    requestPointerRefresh();
};

static void resetApplicationsModeAfterCloseIfNeeded(bool wasApplicationsMode) {
    if (!wasApplicationsMode)
        resetApplicationsOverviewMode();
}

// for restoring dragged window's alpha value
float g_oAlpha = -1;


static bool isAnyOverviewActive() {
    for (auto& widget : g_overviewWidgets) {
        if (widget && widget->isActive())
            return true;
    }
    return false;
}

static std::shared_ptr<CHyprspaceWidget> getActiveWidgetForMonitor(PHLMONITORREF monitor) {
    const auto widget = getWidgetForMonitor(monitor);
    if (widget && widget->isActive())
        return widget;
    return nullptr;
}

static int workspaceNumberFromKeysym(xkb_keysym_t keysym) {
    if (keysym >= XKB_KEY_1 && keysym <= XKB_KEY_9)
        return static_cast<int>(keysym - XKB_KEY_0);
    if (keysym == XKB_KEY_0)
        return 10;

    if (keysym >= XKB_KEY_KP_1 && keysym <= XKB_KEY_KP_9)
        return static_cast<int>(keysym - XKB_KEY_KP_0);
    if (keysym == XKB_KEY_KP_0)
        return 10;

    return 0;
}

static int parseWorkspaceIDArg(const std::string& arg) {
    try {
        size_t idx = 0;
        const int value = std::stoi(arg, &idx);
        if (value > 0)
            return value;
    } catch (...) {
    }
    return 0;
}

static bool isFullscreenWorkspaceActive(PHLMONITORREF monitor) {
    if (!monitor || !monitor->m_activeWorkspace)
        return false;

    const auto activeWorkspace = monitor->m_activeWorkspace;
    for (auto& window : g_pCompositor->m_windows) {
        if (!window)
            continue;
        if (!window->m_isMapped)
            continue;
        if (window->m_workspace != activeWorkspace)
            continue;
        if (window->isEffectiveInternalFSMode(FSMODE_FULLSCREEN))
            return true;
    }

    return false;
}

static bool isQuickshellLayerNamespace(const std::string& ns) {
    return ns.starts_with("quickshell") || ns.starts_with("quickshell:");
}

static bool isScreenshotSelectorKeysym(xkb_keysym_t keysym) {
    // Let the compositor handle screenshot binds while overview is visible.
    // Without this exception the generic overview key guard below consumes
    // Print, so Hyprland never starts commands such as `grim -g "$(slurp)"`.
    return keysym == XKB_KEY_Print || keysym == XKB_KEY_Sys_Req;
}

static bool isMonitorSizedOverlayBox(const CBox& box, PHLMONITORREF monitor) {
    if (!monitor || !(box.w > 1.0 && box.h > 1.0))
        return false;

    const double monitorW = std::max<double>(1.0, monitor->m_size.x);
    const double monitorH = std::max<double>(1.0, monitor->m_size.y);
    return box.w >= monitorW * 0.92 && box.h >= monitorH * 0.92;
}

static bool isExternalSelectorOverlayLayer(size_t layerIndex, bool quickshellLayer) {
    // Region screenshot tools such as slurp are external layer-shell clients.
    // They usually map a monitor-sized top/overlay layer and need pointer input
    // while the overview is open. Quickshell's own fullscreen helper layers stay
    // excluded unless they are explicitly whitelisted elsewhere.
    return !quickshellLayer && layerIndex >= 2;
}

static bool layerBoxShouldReceiveOverviewInput(const CBox& box, PHLMONITORREF monitor, const Vector2D& coords, bool allowMonitorSizedOverlay) {
    if (!box.containsPoint(coords))
        return false;

    // Some Quickshell helper layers are fullscreen transparent overlays. They
    // must not make the overview pass pointer events through, otherwise the real
    // client below the overview can still receive hover and clicks.
    return allowMonitorSizedOverlay || !isMonitorSizedOverlayBox(box, monitor);
}

static bool isApplicationsOverviewInputRegion(PHLMONITORREF monitor, const Vector2D& coords) {
    if (!monitor || !g_overviewApplicationsMode)
        return false;

    // Keep this in sync with ApplicationsOverview.qml input margins. The
    // applications layer is visually fullscreen, but only the launcher content
    // area should receive input. Topbar and AppDock must stay interactive, and
    // clicks outside this region must not leak to windows below the overview.
    constexpr double TOP_INPUT_MARGIN = 56.0;
    constexpr double BOTTOM_INPUT_MARGIN = 116.0;
    const CBox inputRegion = {
        monitor->m_position.x,
        monitor->m_position.y + TOP_INPUT_MARGIN,
        monitor->m_size.x,
        std::max(0.0, monitor->m_size.y - TOP_INPUT_MARGIN - BOTTOM_INPUT_MARGIN)
    };

    return inputRegion.containsPoint(coords);
}

static bool isCoordsOverInteractiveLayer(PHLMONITORREF monitor, const Vector2D& coords) {
    if (!monitor)
        return false;

    // Let real layer surfaces such as the Quickshell topbar, AppDock and their
    // PopupWindow/modal surfaces receive normal pointer events while overview is
    // open. Background layers are skipped unless they are explicitly Quickshell
    // surfaces, otherwise the desktop/wallpaper could receive input.
    for (size_t layerIndex = 0; layerIndex < 4; ++layerIndex) {
        for (auto& weakLayer : monitor->m_layerSurfaceLayers[layerIndex]) {
            const auto layer = weakLayer.lock();
            if (!layer)
                continue;
            if (!layer->m_mapped || layer->m_readyToDelete)
                continue;

            const bool quickshellLayer = isQuickshellLayerNamespace(layer->m_namespace);
            if (layerIndex == 0 && !quickshellLayer)
                continue;
            if (g_overviewApplicationsMode && layer->m_namespace == "quickshell:applications")
                continue;

            const bool applicationsInputLayer = g_overviewApplicationsMode && layer->m_namespace == "quickshell:applications-input";
            const bool externalSelectorOverlayLayer = isExternalSelectorOverlayLayer(layerIndex, quickshellLayer);
            const bool allowMonitorSizedOverlay = externalSelectorOverlayLayer ||
                                                  (applicationsInputLayer && isApplicationsOverviewInputRegion(monitor, coords));

            const CBox realBox = {layer->m_realPosition->value(), layer->m_realSize->value()};
            const auto logicalBox = layer->logicalBox();
            const auto surfaceBox = layer->surfaceLogicalBox();
            if (layerBoxShouldReceiveOverviewInput(realBox, monitor, coords, allowMonitorSizedOverlay) ||
                (logicalBox.has_value() && layerBoxShouldReceiveOverviewInput(*logicalBox, monitor, coords, allowMonitorSizedOverlay)) ||
                (surfaceBox.has_value() && layerBoxShouldReceiveOverviewInput(*surfaceBox, monitor, coords, allowMonitorSizedOverlay)))
                return true;

            // Qt/Wayland popups can extend outside the base layer-surface box.
            // Do not pass the whole monitor just because a popup tree exists:
            // that lets real windows underneath live overview receive hover and
            // clicks. Base layer boxes above are still allowed, so topbar/AppDock
            // themselves remain interactive.
        }
    }

    return false;
}

static bool shouldPassPointerToRealLayer(PHLMONITORREF monitor) {
    return isCoordsOverInteractiveLayer(monitor, g_pInputManager->getMouseCoordsInternal());
}

static bool shouldPassCoordsToRealLayer(PHLMONITORREF monitor, const Vector2D& coords) {
    return isCoordsOverInteractiveLayer(monitor, coords);
}

static void toggleOverviewForCurrentMonitor() {
    const auto currentMonitor = g_pCompositor->getMonitorFromCursor();
    const auto widget = getWidgetForMonitor(currentMonitor);
    if (!widget)
        return;

    if (widget->isActive()) {
        if (g_overviewApplicationsMode) {
            showWorkspaceOverviewFromApplications(widget);
            return;
        }

        const bool wasApplicationsMode = g_overviewApplicationsMode;
        closeWidgetForCurrentOverviewMode(widget);
        resetApplicationsModeAfterCloseIfNeeded(wasApplicationsMode);
    } else {
        resetApplicationsOverviewMode();
        widget->show();
        queuePointerRefresh();
    }
}

static void openOverviewForMonitor(PHLMONITORREF monitor) {
    const auto widget = getWidgetForMonitor(monitor);
    if (!widget || widget->isActive())
        return;

    resetApplicationsOverviewMode();
    widget->show();
    queuePointerRefresh();
}

static bool isPointInHotCorner(PHLMONITORREF monitor, const Vector2D& coords) {
    if (!monitor || Config::hotCornerSize <= 0)
        return false;

    const auto size = static_cast<double>(Config::hotCornerSize);
    const auto left = monitor->m_position.x;
    const auto top = monitor->m_position.y;

    return coords.x >= left && coords.x < left + size &&
           coords.y >= top && coords.y < top + size;
}

static void maybeOpenHotCorner() {
    const auto monitor = g_pCompositor->getMonitorFromCursor();
    if (!monitor)
        return;

    const auto now = std::chrono::steady_clock::now();
    const auto coords = g_pInputManager->getMouseCoordsInternal();
    const bool inside = isPointInHotCorner(monitor, coords);

    if (!g_hotCornerHasLastCoords) {
        g_hotCornerHasLastCoords = true;
        g_hotCornerLastCoords = coords;
        g_hotCornerInside = inside;
        return;
    }

    const auto previous = g_hotCornerLastCoords;
    const bool wasInside = isPointInHotCorner(monitor, previous);
    g_hotCornerLastCoords = coords;

    const double left = monitor->m_position.x;
    const double top = monitor->m_position.y;
    const double approachDistance = static_cast<double>(std::max(1, Config::hotCornerApproachDistance));
    const bool inApproachZone = coords.x >= left && coords.x < left + approachDistance &&
                                coords.y >= top && coords.y < top + approachDistance;

    if (!inside) {
        g_hotCornerInside = false;

        if (inApproachZone) {
            // Start measuring only when the pointer enters the small top-left approach zone.
            // This makes the hot corner react to a real push into the corner, not to a slow
            // accidental hover over the 1px activation point.
            if (!g_hotCornerApproachActive) {
                g_hotCornerApproachActive = true;
                g_hotCornerApproachStartCoords = coords;
                g_hotCornerApproachStartTime = now;
            }
        } else {
            g_hotCornerApproachActive = false;
        }
        return;
    }

    const bool enteredCorner = !wasInside;
    const bool movedTowardCorner = coords.x < previous.x || coords.y < previous.y;

    if (!enteredCorner || !movedTowardCorner || g_hotCornerInside)
        return;

    if (!Config::hotCorner || isAnyOverviewActive() || g_mouseButtonDown || g_mainModDown)
        return;

    // Match GNOME's safer hot-corner behavior: do not open overview over
    // fullscreen video/game workspaces from an accidental corner hit.
    if (isFullscreenWorkspaceActive(monitor))
        return;

    if (!g_hotCornerApproachActive)
        return;

    const double dx = g_hotCornerApproachStartCoords.x - coords.x;
    const double dy = g_hotCornerApproachStartCoords.y - coords.y;
    const double travel = std::sqrt(dx * dx + dy * dy);
    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - g_hotCornerApproachStartTime).count();
    const double speed = elapsedMs > 0 ? travel / static_cast<double>(elapsedMs) : travel;

    const bool enoughTravel = travel >= static_cast<double>(std::max(1, Config::hotCornerMinTravel));
    const bool enoughSpeed = speed >= static_cast<double>(Config::hotCornerMinSpeed);

    g_hotCornerApproachActive = false;

    if (!enoughTravel || !enoughSpeed)
        return;

    const auto cooldownMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - g_hotCornerLastOpen).count();
    if (cooldownMs < Config::hotCornerCooldown)
        return;

    g_hotCornerInside = true;
    g_hotCornerLastOpen = now;
    openOverviewForMonitor(monitor);
}

static void cancelMainModToggleGesture() {
    if (g_mainModDown)
        g_mainModCancelled = true;
}

static bool isConfiguredMainMod(xkb_keysym_t keysym) {
    if (keysym == g_mainModKeysym)
        return true;

    // Keep the default robust across keyboards that report the right Super key
    // or Meta instead of Super. This is only used when the config keeps the
    // default Super_L mainMod key.
    if (g_mainModKeysym == XKB_KEY_Super_L || g_mainModKeysym == XKB_KEY_Super_R) {
        return keysym == XKB_KEY_Super_L || keysym == XKB_KEY_Super_R ||
               keysym == XKB_KEY_Meta_L || keysym == XKB_KEY_Meta_R;
    }

    return false;
}

void onRender(eRenderStage renderStage) {
    if (renderStage == eRenderStage::RENDER_PRE) {
        refreshPointerFocusIfQueued();

        if (g_layoutNeedsRefresh) {
            refreshWidgets();
            g_layoutNeedsRefresh = false;
        }
        return;
    }

    if (renderStage != eRenderStage::RENDER_POST_WINDOWS)
        return;

    const auto widget = getWidgetForMonitor(g_pHyprRenderer->m_renderData.pMonitor);
    if (widget && widget->getOwner() && widget->isActive()) {
        if (g_overviewApplicationsMode)
            widget->drawApplicationsBackground();
        else
            widget->draw();
    }
}

// event hook, currently this is only here to re-hide top layer panels on workspace change
void onWorkspaceChange(PHLWORKSPACE pWorkspace) {

    if (!pWorkspace) return;

    auto widget = getWidgetForMonitor(g_pCompositor->getMonitorFromID(pWorkspace->m_monitor->m_id));
    if (widget != nullptr && widget->isActive()) {
        if (widget->isApplyingWorkspaceActivation())
            return;

        if (g_overviewApplicationsMode) {
            widget->hideKeepingWorkspace(static_cast<int>(pWorkspace->m_id));
            return;
        }

        // If a workspace switch comes from outside the overview while it is
        // open (for example a Hyprland bind that was not cancelled), do not
        // hard-reset the strip. Animate the overview ribbon to the new target
        // instead, so every workspace change has the same GNOME-like motion.
        widget->syncExternalWorkspaceSwitch(static_cast<int>(pWorkspace->m_id));
    }
}

// GNOME-like hot corner: pushing the pointer into the top-left pixel opens overview.
// It never toggles/closes overview, so it is safe to use together with the dock button and mainMod toggle.
void onMouseMove(const Vector2D&, SCallbackInfo& info) {
    // Pointer motion alone should not cancel the mainMod gesture. Hyprland can
    // emit synthetic motion during focus/cursor refresh, especially right after
    // overview opens or closes. Cancelling on move made quick repeated Super
    // presses feel delayed or ignored.
    const auto pMonitor = g_pCompositor->getMonitorFromCursor();
    const auto widget = getWidgetForMonitor(pMonitor);
    if (widget && widget->isActive()) {
        if (shouldPassPointerToRealLayer(pMonitor))
            return;

        // When overview is visible, pointer motion must not be forwarded to
        // the real desktop below it. Otherwise clients on the original
        // workspace can still receive drag motion and start selection boxes,
        // which breaks the illusion that overview is an independent surface.
        info.cancelled = true;
        return;
    }

    maybeOpenHotCorner();
}

// event hook for click and drag interaction
void onMouseButton(const IPointer::SButtonEvent& event, SCallbackInfo& info) {
    cancelMainModToggleGesture();
    if (event.state == WL_POINTER_BUTTON_STATE_PRESSED)
        g_mouseButtonDown = true;
    else if (event.state == WL_POINTER_BUTTON_STATE_RELEASED)
        g_mouseButtonDown = false;

    const SP<IPointer> pointer = g_pSeatManager->m_mouse.lock();
    if (!pointer)
        return;

    const auto pressed = event.state == WL_POINTER_BUTTON_STATE_PRESSED;
    const auto pMonitor = g_pCompositor->getMonitorFromCursor();
    if (pMonitor) {
        const auto widget = getWidgetForMonitor(pMonitor);
        if (widget && widget->isActive()) {
            if (shouldPassPointerToRealLayer(pMonitor))
                return;

            if (event.button == BTN_LEFT)
                info.cancelled = !widget->buttonEvent(pressed, g_pInputManager->getMouseCoordsInternal());
            else
                // Block non-left buttons too while overview is open, so
                // right/middle clicks do not pass through to the desktop.
                info.cancelled = true;
        }
    }

}

// event hook for scrolling through panel and workspaces
void onMouseAxis(const IPointer::SAxisEvent& event, SCallbackInfo& info) {
    cancelMainModToggleGesture();

    const auto pMonitor = g_pCompositor->getMonitorFromCursor();
    if (pMonitor) {
        const auto widget = getWidgetForMonitor(pMonitor);
        if (widget) {
            if (widget->isActive()) {
                if (shouldPassPointerToRealLayer(pMonitor))
                    return;

                info.cancelled = !widget->axisEvent(event.delta, event.axis, g_pInputManager->getMouseCoordsInternal());
                return;
            }

            if (g_mainModDown) {
                info.cancelled = true;

                if (event.delta == 0.0)
                    return;

                const auto now = std::chrono::steady_clock::now();
                if (now - g_mainModLastAxisSwitch < MAIN_MOD_AXIS_SWITCH_MIN_INTERVAL)
                    return;

                const double absDelta = std::abs(event.delta);
                if (absDelta >= 8.0) {
                    widget->activateWorkspaceBy(event.delta > 0.0 ? 1 : -1);
                    g_mainModLastAxisSwitch = now;
                    g_mainModAxisAccumulator = 0.0;
                    return;
                }

                g_mainModAxisAccumulator += event.delta;
                constexpr double MAIN_MOD_AXIS_STEP_THRESHOLD = 6.0;
                if (std::abs(g_mainModAxisAccumulator) >= MAIN_MOD_AXIS_STEP_THRESHOLD) {
                    const int direction = g_mainModAxisAccumulator > 0.0 ? 1 : -1;
                    g_mainModAxisAccumulator = 0.0;
                    widget->activateWorkspaceBy(direction);
                    g_mainModLastAxisSwitch = now;
                }
            }
        }
    }

}

// event hook for swipe
void onSwipeBegin(const IPointer::SSwipeBeginEvent& event, SCallbackInfo& info) {
    cancelMainModToggleGesture();

    if (isAnyOverviewActive()) {
        // While overview is visible, native Hyprland workspace-swipe gestures
        // must not reach the compositor. The overview has its own wheel/touchpad
        // navigation and its own morph animation, so the compositor swipe would
        // appear as a second animation underneath it.
        info.cancelled = true;
    }
}

// event hook for update swipe, most of the swiping mechanics are here
void onSwipeUpdate(const IPointer::SSwipeUpdateEvent& event, SCallbackInfo& info) {
    if (isAnyOverviewActive())
        info.cancelled = true;
}

// event hook for end swipe
void onSwipeEnd(const IPointer::SSwipeEndEvent& event, SCallbackInfo& info) {
    if (isAnyOverviewActive())
        info.cancelled = true;
}

static bool startApplicationsFromActiveOverview(const std::string& initialQuery = "") {
    if (g_overviewApplicationsMode)
        return false;

    const auto widget = getActiveWidgetForMonitor(g_pCompositor->getMonitorFromCursor());
    if (!widget || widget->isClosing())
        return false;

    g_overviewApplicationsMode = true;
    g_overviewApplicationsOriginWorkspaceID = activeWorkspaceIDFromCursor();
    widget->startApplicationsTransitionFromOverview();
    notifyQuickshellOverviewState(initialQuery.empty() ? "applications-from-overview" : "applications:" + initialQuery);
    queuePointerRefresh();
    return true;
}

static bool shouldBlockMainModActionDuringAnimation(const std::shared_ptr<CHyprspaceWidget>& widget,
                                                    bool allowImmediateApplicationsPromotion) {
    if (!widget || !widget->isAnimating())
        return false;

    if (allowImmediateApplicationsPromotion && !widget->isClosing())
        return false;

    requestPointerRefresh(6);
    return true;
}

static bool consumeMainModOverviewActionIfBusy(std::chrono::steady_clock::time_point now) {
    if (now - g_mainModLastOverviewAction < MAIN_MOD_OVERVIEW_ACTION_MIN_INTERVAL)
        return true;

    g_mainModLastOverviewAction = now;
    return false;
}

// Close overview with configurable key and implement safe GNOME-like mainMod toggle.
void onKeyPress(const IKeyboard::SKeyEvent& event, SCallbackInfo& info) {
    const SP<IKeyboard> keyboard = g_pSeatManager->m_keyboard.lock();
    if (!keyboard || !keyboard->m_xkbSymState)
        return;

    const auto keycode = event.keycode + 8; // Because to xkbcommon it's +8 from libinput
    const xkb_keysym_t keysym = xkb_state_key_get_one_sym(keyboard->m_xkbSymState, keycode);
    const bool pressed = event.state == WL_KEYBOARD_KEY_STATE_PRESSED;
    const bool released = event.state == WL_KEYBOARD_KEY_STATE_RELEASED;

    if (isAnyOverviewActive() && isScreenshotSelectorKeysym(keysym)) {
        if (pressed && g_mainModDown)
            g_mainModCancelled = true;
        return;
    }

    if (pressed) {
        if (isAnyOverviewActive() && !g_overviewApplicationsMode && !g_mainModDown) {
            char searchText[32] = {};
            xkb_keysym_to_utf8(keysym, searchText, sizeof(searchText));
            const std::string initialQuery = searchText;
            if (!initialQuery.empty() && static_cast<unsigned char>(initialQuery[0]) >= 0x20) {
                if (startApplicationsFromActiveOverview(initialQuery)) {
                    info.cancelled = true;
                    return;
                }
            }
        }

        const int shortcutWorkspaceID = workspaceNumberFromKeysym(keysym);
        if (shortcutWorkspaceID > 0 && g_mainModDown) {
            const auto widget = getActiveWidgetForMonitor(g_pCompositor->getMonitorFromCursor());
            if (widget && widget->isAnimating()) {
                g_mainModCancelled = true;
                info.cancelled = true;
                requestPointerRefresh(6);
                return;
            }
            if (widget && g_overviewApplicationsMode) {
                widget->hideKeepingWorkspace(shortcutWorkspaceID);
                g_mainModCancelled = true;
                info.cancelled = true;
                return;
            }
            if (widget && widget->activateWorkspaceInOverview(shortcutWorkspaceID)) {
                g_mainModCancelled = true;
                info.cancelled = true;
                return;
            }
        }
    }

    // Main modifier handling must be done inside the plugin, not with Hyprland bindr.
    // bindr on $mainMod fires even after combinations such as $mainMod+Space layout switch.
    // Here we toggle only if the configured mainMod was pressed and released alone.
    if (Config::mainModToggle && isConfiguredMainMod(keysym)) {
        if (pressed) {
            if (!g_mainModDown) {
                g_mainModDown = true;
                g_mainModAxisAccumulator = 0.0;
                const uint32_t mods = keyboard->getModifiers();
                const uint32_t unsafeOtherMods = mods & (HL_MODIFIER_SHIFT | HL_MODIFIER_CTRL | HL_MODIFIER_ALT | HL_MODIFIER_MOD2 | HL_MODIFIER_MOD3 | HL_MODIFIER_MOD5);
                g_mainModCancelled = unsafeOtherMods != 0;
            }
            if (isAnyOverviewActive())
                info.cancelled = true;
            return;
        }

        if (released && g_mainModDown) {
            const bool safeSinglePress = !g_mainModCancelled;

            g_mainModDown = false;
            g_mainModCancelled = false;
            g_mainModAxisAccumulator = 0.0;

            if (safeSinglePress) {
                const auto now = std::chrono::steady_clock::now();
                const auto widget = getActiveWidgetForMonitor(g_pCompositor->getMonitorFromCursor());
                const bool overviewActive = isAnyOverviewActive();
                const bool doubleMainModPress = now - g_mainModLastSafeRelease <= MAIN_MOD_DOUBLE_PRESS_INTERVAL;
                const bool promoteToApplications = doubleMainModPress && overviewActive && !g_overviewApplicationsMode;

                if (!promoteToApplications && consumeMainModOverviewActionIfBusy(now)) {
                    g_mainModLastSafeRelease = now;
                    info.cancelled = true;
                    return;
                }

                if (shouldBlockMainModActionDuringAnimation(widget, promoteToApplications)) {
                    g_mainModLastSafeRelease = now;
                    info.cancelled = true;
                    return;
                }

                if (promoteToApplications) {
                    startApplicationsFromActiveOverview();
                } else if (g_overviewApplicationsMode && overviewActive) {
                    if (widget)
                        showWorkspaceOverviewFromApplications(widget);
                } else {
                    toggleOverviewForCurrentMonitor();
                }

                g_mainModLastSafeRelease = now;
                info.cancelled = true;
            } else if (isAnyOverviewActive()) {
                info.cancelled = true;
            }
            return;
        }
    } else if (pressed && g_mainModDown) {
        // Any other key while mainMod is held means it was a shortcut or layout switch.
        // Do not open overview on mainMod release.
        g_mainModCancelled = true;
    }

    auto* pExitKeyCfg = HyprlandAPI::getConfigValue(pHandle, "plugin:overview:exitKey");
    if (pExitKeyCfg) {
        const Hyprlang::STRING cfgExitKey = std::any_cast<Hyprlang::STRING>(pExitKeyCfg->getValue());
        if (cfgExitKey && cfgExitKey[0] != '\0') {
            const xkb_keysym_t cfgExitKeysym = xkb_keysym_from_name(cfgExitKey, XKB_KEYSYM_CASE_INSENSITIVE);

            if (pressed && keysym == cfgExitKeysym) {
                bool overviewActive = false;
                const bool wasApplicationsMode = g_overviewApplicationsMode;
                for (auto& widget : g_overviewWidgets) {
                    if (widget != nullptr && widget->isActive()) {
                        closeWidgetForCurrentOverviewMode(widget);
                        overviewActive = true;
                    }
                }
                if (overviewActive)
                    resetApplicationsModeAfterCloseIfNeeded(wasApplicationsMode);
                if (overviewActive)
                    info.cancelled = true;
                return;
            }
        }
    }

    // While live overview is visible, do not let text input fall through to the
    // focused client underneath. This still keeps the explicit overview shortcuts
    // above working, but normal typing no longer edits the hidden application.
    if (isAnyOverviewActive() && !g_overviewApplicationsMode && !g_mainModDown)
        info.cancelled = true;
}

PHLMONITOR g_pTouchedMonitor;

void onTouchDown(const ITouch::SDownEvent& event, SCallbackInfo& info) {
    cancelMainModToggleGesture();
    if (!event.device)
        return;

    auto targetMonitor = g_pCompositor->getMonitorFromName(!event.device->m_boundOutput.empty() ? event.device->m_boundOutput : "");
    targetMonitor = targetMonitor ? targetMonitor : g_pCompositor->getMonitorFromCursor();

    const auto widget = getWidgetForMonitor(targetMonitor);
    if (widget != nullptr && targetMonitor != nullptr) {
        if (widget->isActive()) {
            Vector2D pos = targetMonitor->m_position + event.pos * targetMonitor->m_size;
            if (shouldPassCoordsToRealLayer(targetMonitor, pos))
                return;

            info.cancelled = !widget->buttonEvent(true, pos);
            if (info.cancelled) {
                g_pTouchedMonitor = targetMonitor;
                g_pCompositor->warpCursorTo(pos);
                g_pInputManager->refocus();
            }
        }
    }
}

void onTouchMove(const ITouch::SMotionEvent& event, SCallbackInfo& info) {
    if (g_pTouchedMonitor == nullptr) return;

    g_pCompositor->warpCursorTo(g_pTouchedMonitor->m_position + g_pTouchedMonitor->m_size * event.pos);
    g_pInputManager->simulateMouseMovement();
    info.cancelled = true;
}

void onTouchUp(const ITouch::SUpEvent& event, SCallbackInfo& info) {
    const auto widget = getWidgetForMonitor(g_pTouchedMonitor);
    if (widget != nullptr && g_pTouchedMonitor != nullptr)
        if (widget->isActive())
            info.cancelled = !widget->buttonEvent(false, g_pInputManager->getMouseCoordsInternal());

    g_pTouchedMonitor = nullptr;
}

static SDispatchResult dispatchToggleOverview(std::string arg) {
    auto currentMonitor = g_pCompositor->getMonitorFromCursor();
    auto widget = getWidgetForMonitor(currentMonitor);
    if (widget) {
        if (arg.contains("all")) {
            if (widget->isActive()) {
                for (auto& widget : g_overviewWidgets) {
                    if (widget != nullptr)
                        if (widget->isActive())
                            closeWidgetForCurrentOverviewMode(widget);
                }
                resetApplicationsModeAfterCloseIfNeeded(g_overviewApplicationsMode);
            }
            else {
                resetApplicationsOverviewMode();
                for (auto& widget : g_overviewWidgets) {
                    if (widget != nullptr)
                        if (!widget->isActive())
                            widget->show();
                }
                queuePointerRefresh();
            }
        }
        else if (widget->isActive()) {
            const bool wasApplicationsMode = g_overviewApplicationsMode;
            closeWidgetForCurrentOverviewMode(widget);
            resetApplicationsModeAfterCloseIfNeeded(wasApplicationsMode);
        } else {
            resetApplicationsOverviewMode();
            widget->show();
            queuePointerRefresh();
        }
    }
    return SDispatchResult{};
}

static SDispatchResult dispatchOpenOverview(std::string arg) {
    resetApplicationsOverviewMode();
    bool opened = false;

    if (arg.contains("all")) {
        for (auto& widget : g_overviewWidgets) {
            if (!widget)
                continue;
            if (!widget->isActive()) {
                widget->show();
                opened = true;
            } else {
                opened = true;
            }
        }
    }
    else {
        auto currentMonitor = g_pCompositor->getMonitorFromCursor();
        auto widget = getWidgetForMonitor(currentMonitor);
        if (widget) {
            if (!widget->isActive()) {
                widget->show();
                opened = true;
            } else {
                opened = true;
            }
        }
    }
    if (opened) {
        notifyQuickshellOverviewState("open");
        queuePointerRefresh();
    }
    return SDispatchResult{};
}

static SDispatchResult dispatchApplicationsOverview(std::string arg) {
    auto currentMonitorForGate = g_pCompositor->getMonitorFromCursor();
    auto widgetForGate = getWidgetForMonitor(currentMonitorForGate);
    const bool canPromoteActiveOverview = widgetForGate && widgetForGate->isActive() && !widgetForGate->isClosing() && !g_overviewApplicationsMode;
    if (widgetForGate && widgetForGate->isAnimating() && !canPromoteActiveOverview) {
        requestPointerRefresh(6);
        return SDispatchResult{};
    }

    if (g_overviewApplicationsMode && isAnyOverviewActive()) {
        const int returnWorkspaceID = applicationsReturnWorkspaceID();
        if (arg.contains("all")) {
            for (auto& widget : g_overviewWidgets) {
                if (widget && widget->isActive())
                    widget->hideKeepingWorkspace(returnWorkspaceID);
            }
        } else {
            auto currentMonitor = g_pCompositor->getMonitorFromCursor();
            auto widget = getWidgetForMonitor(currentMonitor);
            if (widget && widget->isActive())
                widget->hideKeepingWorkspace(returnWorkspaceID);
        }
        return SDispatchResult{};
    }

    g_overviewApplicationsMode = true;
    g_overviewApplicationsOriginWorkspaceID = parseWorkspaceIDArg(arg);
    bool fromActiveOverview = false;

    if (arg.contains("all")) {
        for (auto& widget : g_overviewWidgets) {
            if (!widget)
                continue;
            if (widget->isActive()) {
                fromActiveOverview = true;
                widget->startApplicationsTransitionFromOverview();
            } else {
                widget->show();
            }
            rememberApplicationsOriginWorkspace(widget->getOwner());
        }
    } else {
        auto currentMonitor = g_pCompositor->getMonitorFromCursor();
        auto widget = getWidgetForMonitor(currentMonitor);
        if (widget) {
            if (widget->isActive()) {
                fromActiveOverview = true;
                widget->startApplicationsTransitionFromOverview();
            } else {
                widget->show();
            }
            rememberApplicationsOriginWorkspace(widget->getOwner());
        }
    }

    if (g_overviewApplicationsOriginWorkspaceID <= 0)
        g_overviewApplicationsOriginWorkspaceID = activeWorkspaceIDFromCursor();

    notifyQuickshellOverviewState(fromActiveOverview ? "applications-from-overview" : "applications");
    queuePointerRefresh();
    return SDispatchResult{};
}

static SDispatchResult dispatchCloseOverview(std::string arg) {
    const bool wasApplicationsMode = g_overviewApplicationsMode;
    bool closedAny = false;
    if (arg.contains("all")) {
        for (auto& widget : g_overviewWidgets) {
            if (widget && widget->isActive()) {
                closeWidgetForCurrentOverviewMode(widget);
                closedAny = true;
            }
        }
    }
    else {
        auto currentMonitor = g_pCompositor->getMonitorFromCursor();
        auto widget = getWidgetForMonitor(currentMonitor);
        if (widget)
            if (widget->isActive()) {
                closeWidgetForCurrentOverviewMode(widget);
                closedAny = true;
            }
    }
    if (closedAny)
        resetApplicationsModeAfterCloseIfNeeded(wasApplicationsMode);
    else
        resetApplicationsOverviewMode();
    return SDispatchResult{};
}

static SDispatchResult dispatchSelectOverview(std::string arg) {
    const int workspaceID = parseWorkspaceIDArg(arg);
    if (workspaceID <= 0)
        return SDispatchResult{};

    auto currentMonitor = g_pCompositor->getMonitorFromCursor();
    auto widget = getWidgetForMonitor(currentMonitor);
    if (widget && widget->isActive()) {
        if (g_overviewApplicationsMode)
            widget->hideKeepingWorkspace(workspaceID);
        else
            widget->selectWorkspaceInOverview(workspaceID);
    }

    return SDispatchResult{};
}

static SDispatchResult dispatchNextOverview(std::string) {
    auto currentMonitor = g_pCompositor->getMonitorFromCursor();
    auto widget = getWidgetForMonitor(currentMonitor);
    if (widget && widget->isActive())
        widget->selectWorkspaceInOverviewBy(1);

    return SDispatchResult{};
}

static SDispatchResult dispatchPrevOverview(std::string) {
    auto currentMonitor = g_pCompositor->getMonitorFromCursor();
    auto widget = getWidgetForMonitor(currentMonitor);
    if (widget && widget->isActive())
        widget->selectWorkspaceInOverviewBy(-1);

    return SDispatchResult{};
}

static SDispatchResult dispatchRefreshPointer(std::string) {
    requestPointerRefresh(10);
    return SDispatchResult{};
}

template <typename T>
T getConfigValueOr(const std::string& name, const T& fallback) {
    const auto* value = HyprlandAPI::getConfigValue(pHandle, name);
    if (!value) {
        Log::logger->log(Log::WARN, "Hyprspace: missing config value {}, using default", name);
        return fallback;
    }

    try {
        return std::any_cast<T>(value->getValue());
    } catch (const std::bad_any_cast& e) {
        Log::logger->log(Log::ERR, "Hyprspace: invalid config value type for {}: {}", name, e.what());
        return fallback;
    }
}

CHyprColor getConfigColorOr(const std::string& name, const CHyprColor& fallback) {
    return CHyprColor(getConfigValueOr<Hyprlang::INT>(name, fallback.getAsHex()));
}

void reloadConfig() {
    Config::workspaceActiveBackground = getConfigColorOr("plugin:overview:workspaceActiveBackground", Config::workspaceActiveBackground);
    Config::workspaceInactiveBackground = getConfigColorOr("plugin:overview:workspaceInactiveBackground", Config::workspaceInactiveBackground);

    Config::workspaceMargin = getConfigValueOr<Hyprlang::INT>("plugin:overview:workspaceMargin", Config::workspaceMargin);
    Config::reservedArea = getConfigValueOr<Hyprlang::INT>("plugin:overview:reservedArea", Config::reservedArea);
    Config::showNewWorkspace = getConfigValueOr<Hyprlang::INT>("plugin:overview:showNewWorkspace", Config::showNewWorkspace) != 0;

    Config::disableBlur = getConfigValueOr<Hyprlang::INT>("plugin:overview:disableBlur", Config::disableBlur) != 0;

    // We don't need to store exitKey in Config namespace as it's only used in onKeyPress

    for (auto& widget : g_overviewWidgets) {
        if (widget->isActive())
            widget->hide();
    }

    Config::mainModToggle = getConfigValueOr<Hyprlang::INT>("plugin:overview:mainModToggle", Config::mainModToggle) != 0;
    Config::mainModKey = getConfigValueOr<Hyprlang::STRING>("plugin:overview:mainModKey", Config::mainModKey.c_str());
    Config::hotCorner = getConfigValueOr<Hyprlang::INT>("plugin:overview:hotCorner", Config::hotCorner) != 0;
    Config::hotCornerSize = getConfigValueOr<Hyprlang::INT>("plugin:overview:hotCornerSize", Config::hotCornerSize);
    Config::hotCornerCooldown = getConfigValueOr<Hyprlang::INT>("plugin:overview:hotCornerCooldown", Config::hotCornerCooldown);
    Config::hotCornerApproachDistance = getConfigValueOr<Hyprlang::INT>("plugin:overview:hotCornerApproachDistance", Config::hotCornerApproachDistance);
    Config::hotCornerMinTravel = getConfigValueOr<Hyprlang::INT>("plugin:overview:hotCornerMinTravel", Config::hotCornerMinTravel);
    Config::hotCornerMinSpeed = getConfigValueOr<Hyprlang::FLOAT>("plugin:overview:hotCornerMinSpeed", Config::hotCornerMinSpeed);
    if (Config::hotCornerSize < 1) Config::hotCornerSize = 1;
    if (Config::hotCornerCooldown < 0) Config::hotCornerCooldown = 0;
    if (Config::hotCornerApproachDistance < Config::hotCornerSize) Config::hotCornerApproachDistance = Config::hotCornerSize;
    if (Config::hotCornerMinTravel < 1) Config::hotCornerMinTravel = 1;
    if (Config::hotCornerMinSpeed < 0.01f) Config::hotCornerMinSpeed = 0.01f;

    g_mainModKeysym = xkb_keysym_from_name(Config::mainModKey.c_str(), XKB_KEYSYM_CASE_INSENSITIVE);
    if (g_mainModKeysym == XKB_KEY_NoSymbol) {
        Log::logger->log(Log::WARN, "Overview: invalid plugin:overview:mainModKey {}, fallback to Super_L", Config::mainModKey);
        Config::mainModKey = "Super_L";
        g_mainModKeysym = XKB_KEY_Super_L;
    }

    // TODO: schedule frame for monitor?
}

void registerMonitors() {
    // create a widget for each monitor
    for (auto& m : g_pCompositor->m_monitors) {
        if (getWidgetForMonitor(m) != nullptr) continue;
        CHyprspaceWidget* widget = new CHyprspaceWidget(m->m_id);
        g_overviewWidgets.emplace_back(widget);
    }
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE inHandle) {
    pHandle = inHandle;

    Log::logger->log(Log::DEBUG, "Loading Quickshell GNOME Overview plugin");

    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:panelColor", Hyprlang::INT{CHyprColor(0.02, 0.025, 0.032, 0.42).getAsHex()});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:panelBorderColor", Hyprlang::INT{CHyprColor(1, 1, 1, 0).getAsHex()});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:workspaceActiveBackground", Hyprlang::INT{CHyprColor(0, 0, 0, 0).getAsHex()});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:workspaceInactiveBackground", Hyprlang::INT{CHyprColor(0, 0, 0, 0).getAsHex()});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:workspaceActiveBorder", Hyprlang::INT{CHyprColor(1, 1, 1, 0).getAsHex()});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:workspaceInactiveBorder", Hyprlang::INT{CHyprColor(1, 1, 1, 0).getAsHex()});

    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:panelHeight", Hyprlang::INT{520});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:panelBorderWidth", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:workspaceMargin", Hyprlang::INT{16});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:workspaceBorderSize", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:reservedArea", Hyprlang::INT{110});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:adaptiveHeight", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:centerAligned", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:onBottom", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hideBackgroundLayers", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hideTopLayers", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hideOverlayLayers", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:drawActiveWorkspace", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hideRealLayers", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:affectStrut", Hyprlang::INT{0});

    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:overrideGaps", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:gapsIn", Hyprlang::INT{24});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:gapsOut", Hyprlang::INT{70});

    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:autoDrag", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:autoScroll", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:exitOnClick", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:switchOnDrop", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:exitOnSwitch", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:showNewWorkspace", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:showEmptyWorkspace", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:showSpecialWorkspace", Hyprlang::INT{0});

    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:disableGestures", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:reverseSwipe", Hyprlang::INT{0});

    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:disableBlur", Hyprlang::INT{0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:overrideAnimSpeed", Hyprlang::FLOAT{1.0});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:dragAlpha", Hyprlang::FLOAT{0.2});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:exitKey", Hyprlang::STRING{"Escape"});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:mainModToggle", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:mainModKey", Hyprlang::STRING{"Super_L"});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hotCorner", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hotCornerSize", Hyprlang::INT{1});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hotCornerCooldown", Hyprlang::INT{450});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hotCornerApproachDistance", Hyprlang::INT{72});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hotCornerMinTravel", Hyprlang::INT{18});
    HyprlandAPI::addConfigValue(pHandle, "plugin:overview:hotCornerMinSpeed", Hyprlang::FLOAT{0.18});

    g_pConfigReloadHook = Event::bus()->m_events.config.reloaded.listen([]() { reloadConfig(); });
    g_pStartHook = Event::bus()->m_events.start.listen([]() {
        reloadConfig();
        registerMonitors();
    });
    HyprlandAPI::reloadConfig();

    HyprlandAPI::addDispatcherV2(pHandle, "overview:toggle", ::dispatchToggleOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "overview:open", ::dispatchOpenOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "overview:close", ::dispatchCloseOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "overview:select", ::dispatchSelectOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "overview:next", ::dispatchNextOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "overview:prev", ::dispatchPrevOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "overview:applications", ::dispatchApplicationsOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:toggle", ::dispatchToggleOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:open", ::dispatchOpenOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:close", ::dispatchCloseOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:select", ::dispatchSelectOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:next", ::dispatchNextOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:prev", ::dispatchPrevOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:applications", ::dispatchApplicationsOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:refresh-pointer", ::dispatchRefreshPointer);

    g_pRenderHook = Event::bus()->m_events.render.stage.listen([](eRenderStage stage) { onRender(stage); });

    // refresh on layer change
    g_pOpenLayerHook = Event::bus()->m_events.layer.opened.listen([](PHLLS layer) {
        g_layoutNeedsRefresh = true;
        if (layer && isQuickshellLayerNamespace(layer->m_namespace))
            requestPointerRefresh(12);
    });
    g_pCloseLayerHook = Event::bus()->m_events.layer.closed.listen([](PHLLS layer) {
        g_layoutNeedsRefresh = true;
        if (layer && isQuickshellLayerNamespace(layer->m_namespace))
            requestPointerRefresh(8);
    });


    g_pMouseMoveHook = listenCancellable<Vector2D>(Event::bus()->m_events.input.mouse.move, onMouseMove);
    g_pMouseButtonHook = listenCancellable<IPointer::SButtonEvent>(Event::bus()->m_events.input.mouse.button, onMouseButton);
    g_pMouseAxisHook = listenCancellable<IPointer::SAxisEvent>(Event::bus()->m_events.input.mouse.axis, onMouseAxis);

    g_pTouchDownHook = listenCancellable<ITouch::SDownEvent>(Event::bus()->m_events.input.touch.down, onTouchDown);
    g_pTouchMoveHook = listenCancellable<ITouch::SMotionEvent>(Event::bus()->m_events.input.touch.motion, onTouchMove);
    g_pTouchUpHook = listenCancellable<ITouch::SUpEvent>(Event::bus()->m_events.input.touch.up, onTouchUp);

    g_pSwipeBeginHook = listenCancellable<IPointer::SSwipeBeginEvent>(Event::bus()->m_events.gesture.swipe.begin, onSwipeBegin);
    g_pSwipeUpdateHook = listenCancellable<IPointer::SSwipeUpdateEvent>(Event::bus()->m_events.gesture.swipe.update, onSwipeUpdate);
    g_pSwipeEndHook = listenCancellable<IPointer::SSwipeEndEvent>(Event::bus()->m_events.gesture.swipe.end, onSwipeEnd);

    g_pKeyPressHook = listenCancellable<IKeyboard::SKeyEvent>(Event::bus()->m_events.input.keyboard.key, onKeyPress);

    g_pSwitchWorkspaceHook = Event::bus()->m_events.workspace.active.listen(onWorkspaceChange);

    registerMonitors();
    g_pAddMonitorHook = Event::bus()->m_events.monitor.added.listen([](PHLMONITOR) { registerMonitors(); });

    return {"Quickshell Minimal Overview", "Minimal live workspace previews with background dimming, based on Hyprspace", "KZdkm + ChatGPT", "0.2"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_pRenderHook.reset();
    g_pConfigReloadHook.reset();
    g_pOpenLayerHook.reset();
    g_pCloseLayerHook.reset();
    g_pMouseMoveHook.reset();
    g_pMouseButtonHook.reset();
    g_pMouseAxisHook.reset();
    g_pTouchDownHook.reset();
    g_pTouchMoveHook.reset();
    g_pTouchUpHook.reset();
    g_pSwipeBeginHook.reset();
    g_pSwipeUpdateHook.reset();
    g_pSwipeEndHook.reset();
    g_pKeyPressHook.reset();
    g_pSwitchWorkspaceHook.reset();
    g_pAddMonitorHook.reset();
    g_pStartHook.reset();

    g_overviewWidgets.clear();

    pHandle = nullptr;
}
