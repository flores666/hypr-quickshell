import QtQuick
import "../../services" as Services

Rectangle {
    id: root

    required property bool interactive
    required property bool showVisuals
    property string queryText: ""
    property bool hidePointerCursor: false
    property var pointerMovedCallback: null
    property alias inputField: searchInput

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

    radius: 24
    color: showVisuals ? "#da111821" : "transparent"
    border.width: showVisuals ? 1 : 0
    border.color: "#22ffffff"
    antialiasing: true

    HoverHandler {
        enabled: root.interactive
        cursorShape: root.hidePointerCursor ? Qt.BlankCursor : Qt.IBeamCursor
        onPointChanged: root.notifyPointerMoved()
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showVisuals
        text: "⌕"
        color: "#b8c3cf"
        font.pixelSize: 18
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        font.kerning: false
    }

    Text {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 52
            rightMargin: 22
        }
        visible: root.showVisuals && !root.interactive
        text: root.queryText.length > 0 ? root.queryText : "Search applications"
        color: root.queryText.length > 0 ? "#f5f8fb" : "#7f8b96"
        font.pixelSize: 16
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        font.kerning: false
    }

    TextInput {
        id: searchInput
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 52
            rightMargin: 22
        }
        visible: root.interactive
        opacity: root.showVisuals ? 1 : 0
        enabled: root.interactive
        text: root.queryText
        color: "#f5f8fb"
        selectionColor: "#55ffffff"
        selectedTextColor: "#0b1018"
        font.pixelSize: 16
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        font.kerning: false
        clip: true

        onTextEdited: root.queryEdited(text)

        Text {
            anchors.fill: parent
            visible: searchInput.text.length === 0
            text: "Search applications"
            color: "#7f8b96"
            font.pixelSize: searchInput.font.pixelSize
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activateSelectionRequested();
                event.accepted = true;
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

        Keys.onEscapePressed: Services.ShellActions.closeWorkspaceOverview()
    }
}
