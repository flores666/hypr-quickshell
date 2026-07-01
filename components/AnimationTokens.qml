import QtQuick

QtObject {
    readonly property int hoverDuration: 130
    readonly property int pressDuration: 90
    readonly property int releaseDuration: 130
    readonly property int popupOpenDuration: 125
    readonly property int popupCloseDuration: 95
    readonly property int cursorDelay: 35

    // Same motion language as the native live-overview workspace morph:
    // cubic ease-in-out, ~240ms, no bounce/overshoot. Keep these values
    // centralized so popup sections do not drift into different animation curves.
    readonly property int workspaceMorphDuration: 240
    readonly property int workspaceMorphEasing: Easing.InOutCubic

    readonly property int notificationMorphDuration: workspaceMorphDuration
    readonly property int notificationMorphEasing: workspaceMorphEasing
    readonly property int notificationEnterOffsetX: 22
    readonly property real notificationEnterScale: 0.985
}
