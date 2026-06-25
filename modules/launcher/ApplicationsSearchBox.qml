import QtQuick
import "../../components" as Components
import "../../services" as Services

Item {
    id: root

    required property bool interactive
    required property bool showVisuals
    property string queryText: ""
    property bool hidePointerCursor: false
    property var pointerMovedCallback: null
    property alias inputField: searchInput

    readonly property int horizontalPadding: 14
    readonly property int iconSize: 15
    readonly property int iconWidth: 18
    readonly property int textLeftInset: 42
    readonly property int textRightInset: 15
    readonly property int searchFontSize: 12

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

    opacity: showVisuals ? 1 : 0
    visible: showVisuals || interactive

    Components.GlassPanel {
        id: searchBackground
        anchors.fill: parent
        radiusSize: Math.round(height / 2)
        glassColor: "#b006080c"
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
        opacity: 0.9

        Rectangle {
            id: searchIconRing
            width: root.iconSize - 4
            height: width
            x: 1
            y: 1
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: "#b8c3cf"
            antialiasing: true
        }

        Rectangle {
            width: Math.max(6, Math.round(root.iconSize * 0.42))
            height: 2
            x: searchIconRing.x + searchIconRing.width - 1
            y: searchIconRing.y + searchIconRing.height - 1
            radius: 1
            color: "#b8c3cf"
            antialiasing: true
            transformOrigin: Item.Left
            rotation: 45
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
        visible: root.showVisuals && !root.interactive
        text: root.queryText.length > 0 ? root.queryText : "Search applications"
        color: root.queryText.length > 0 ? "#f5f8fb" : "#7f8b96"
        font.pixelSize: root.searchFontSize
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
            leftMargin: root.textLeftInset
            rightMargin: root.textRightInset
        }
        visible: root.interactive
        opacity: root.showVisuals ? 1 : 0
        enabled: root.interactive
        text: root.queryText
        color: "#f5f8fb"
        selectionColor: "#55ffffff"
        selectedTextColor: "#0b1018"
        font.pixelSize: root.searchFontSize
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
