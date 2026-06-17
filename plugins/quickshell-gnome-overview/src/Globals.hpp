#pragma once

#include <functional>
#include <string>
#include <tuple>
#include <type_traits>

#include <hyprutils/memory/SharedPtr.hpp>

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/types.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/managers/animation/AnimationManager.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/helpers/time/Time.hpp>
#include <hyprland/src/event/EventBus.hpp>

// Hyprland v0.54+: cancellable input uses Event::SCallbackInfo (not legacy CEvent*).
using SCallbackInfo = Event::SCallbackInfo;

// Must match Hyprutils::Signal::CSignalT::RefArg (hyprutils/signal/Signal.hpp).
template <typename T>
using HyprSignalRefArg = std::conditional_t<std::is_trivially_copyable_v<T>, T, const T&>;

// Unpack Hyprutils::CSignalT::emit() tuple — first event arg is often stored by value (trivial types).
template <typename EventType, typename Signal>
CHyprSignalListener listenCancellable(Signal& signal, std::function<void(const EventType&, SCallbackInfo&)> handler) {
    struct Hack : Hyprutils::Signal::CSignalBase {
        using CSignalBase::registerListenerInternal;
    };
    return reinterpret_cast<Hack&>(signal).registerListenerInternal([handler](void* args) {
        using Tuple = std::tuple<HyprSignalRefArg<EventType>, HyprSignalRefArg<Event::SCallbackInfo&>>;
        auto* tup = static_cast<Tuple*>(args);
        handler(std::get<0>(*tup), std::get<1>(*tup));
    });
}

inline HANDLE pHandle = NULL;

namespace Config {
    extern CHyprColor workspaceActiveBackground;
    extern CHyprColor workspaceInactiveBackground;

    extern int workspaceMargin;
    extern int reservedArea;
    extern bool showNewWorkspace;

    extern bool disableBlur;

    // GNOME-like single-mainMod toggle. The plugin toggles overview only when
    // the main modifier is pressed and released alone. If another key/mouse/touch
    // event happens while the modifier is held, the release is ignored.
    extern bool mainModToggle;
    extern std::string mainModKey;
    extern bool hotCorner;
    extern int hotCornerSize;
    extern int hotCornerCooldown;
    extern int hotCornerApproachDistance;
    extern int hotCornerMinTravel;
    extern float hotCornerMinSpeed;
}
