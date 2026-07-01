import QtQuick

QtObject {
    readonly property int hoverDuration: 130
    readonly property int pressDuration: 90
    readonly property int releaseDuration: 130
    readonly property int popupOpenDuration: 125
    readonly property int popupCloseDuration: 95
    readonly property int cursorDelay: 35

    // Shared motion language. The workspace/live-overview morph uses a cubic
    // ease-in-out curve and a short 240ms travel time; notification motion reuses
    // that same timing so UI sections feel like one system instead of separate
    // ad-hoc animations.
    readonly property int workspaceMorphDuration: 240
    readonly property int workspaceMorphEasing: Easing.InOutCubic

    readonly property int notificationMorphDuration: workspaceMorphDuration
    readonly property int notificationMorphEasing: workspaceMorphEasing
    readonly property int notificationEnterOffsetX: 24
    readonly property int notificationExitOffsetX: 32
    readonly property real notificationEnterScale: 1.0
    readonly property real notificationGroupRevealFadeStart: 0.18

    readonly property int systemNestedOpenDuration: Math.min(170, Math.max(120, workspaceMorphDuration * 0.62))
    readonly property int systemNestedCloseDuration: Math.min(135, Math.max(95, popupCloseDuration + 25))
    readonly property real systemNestedCardStartScale: 0.972
    readonly property int systemNestedCardOffsetY: 10
}
