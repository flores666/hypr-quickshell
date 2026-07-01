import QtQuick
import "../../components" as Components
import "../../services" as Services

Item {
    id: root

    required property bool interactive
    required property bool showVisuals
    property bool visualInteractive: interactive
    property string queryText: ""
    property bool hidePointerCursor: false
    property var pointerMovedCallback: null
    property alias inputField: searchInput
    property bool enterActivationPending: false

    readonly property int horizontalPadding: 16
    readonly property int iconSize: 18
    readonly property int iconWidth: 20
    readonly property int textLeftInset: 46
    readonly property int textRightInset: 18
    readonly property int searchFontSize: 13

    signal queryEdited(string text)
    signal moveSelectionRequested(string direction)
    signal activateSelectionRequested()


    function notifyPointerMoved() {
        if (root.pointerMovedCallback)
            root.pointerMovedCallback();
    }

    function forceSearchFocus() {
        if (!root.interactive)
            return;
        searchInput.forceActiveFocus();
        searchInput.cursorPosition = searchInput.text.length;
    }

    function clearSearchFocus() {
        searchInput.focus = false;
        enterActivationPending = false;
    }

    function clearPendingKeyboardActivation() {
        enterActivationPending = false;
    }

    onInteractiveChanged: {
        if (!interactive)
            clearPendingKeyboardActivation();
    }

    opacity: showVisuals ? 1 : 0
    visible: showVisuals || interactive

    Components.GlassPanel {
        id: searchBackground
        anchors.fill: parent
        radiusSize: Math.round(height / 2)
        glassColor: "#8a000000"
        antialiasing: true
    }

    HoverHandler {
        enabled: root.interactive
        cursorShape: root.hidePointerCursor ? Qt.BlankCursor : Qt.IBeamCursor
        onPointChanged: root.notifyPointerMoved()
    }

    Item {
        id: searchIcon
        anchors.left: parent.left
        anchors.leftMargin: root.horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconWidth
        height: root.iconWidth
        visible: root.showVisuals
        opacity: 0.86

        Image {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            source: Qt.resolvedUrl("icons/search.svg")
            sourceSize.width: 36
            sourceSize.height: 36
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    Text {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.textLeftInset
            rightMargin: root.textRightInset
        }
        visible: root.showVisuals && !root.visualInteractive
        text: root.queryText.length > 0 ? root.queryText : "Search applications"
        color: root.queryText.length > 0 ? "#f5f8fb" : "#7f8b96"
        font.family: "Nunito"
        font.pixelSize: root.searchFontSize
        font.weight: Font.Medium
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        renderType: Text.QtRendering
        font.hintingPreference: Font.PreferNoHinting
        font.kerning: true
    }

    TextInput {
        id: searchInput
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.textLeftInset
            rightMargin: root.textRightInset
        }
        visible: root.visualInteractive
        opacity: root.showVisuals ? 1 : 0
        enabled: root.interactive
        text: root.queryText
        color: "#f5f8fb"
        selectionColor: "#55ffffff"
        selectedTextColor: "#0b1018"
        font.family: "Nunito"
        font.pixelSize: root.searchFontSize
        font.weight: Font.Medium
        renderType: Text.QtRendering
        font.hintingPreference: Font.PreferNoHinting
        font.kerning: true
        clip: true
        cursorVisible: root.interactive && searchInput.activeFocus

        onTextEdited: root.queryEdited(text)

        onActiveFocusChanged: {
            if (!activeFocus)
                root.clearPendingKeyboardActivation();
        }

        Text {
            anchors.fill: parent
            visible: searchInput.text.length === 0
            text: "Search applications"
            color: "#7f8b96"
            font.family: "Nunito"
            font.pixelSize: searchInput.font.pixelSize
            font.weight: Font.Medium
            verticalAlignment: Text.AlignVCenter
            renderType: Text.QtRendering
            font.hintingPreference: Font.PreferNoHinting
            font.kerning: true
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Do not launch on key press. If the overview closes while the
                // physical Enter key is still down, the newly focused client can
                // inherit the pressed/repeating state. Arm activation here and
                // launch only after the release event is consumed by Quickshell.
                event.accepted = true;
                if (!event.isAutoRepeat)
                    root.enterActivationPending = true;
                return;
            }

            if (event.key === Qt.Key_Left) {
                root.moveSelectionRequested("left");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Right) {
                root.moveSelectionRequested("right");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Up) {
                root.moveSelectionRequested("up");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Down) {
                root.moveSelectionRequested("down");
                event.accepted = true;
                return;
            }
        }

        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                var shouldActivate = root.enterActivationPending && root.interactive && !event.isAutoRepeat;
                root.enterActivationPending = false;
                event.accepted = true;
                if (shouldActivate)
                    root.activateSelectionRequested();
                return;
            }
        }

        Keys.onEscapePressed: {
            root.clearPendingKeyboardActivation();
            Services.ShellActions.closeWorkspaceOverview();
        }
    }
}
