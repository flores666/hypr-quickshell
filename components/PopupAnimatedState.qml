import QtQuick

AnimatedPopupState {
    id: root

    AnimationTokens {
        id: motion
    }

    openDuration: motion.popupOpenDuration
    closeDuration: motion.popupCloseDuration
    closeSafetyDelay: motion.popupCloseDuration + 55
}
