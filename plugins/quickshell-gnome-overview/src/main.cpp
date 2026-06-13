#include <hyprland/src/plugins/PluginSystem.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/devices/IKeyboard.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/debug/log/Logger.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprutils/memory/SharedPtr.hpp>
#include <any>
#include <chrono>
#include <cmath>
#include "Overview.hpp"
#include "Globals.hpp"

void* pRenderWindow;
void* pRenderLayer;

std::vector<std::shared_ptr<CHyprspaceWidget>> g_overviewWidgets;


CHyprColor Config::panelBaseColor = CHyprColor(0.02, 0.025, 0.032, 0.42);
CHyprColor Config::panelBorderColor = CHyprColor(1, 1, 1, 0);
CHyprColor Config::workspaceActiveBackground = CHyprColor(0, 0, 0, 0);
CHyprColor Config::workspaceInactiveBackground = CHyprColor(0, 0, 0, 0);
CHyprColor Config::workspaceActiveBorder = CHyprColor(1, 1, 1, 0);
CHyprColor Config::workspaceInactiveBorder = CHyprColor(1, 1, 1, 0);

int Config::panelHeight = 520;
int Config::panelBorderWidth = 0;
int Config::workspaceMargin = 16;
int Config::reservedArea = 110;
int Config::workspaceBorderSize = 0;
bool Config::adaptiveHeight = false; // TODO: implement
bool Config::centerAligned = true;
bool Config::onBottom = true; // Keep overview above the bottom AppDock.
bool Config::hideBackgroundLayers = false;
bool Config::hideTopLayers = true;
bool Config::hideOverlayLayers = true;
bool Config::drawActiveWorkspace = true;
bool Config::hideRealLayers = false;
bool Config::affectStrut = false;

bool Config::overrideGaps = false;
int Config::gapsIn = 24;
int Config::gapsOut = 70;

bool Config::autoDrag = false;
bool Config::autoScroll = true;
bool Config::exitOnClick = true;
bool Config::switchOnDrop = false;
bool Config::exitOnSwitch = true;
bool Config::showNewWorkspace = false;
bool Config::showEmptyWorkspace = true;
bool Config::showSpecialWorkspace = false;

bool Config::disableGestures = true;
bool Config::reverseSwipe = false;

bool Config::disableBlur = false;

float Config::overrideAnimSpeed = 1.0;

float Config::dragAlpha = 0.2;

bool Config::mainModToggle = true;
std::string Config::mainModKey = "Super_L";
bool Config::hotCorner = true;
int Config::hotCornerSize = 1;
int Config::hotCornerCooldown = 450;
int Config::hotCornerApproachDistance = 72;
int Config::hotCornerMinTravel = 18;
float Config::hotCornerMinSpeed = 0.18;

int numWorkspaces = -1; //hyprsplit/split-monitor-workspaces support

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
        if (widget != nullptr)
            if (widget->isActive())
                widget->show();
    }
}

bool g_layoutNeedsRefresh = true;

static bool g_mainModDown = false;
static bool g_mainModCancelled = false;
static xkb_keysym_t g_mainModKeysym = XKB_KEY_Super_L;
static std::chrono::steady_clock::time_point g_mainModPressTime;
static bool g_hotCornerInside = false;
static bool g_hotCornerHasLastCoords = false;
static Vector2D g_hotCornerLastCoords;
static bool g_hotCornerApproachActive = false;
static Vector2D g_hotCornerApproachStartCoords;
static std::chrono::steady_clock::time_point g_hotCornerApproachStartTime;
static bool g_mouseButtonDown = false;
static std::chrono::steady_clock::time_point g_hotCornerLastOpen = std::chrono::steady_clock::now() - std::chrono::seconds(10);

// for restoring dragged window's alpha value
float g_oAlpha = -1;


static bool isAnyOverviewActive() {
    for (auto& widget : g_overviewWidgets) {
        if (widget && widget->isActive())
            return true;
    }
    return false;
}

static void toggleOverviewForCurrentMonitor() {
    const auto currentMonitor = g_pCompositor->getMonitorFromCursor();
    const auto widget = getWidgetForMonitor(currentMonitor);
    if (!widget)
        return;

    widget->isActive() ? widget->hide() : widget->show();
}

static void openOverviewForMonitor(PHLMONITORREF monitor) {
    const auto widget = getWidgetForMonitor(monitor);
    if (!widget || widget->isActive())
        return;

    widget->show();
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
        if (g_layoutNeedsRefresh) {
            refreshWidgets();
            g_layoutNeedsRefresh = false;
        }
        return;
    }

    if (renderStage != eRenderStage::RENDER_POST_WINDOWS)
        return;

    const auto widget = getWidgetForMonitor(g_pHyprRenderer->m_renderData.pMonitor);
    if (widget && widget->getOwner() && widget->isActive())
        widget->draw();
}

