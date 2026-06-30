import QtQuick
import "../../services" as Services

Item {
    id: controller

    visible: false

    property var overview: null
    property var inputContent: null
    property bool interactive: false
    property string query: ""
    property bool pointerSuppressedByKeyboard: false
    property bool pointerRefreshGuardActive: false
    property bool inputReadyNotified: false
    property int inputFocusAttemptsRemaining: 0

    function normalizedQuery() {
        return String(query || "").trim().toLowerCase();
    }

    function isSearchTextActive(text) {
        return String(text || "").trim().length > 0;
    }

    function currentSearchActive() {
        return isSearchTextActive(query);
    }

    function requestSearchFocusAttempt() {
        if (!interactive || !inputContent || !inputContent.searchField)
            return false;

        inputContent.forceSearchFocus();
        Services.ShellActions.refreshPointerFocus();
        return inputContent.searchField.activeFocus;
    }

    function focusSearchFieldWhenReady() {
        if (!interactive)
            return;

        inputFocusAttemptsRemaining = Math.max(inputFocusAttemptsRemaining, 10);
        inputFocusRetryTimer.restart();
        Qt.callLater(function () {
            if (controller.interactive && !controller.inputReadyNotified)
                inputFocusRetryTimer.restart();
        });
    }

    function notifyApplicationsInputReadyWhenFocused() {
        if (inputReadyNotified || !interactive || !inputContent || !inputContent.searchField || !inputContent.searchField.activeFocus)
            return;

        inputReadyNotified = true;
        Services.ShellActions.notifyApplicationsInputReady();
    }

    function notifyApplicationsInputNotReady() {
        if (!inputReadyNotified)
            return;

        inputReadyNotified = false;
        Services.ShellActions.notifyApplicationsInputNotReady();
    }

    function resetInputReadiness(notifyNative) {
        if (notifyNative)
            notifyApplicationsInputNotReady();
        else
            inputReadyNotified = false;

        inputFocusAttemptsRemaining = 0;
        inputFocusRetryTimer.stop();
    }

    function activateApplicationsInput() {
        Services.ShellActions.setApplicationsInputQuery(query);
        focusSearchFieldWhenReady();
    }

    function deactivateApplicationsInput() {
        resetInputReadiness(true);
        clearSearchFocus();
        if (overview)
            overview.closeContextMenu();
    }

    function keepSearchFocusWhileOwned() {
        if (!interactive || !inputContent || !inputContent.searchField)
            return;

        if (inputContent.searchField.activeFocus) {
            notifyApplicationsInputReadyWhenFocused();
            return;
        }

        inputFocusAttemptsRemaining = Math.max(inputFocusAttemptsRemaining, 8);
        inputFocusRetryTimer.restart();
    }

    function clearSearchFocus() {
        if (inputContent)
            inputContent.clearSearchFocus();
    }

    function suppressPointerAfterKeyboardInput() {
        if (!interactive)
            return;

        var shouldRefreshPointerFocus = !pointerSuppressedByKeyboard;
        pointerSuppressedByKeyboard = true;
        pointerRefreshGuardActive = true;
        pointerRefreshGuardTimer.restart();

        if (shouldRefreshPointerFocus)
            Services.ShellActions.refreshPointerFocus();
    }

    function clearPointerSuppression() {
        pointerRefreshGuardTimer.stop();
        pointerRefreshGuardActive = false;
        pointerSuppressedByKeyboard = false;
    }

    function revealPointerAfterMouseMove() {
        if (pointerRefreshGuardActive)
            return;

        if (pointerSuppressedByKeyboard)
            pointerSuppressedByKeyboard = false;
    }

    function interactiveCursorShape(defaultShape) {
        return pointerSuppressedByKeyboard ? Qt.BlankCursor : defaultShape;
    }

    Timer {
        id: pointerRefreshGuardTimer
        interval: 120
        repeat: false
        onTriggered: controller.pointerRefreshGuardActive = false
    }

    Timer {
        id: inputFocusRetryTimer
        interval: 16
        repeat: true
        onTriggered: {
            if (!controller.interactive || controller.inputReadyNotified) {
                controller.inputFocusAttemptsRemaining = 0;
                stop();
                return;
            }

            var focused = controller.requestSearchFocusAttempt();
            controller.inputFocusAttemptsRemaining -= 1;
            if (focused) {
                controller.notifyApplicationsInputReadyWhenFocused();
                stop();
                return;
            }

            if (controller.inputFocusAttemptsRemaining <= 0)
                stop();
        }
    }
}
