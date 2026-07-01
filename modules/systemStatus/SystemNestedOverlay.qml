import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    required property var popupRoot
    required property var popupController
    required property var motionTokens

    property string renderedDetailMode: ""
    property string renderedConfirmActionName: ""
    property string renderedConfirmActionLabel: ""

    readonly property bool targetVisible: popupController.nestedOverlayVisible
    readonly property bool confirmMode: renderedConfirmActionName.length > 0
    readonly property real reveal: nestedState.reveal
    readonly property real contentReveal: Math.max(0, Math.min(1, (reveal - 0.12) / 0.88))
    readonly property int cardPadding: 16

    function refreshRenderedState() {
        if (!targetVisible)
            return;

        renderedDetailMode = String(popupController.detailMode || "");
        renderedConfirmActionName = String(popupController.confirmActionName || "");
        renderedConfirmActionLabel = String(popupController.confirmActionLabel || "");
    }

    function clearRenderedState() {
        if (targetVisible)
            return;

        renderedDetailMode = "";
        renderedConfirmActionName = "";
        renderedConfirmActionLabel = "";
    }

    function detailIcon() {
        if (renderedDetailMode === "wifi")
            return popupRoot.wifiIcon();
        if (renderedDetailMode === "bluetooth")
            return popupRoot.rowIcon("bluetooth");
        return popupRoot.rowIcon("ethernet");
    }

    function detailTitle() {
        if (renderedDetailMode === "wifi")
            return "Wi-Fi networks";
        if (renderedDetailMode === "ethernet")
            return "Ethernet details";
        if (renderedDetailMode === "bluetooth")
            return "Bluetooth devices";
        return "System details";
    }

    function detailEmptyText() {
        if (renderedDetailMode === "wifi")
            return Services.SystemStatus.wifiEnabled ? "No networks found" : "Wi-Fi is off";
        if (renderedDetailMode === "bluetooth")
            return Services.SystemStatus.bluetoothEnabled ? "No devices found" : "Bluetooth is off";
        return "No data available";
    }

    function confirmationText() {
        return "Are you sure you want to\n" + (renderedConfirmActionLabel || "continue") + "?";
    }

    anchors.fill: parent
    radius: 18
    visible: nestedState.renderVisible
    enabled: nestedState.inputEnabled
    opacity: reveal
    color: "#a0000000"
    border.width: 0
    antialiasing: true
    z: 50

    onTargetVisibleChanged: {
        if (targetVisible)
            refreshRenderedState();
    }

    Connections {
        target: popupController

        function onDetailModeChanged() {
            root.refreshRenderedState();
        }

        function onConfirmActionNameChanged() {
            root.refreshRenderedState();
        }

        function onConfirmActionLabelChanged() {
            root.refreshRenderedState();
        }
    }

    Components.AnimatedPopupState {
        id: nestedState
        targetVisible: root.targetVisible
        openDuration: root.motionTokens.systemNestedOpenDuration
        closeDuration: root.motionTokens.systemNestedCloseDuration
        closeSafetyDelay: closeDuration + 70
        onClosed: root.clearRenderedState()
    }

    MouseArea {
        id: nestedOverlayMouseBlocker
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        preventStealing: true
        cursorShape: Qt.ArrowCursor

        onPressed: function (mouse) {
            mouse.accepted = true;
        }

        onReleased: function (mouse) {
            mouse.accepted = true;
        }

        onWheel: function (wheel) {
            wheel.accepted = true;
        }

        onClicked: function (mouse) {
            mouse.accepted = true;
            if (mouse.button !== Qt.LeftButton)
                return;

            if (root.confirmMode)
                popupController.cancelSystemActionConfirm();
            else
                popupController.closeDetailPopup();
        }
    }

    Rectangle {
        id: nestedCard

        width: Math.min(parent.width - 38, 322)
        height: root.confirmMode ? confirmColumn.implicitHeight + 28 : detailColumn.implicitHeight + 28
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2 - (1.0 - root.reveal) * root.motionTokens.systemNestedCardOffsetY
        radius: 18
        color: "#f0000000"
        border.width: 1
        border.color: "#24000000"
        antialiasing: true
        clip: true
        opacity: root.contentReveal
        scale: root.motionTokens.systemNestedCardStartScale + root.reveal * (1.0 - root.motionTokens.systemNestedCardStartScale)
        transformOrigin: Item.Center

        Behavior on height {
            NumberAnimation {
                duration: root.motionTokens.workspaceMorphDuration
                easing.type: root.motionTokens.workspaceMorphEasing
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            preventStealing: true
            cursorShape: Qt.ArrowCursor

            onPressed: function (mouse) {
                mouse.accepted = true;
            }

            onReleased: function (mouse) {
                mouse.accepted = true;
            }

            onWheel: function (wheel) {
                wheel.accepted = true;
            }

            onClicked: function (mouse) {
                mouse.accepted = true;
            }
        }

        Column {
            id: confirmColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: root.cardPadding
            anchors.rightMargin: root.cardPadding
            spacing: 12
            visible: root.confirmMode
            opacity: root.confirmMode ? 1.0 : 0.0

            Components.StyledText {
                width: parent.width
                text: root.confirmationText()
                color: "#f4f7fb"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.NoWrap
                maximumLineCount: 2
            }

            RowLayout {
                width: parent.width
                height: 30
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 13
                    color: acceptConfirmMouse.pressed ? "#36ffffff" : (acceptConfirmMouse.containsMouse ? "#2fffffff" : "#1cffffff")
                    border.width: 0
                    antialiasing: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.motionTokens.hoverDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    Components.StyledText {
                        anchors.centerIn: parent
                        text: "Confirm"
                        color: "#f4f7fb"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: acceptConfirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popupController.runConfirmedSystemAction()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 13
                    color: cancelConfirmMouse.pressed ? "#2c000000" : (cancelConfirmMouse.containsMouse ? "#26000000" : "#1a000000")
                    border.width: 0
                    antialiasing: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.motionTokens.hoverDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    Components.StyledText {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: "#eef3f8"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: cancelConfirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popupController.cancelSystemActionConfirm()
                    }
                }
            }
        }

        Column {
            id: detailColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10
            visible: !root.confirmMode && root.renderedDetailMode.length > 0
            opacity: visible ? 1.0 : 0.0

            RowLayout {
                width: parent.width
                height: 26
                spacing: 8

                SystemIcon {
                    source: root.detailIcon()
                    iconOpacity: 0.9
                }

                Components.StyledText {
                    Layout.fillWidth: true
                    text: root.detailTitle()
                    color: "#f4f7fb"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: closeDetailMouse.pressed ? "#2c000000" : (closeDetailMouse.containsMouse ? "#26000000" : "transparent")
                    border.width: 0
                    antialiasing: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.motionTokens.hoverDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    SystemIcon {
                        anchors.centerIn: parent
                        source: popupRoot.rowIcon("x")
                        iconOpacity: 0.72
                    }

                    MouseArea {
                        id: closeDetailMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popupController.closeDetailPopup()
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 8
                visible: root.renderedDetailMode === "ethernet"

                Components.StyledText {
                    width: parent.width
                    text: Services.SystemStatus.ethernetActive ? "Ethernet is active" : "Ethernet is disconnected"
                    color: "#eef3f8"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Components.StyledText {
                    width: parent.width
                    text: popupRoot.ethernetText()
                    color: "#aeb8c6"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Flickable {
                width: parent.width
                height: root.renderedDetailMode === "wifi" ? Math.min(190, Math.max(38, wifiDetailColumn.implicitHeight)) : 0
                visible: root.renderedDetailMode === "wifi"
                clip: true
                contentWidth: width
                contentHeight: wifiDetailColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: wifiDetailColumn
                    width: parent.width
                    spacing: 6

                    Components.StyledText {
                        width: parent.width
                        height: root.renderedDetailMode === "wifi" && Services.SystemStatus.wifiNetworks.length === 0 ? 36 : 0
                        visible: root.renderedDetailMode === "wifi" && Services.SystemStatus.wifiNetworks.length === 0
                        text: root.detailEmptyText()
                        color: "#aeb8c6"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    Repeater {
                        model: root.renderedDetailMode === "wifi" ? Services.SystemStatus.wifiNetworks : []

                        delegate: SystemWifiNetworkRow {
                            popupRoot: root.popupRoot
                            popupController: root.popupController
                            motionTokens: root.motionTokens
                        }
                    }
                }
            }

            Flickable {
                width: parent.width
                height: root.renderedDetailMode === "bluetooth" ? Math.min(178, Math.max(38, bluetoothDetailColumn.implicitHeight)) : 0
                visible: root.renderedDetailMode === "bluetooth"
                clip: true
                contentWidth: width
                contentHeight: bluetoothDetailColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: bluetoothDetailColumn
                    width: parent.width
                    spacing: 6

                    Components.StyledText {
                        width: parent.width
                        height: root.renderedDetailMode === "bluetooth" && Services.SystemStatus.bluetoothDevices.length === 0 ? 36 : 0
                        visible: root.renderedDetailMode === "bluetooth" && Services.SystemStatus.bluetoothDevices.length === 0
                        text: root.detailEmptyText()
                        color: "#aeb8c6"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    Repeater {
                        model: root.renderedDetailMode === "bluetooth" ? Services.SystemStatus.bluetoothDevices : []

                        delegate: SystemBluetoothDeviceRow {
                            popupRoot: root.popupRoot
                            motionTokens: root.motionTokens
                        }
                    }
                }
            }
        }
    }
}