// event hook, currently this is only here to re-hide top layer panels on workspace change
void onWorkspaceChange(PHLWORKSPACE pWorkspace) {

    if (!pWorkspace) return;

    auto widget = getWidgetForMonitor(g_pCompositor->getMonitorFromID(pWorkspace->m_monitor->m_id));
    if (widget != nullptr)
        if (widget->isActive())
            widget->show();
}

// GNOME-like hot corner: pushing the pointer into the top-left pixel opens overview.
// It never toggles/closes overview, so it is safe to use together with the dock button and mainMod toggle.
void onMouseMove(const Vector2D&, SCallbackInfo&) {
    cancelMainModToggleGesture();
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

    if (event.button != BTN_LEFT) return;

    const auto pressed = event.state == WL_POINTER_BUTTON_STATE_PRESSED;
    const auto pMonitor = g_pCompositor->getMonitorFromCursor();
    if (pMonitor) {
        const auto widget = getWidgetForMonitor(pMonitor);
        if (widget) {
            if (widget->isActive()) {
                info.cancelled = !widget->buttonEvent(pressed, g_pInputManager->getMouseCoordsInternal());
            }
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
                info.cancelled = !widget->axisEvent(event.delta, event.axis, g_pInputManager->getMouseCoordsInternal());
            }
        }
    }

}

// event hook for swipe
void onSwipeBegin(const IPointer::SSwipeBeginEvent& event, SCallbackInfo& info) {
    cancelMainModToggleGesture();

    if (Config::disableGestures) return;

    const auto widget = getWidgetForMonitor(g_pCompositor->getMonitorFromCursor());
    if (widget != nullptr)
        widget->beginSwipe(event);

    // end other widget swipe
    for (auto& w : g_overviewWidgets) {
        if (w != widget && w->isSwiping()) {
            IPointer::SSwipeEndEvent dummy;
            dummy.cancelled = true;
            w->endSwipe(dummy);
        }
    }
}

// event hook for update swipe, most of the swiping mechanics are here
void onSwipeUpdate(const IPointer::SSwipeUpdateEvent& event, SCallbackInfo& info) {

    if (Config::disableGestures) return;

    const auto widget = getWidgetForMonitor(g_pCompositor->getMonitorFromCursor());
    if (widget != nullptr)
        info.cancelled = !widget->updateSwipe(event);
}

// event hook for end swipe
void onSwipeEnd(const IPointer::SSwipeEndEvent& event, SCallbackInfo& info) {

    if (Config::disableGestures) return;

    const auto widget = getWidgetForMonitor(g_pCompositor->getMonitorFromCursor());
    if (widget != nullptr)
        widget->endSwipe(event);
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

    // Main modifier handling must be done inside the plugin, not with Hyprland bindr.
    // bindr on $mainMod fires even after combinations such as $mainMod+Space layout switch.
    // Here we toggle only if the configured mainMod was pressed and released alone.
    if (Config::mainModToggle && isConfiguredMainMod(keysym)) {
        if (pressed) {
            if (!g_mainModDown) {
                g_mainModDown = true;
                const uint32_t mods = keyboard->getModifiers();
                const uint32_t unsafeOtherMods = mods & (HL_MODIFIER_SHIFT | HL_MODIFIER_CTRL | HL_MODIFIER_ALT | HL_MODIFIER_MOD2 | HL_MODIFIER_MOD3 | HL_MODIFIER_MOD5);
                g_mainModCancelled = unsafeOtherMods != 0;
                g_mainModPressTime = std::chrono::steady_clock::now();
            }
            return;
        }

        if (released && g_mainModDown) {
            const auto heldMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - g_mainModPressTime).count();
            const bool safeSinglePress = !g_mainModCancelled && heldMs >= 25;

            g_mainModDown = false;
            g_mainModCancelled = false;

            if (safeSinglePress) {
                toggleOverviewForCurrentMonitor();
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
    if (!pExitKeyCfg)
        return;

    const Hyprlang::STRING cfgExitKey = std::any_cast<Hyprlang::STRING>(pExitKeyCfg->getValue());
    if (!cfgExitKey || cfgExitKey[0] == '\0')
        return;

    const xkb_keysym_t cfgExitKeysym = xkb_keysym_from_name(cfgExitKey, XKB_KEYSYM_CASE_INSENSITIVE);

    if (pressed && keysym == cfgExitKeysym) {
        bool overviewActive = false;
        for (auto& widget : g_overviewWidgets) {
            if (widget != nullptr && widget->isActive()) {
                widget->hide();
                overviewActive = true;
            }
        }
        if (overviewActive)
            info.cancelled = true;
    }
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
                            widget->hide();
                }
            }
            else {
                for (auto& widget : g_overviewWidgets) {
                    if (widget != nullptr)
                        if (!widget->isActive())
                            widget->show();
                }
            }
        }
        else
            widget->isActive() ? widget->hide() : widget->show();
    }
    return SDispatchResult{};
}

