import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

PopupWindow {
    id: root

    property var controller: null
    property var hostWindow: null
    property real popupX: 0
    property real popupY: 44
    property bool targetVisible: controller ? controller.popupOpen : false
    property real reveal: popupState.reveal

    readonly property int contentRows: Math.max(1, Services.KeyboardLayoutService.layouts.length)
    readonly property int rowHeight: 28
    readonly property int rowSpacing: 5
    readonly property int outerMargin: 10
    readonly property int listPadding: 8

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    anchor.window: hostWindow
    anchor.rect.x: popupX
    anchor.rect.y: popupY
    implicitWidth: 216
    implicitHeight: Math.min(220, outerMargin * 2 + listPadding * 2 + contentRows * rowHeight + Math.max(0, contentRows - 1) * rowSpacing)
    visible: popupState.renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: root.targetVisible
        onActivated: {
            if (root.controller)
                root.controller.closePopup();
        }
    }

    onTargetVisibleChanged: {
        if (targetVisible)
            Services.KeyboardLayoutService.requestLayouts();
    }

    Components.AnimatedPopupState {
        id: popupState
        targetVisible: root.targetVisible
        openDuration: 350
        closeDuration: 270
        closeSafetyDelay: 340
    }

    Components.AnimationTokens { id: motion }

    Item {
        id: popupMotionLayer
        anchors.fill: parent
        opacity: root.reveal
        y: -9 + root.reveal * 9
        scale: 0.972 + root.reveal * 0.028
        transformOrigin: Item.Top
        enabled: root.targetVisible && root.reveal > 0.45
        layer.enabled: root.reveal > 0.001 && root.reveal < 0.999
        layer.smooth: true

        Components.GlassPanel {
            id: panel
            anchors.fill: parent
            radiusSize: 18
            glassColor: "#b010131a"
            clip: true
            antialiasing: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: popupMouse.pressed ? "#08ffffff" : "transparent"
            border.width: 0
            antialiasing: true

            Behavior on color {
                ColorAnimation { duration: popupMouse.pressed ? motion.pressDuration : motion.releaseDuration; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            id: popupMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onClicked: function(mouse) { mouse.accepted = true; }
        }

        Rectangle {
            id: layoutListPanel
            anchors.fill: parent
            anchors.margins: root.outerMargin
            radius: 16
            color: "#1019232f"
            border.width: 0
            antialiasing: true
            opacity: root.clamp01((root.reveal - 0.10) / 0.90)

            Column {
                anchors.fill: parent
                anchors.margins: root.listPadding
                spacing: root.rowSpacing

                Components.StyledText {
                    width: parent.width
                    visible: Services.KeyboardLayoutService.layouts.length === 0
                    height: visible ? root.rowHeight : 0
                    text: "Раскладки не найдены"
                    color: "#aeb8c6"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: Services.KeyboardLayoutService.layouts

                    delegate: Rectangle {
                        required property var modelData

                        readonly property bool activeLayout: modelData.code === Services.KeyboardLayoutService.currentLayout

                        width: parent.width
                        height: root.rowHeight
                        radius: 12
                        color: activeLayout
                            ? "#24ffffff"
                            : (layoutMouse.pressed ? "#22ffffff" : (layoutMouse.containsMouse ? "#14ffffff" : "transparent"))
                        border.width: 0
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 8

                            Components.StyledText {
                                text: modelData.code
                                color: activeLayout ? "#f4f7fb" : "#d9e0ea"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Components.StyledText {
                                Layout.fillWidth: true
                                text: modelData.raw
                                color: activeLayout ? "#b9c3d0" : "#8f9aa8"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Components.StyledText {
                                text: activeLayout ? "активно" : ""
                                color: "#8f9aa8"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: layoutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (!parent.activeLayout)
                                    Services.KeyboardLayoutService.switchToLayout(modelData.index);

                                if (root.controller)
                                    root.controller.closePopup();
                            }
                        }
                    }
                }
            }
        }
    }
}