static SDispatchResult dispatchOpenOverview(std::string arg) {
    if (arg.contains("all")) {
        for (auto& widget : g_overviewWidgets) {
            if (!widget->isActive()) widget->show();
        }
    }
    else {
        auto currentMonitor = g_pCompositor->getMonitorFromCursor();
        auto widget = getWidgetForMonitor(currentMonitor);
        if (widget)
            if (!widget->isActive()) widget->show();
    }
    return SDispatchResult{};
}

static SDispatchResult dispatchCloseOverview(std::string arg) {
    if (arg.contains("all")) {
        for (auto& widget : g_overviewWidgets) {
            if (widget->isActive()) widget->hide();
        }
    }
    else {
        auto currentMonitor = g_pCompositor->getMonitorFromCursor();
        auto widget = getWidgetForMonitor(currentMonitor);
        if (widget)
            if (widget->isActive()) widget->hide();
    }
    return SDispatchResult{};
}

void* findFunctionBySymbol(HANDLE inHandle, const std::string func, const std::string sym) {
    // should return all functions
    auto funcSearch = HyprlandAPI::findFunctionsByName(inHandle, func);
    for (auto f : funcSearch) {
        if (f.demangled.contains(sym))
            return f.address;
    }
    return nullptr;
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
    Config::panelBaseColor = getConfigColorOr("plugin:overview:panelColor", Config::panelBaseColor);
    Config::panelBorderColor = getConfigColorOr("plugin:overview:panelBorderColor", Config::panelBorderColor);
    Config::workspaceActiveBackground = getConfigColorOr("plugin:overview:workspaceActiveBackground", Config::workspaceActiveBackground);
    Config::workspaceInactiveBackground = getConfigColorOr("plugin:overview:workspaceInactiveBackground", Config::workspaceInactiveBackground);
    Config::workspaceActiveBorder = getConfigColorOr("plugin:overview:workspaceActiveBorder", Config::workspaceActiveBorder);
    Config::workspaceInactiveBorder = getConfigColorOr("plugin:overview:workspaceInactiveBorder", Config::workspaceInactiveBorder);

    Config::panelHeight = getConfigValueOr<Hyprlang::INT>("plugin:overview:panelHeight", Config::panelHeight);
    Config::panelBorderWidth = getConfigValueOr<Hyprlang::INT>("plugin:overview:panelBorderWidth", Config::panelBorderWidth);
    Config::workspaceMargin = getConfigValueOr<Hyprlang::INT>("plugin:overview:workspaceMargin", Config::workspaceMargin);
    Config::reservedArea = getConfigValueOr<Hyprlang::INT>("plugin:overview:reservedArea", Config::reservedArea);
    Config::workspaceBorderSize = getConfigValueOr<Hyprlang::INT>("plugin:overview:workspaceBorderSize", Config::workspaceBorderSize);
    Config::adaptiveHeight = getConfigValueOr<Hyprlang::INT>("plugin:overview:adaptiveHeight", Config::adaptiveHeight) != 0;
    Config::centerAligned = getConfigValueOr<Hyprlang::INT>("plugin:overview:centerAligned", Config::centerAligned) != 0;
    Config::onBottom = getConfigValueOr<Hyprlang::INT>("plugin:overview:onBottom", Config::onBottom) != 0;
    Config::hideBackgroundLayers = getConfigValueOr<Hyprlang::INT>("plugin:overview:hideBackgroundLayers", Config::hideBackgroundLayers) != 0;
    Config::hideTopLayers = getConfigValueOr<Hyprlang::INT>("plugin:overview:hideTopLayers", Config::hideTopLayers) != 0;
    Config::hideOverlayLayers = getConfigValueOr<Hyprlang::INT>("plugin:overview:hideOverlayLayers", Config::hideOverlayLayers) != 0;
    Config::drawActiveWorkspace = getConfigValueOr<Hyprlang::INT>("plugin:overview:drawActiveWorkspace", Config::drawActiveWorkspace) != 0;
    Config::hideRealLayers = getConfigValueOr<Hyprlang::INT>("plugin:overview:hideRealLayers", Config::hideRealLayers) != 0;
    Config::affectStrut = getConfigValueOr<Hyprlang::INT>("plugin:overview:affectStrut", Config::affectStrut) != 0;

    Config::overrideGaps = getConfigValueOr<Hyprlang::INT>("plugin:overview:overrideGaps", Config::overrideGaps) != 0;
    Config::gapsIn = getConfigValueOr<Hyprlang::INT>("plugin:overview:gapsIn", Config::gapsIn);
    Config::gapsOut = getConfigValueOr<Hyprlang::INT>("plugin:overview:gapsOut", Config::gapsOut);

    Config::autoDrag = getConfigValueOr<Hyprlang::INT>("plugin:overview:autoDrag", Config::autoDrag) != 0;
    Config::autoScroll = getConfigValueOr<Hyprlang::INT>("plugin:overview:autoScroll", Config::autoScroll) != 0;
    Config::exitOnClick = getConfigValueOr<Hyprlang::INT>("plugin:overview:exitOnClick", Config::exitOnClick) != 0;
    Config::switchOnDrop = getConfigValueOr<Hyprlang::INT>("plugin:overview:switchOnDrop", Config::switchOnDrop) != 0;
    Config::exitOnSwitch = getConfigValueOr<Hyprlang::INT>("plugin:overview:exitOnSwitch", Config::exitOnSwitch) != 0;
    Config::showNewWorkspace = getConfigValueOr<Hyprlang::INT>("plugin:overview:showNewWorkspace", Config::showNewWorkspace) != 0;
    Config::showEmptyWorkspace = getConfigValueOr<Hyprlang::INT>("plugin:overview:showEmptyWorkspace", Config::showEmptyWorkspace) != 0;
    Config::showSpecialWorkspace = getConfigValueOr<Hyprlang::INT>("plugin:overview:showSpecialWorkspace", Config::showSpecialWorkspace) != 0;

    Config::disableGestures = getConfigValueOr<Hyprlang::INT>("plugin:overview:disableGestures", Config::disableGestures) != 0;
    Config::reverseSwipe = getConfigValueOr<Hyprlang::INT>("plugin:overview:reverseSwipe", Config::reverseSwipe) != 0;

    Config::disableBlur = getConfigValueOr<Hyprlang::INT>("plugin:overview:disableBlur", Config::disableBlur) != 0;

    Config::overrideAnimSpeed = getConfigValueOr<Hyprlang::FLOAT>("plugin:overview:overrideAnimSpeed", Config::overrideAnimSpeed);
    
    // We don't need to store exitKey in Config namespace as it's only used in onKeyPress

    for (auto& widget : g_overviewWidgets) {
        widget->updateConfig();
        if (widget->isActive() || widget->isSwiping()) {
            widget->hide();
            IPointer::SSwipeEndEvent dummy;
            dummy.cancelled = true;
            widget->endSwipe(dummy);
        }
    }

    Config::dragAlpha = getConfigValueOr<Hyprlang::FLOAT>("plugin:overview:dragAlpha", Config::dragAlpha);
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

    // get number of workspaces from hyprsplit or split-monitor-workspaces plugin config
    Hyprlang::CConfigValue* numWorkspacesConfig = HyprlandAPI::getConfigValue(pHandle, "plugin:hyprsplit:num_workspaces");
    if (!numWorkspacesConfig)
        numWorkspacesConfig = HyprlandAPI::getConfigValue(pHandle, "plugin:split-monitor-workspaces:count");
    if (numWorkspacesConfig)
        numWorkspaces = std::any_cast<Hyprlang::INT>(numWorkspacesConfig->getValue());

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
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:toggle", ::dispatchToggleOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:open", ::dispatchOpenOverview);
    HyprlandAPI::addDispatcherV2(pHandle, "qs-gnome-overview:close", ::dispatchCloseOverview);

    g_pRenderHook = Event::bus()->m_events.render.stage.listen([](eRenderStage stage) { onRender(stage); });

    // refresh on layer change
    g_pOpenLayerHook = Event::bus()->m_events.layer.opened.listen([](PHLLS) { g_layoutNeedsRefresh = true; });
    g_pCloseLayerHook = Event::bus()->m_events.layer.closed.listen([](PHLLS) { g_layoutNeedsRefresh = true; });


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

    // Minimal renderer does not hook private renderWindow/renderLayer symbols.
    pRenderWindow = nullptr;
    pRenderLayer = nullptr;

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

    pRenderWindow = nullptr;
    pRenderLayer = nullptr;
    pHandle = nullptr;
}
