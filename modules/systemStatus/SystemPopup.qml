import Quickshell
import QtQuick
import QtQuick.Window
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
    property string detailMode: ""

    readonly property real popupBottomMargin: 2
    readonly property real maxPopupHeight: Math.max(180, Screen.height - popupY - popupBottomMargin)
    readonly property real contentPopupHeight: contentColumn.implicitHeight + 32

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function rowIcon(name) {
        return Qt.resolvedUrl("icons/" + name + ".svg");
    }

    function wifiIcon() {
        if (!Services.SystemStatus.hasWifi || !Services.SystemStatus.wifiEnabled)
            return rowIcon("wifi-off");
        if (Services.SystemStatus.networkState === "connecting")
            return rowIcon("wifi-connecting");
        if (Services.SystemStatus.networkType === "wifi" && Services.SystemStatus.networkState === "connected") {
            var signal = Services.SystemStatus.wifiSignal;
            if (signal <= 25)
                return rowIcon("wifi-0");
            if (signal <= 45)
                return rowIcon("wifi-1");
            if (signal <= 70)
                return rowIcon("wifi-2");
            return rowIcon("wifi-3");
        }
        return rowIcon("wifi-1");
    }

    function volumeIcon() {
        if (!Services.SystemStatus.hasAudio)
            return rowIcon("volume-none");
        if (Services.SystemStatus.muted || Services.SystemStatus.volume <= 0)
            return rowIcon("volume-muted");
        if (Services.SystemStatus.volume <= 33)
            return rowIcon("volume-low");
        if (Services.SystemStatus.volume <= 66)
            return rowIcon("volume-medium");
        return rowIcon("volume-high");
    }

    function audioTitle() {
        if (!Services.SystemStatus.hasAudio)
            return "Аудиоустройство недоступно";
        if (Services.SystemStatus.muted)
            return "Звук заглушен";
        return "System volume";
    }

    function ethernetText() {
        if (!Services.SystemStatus.hasEthernet)
            return "Ethernet недоступен";
        if (Services.SystemStatus.ethernetActive)
            return (Services.SystemStatus.ethernetConnection || "Ethernet") + (Services.SystemStatus.ethernetIp !== "" ? " · " + Services.SystemStatus.ethernetIp : "");
        return Services.SystemStatus.ethernetDevice !== "" ? Services.SystemStatus.ethernetDevice + " · кабель не подключен" : "Кабель не подключен";
    }

    function batteryLine() {
        if (!Services.SystemStatus.hasBattery)
            return "";
        var parts = [Services.SystemStatus.batteryPercent + "%"];
        if (Services.SystemStatus.batteryStatus === "full")
            parts.push("заряжено");
        else if (Services.SystemStatus.batteryCharging)
            parts.push("заряжается");
        else
            parts.push("разряжается");
        if (Services.SystemStatus.batteryTime !== "")
            parts.push(Services.SystemStatus.batteryTime);
        return parts.join(" · ");
    }

    anchor.window: hostWindow
    anchor.rect.x: popupX
    anchor.rect.y: popupY
    implicitWidth: 398
    implicitHeight: Math.min(maxPopupHeight, Math.max(260, contentPopupHeight))
    visible: popupState.renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    onTargetVisibleChanged: {
        if (targetVisible)
            Services.SystemStatus.requestRefresh();
        else
            detailMode = "";
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

        Flickable {
            id: contentFlick
            anchors.fill: parent
            anchors.margins: 16
            clip: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            opacity: root.clamp01((root.reveal - 0.10) / 0.90)

            Column {
                id: contentColumn
                width: contentFlick.width
                spacing: 12

                RowLayout {
                    width: parent.width
                    height: 44
                    spacing: 9

                    Repeater {
                        model: [
                            { action: "poweroff", icon: "power", label: "Выключение" },
                            { action: "reboot", icon: "reboot", label: "Перезагрузка" },
                            { action: "logout", icon: "logout", label: "Выход" }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 15
                            color: actionMouse.pressed ? "#28ffffff" : (actionMouse.containsMouse ? "#18ffffff" : "#1019232f")
                            border.width: 0
                            antialiasing: true

                            Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                            SystemIcon {
                                anchors.centerIn: parent
                                source: root.rowIcon(modelData.icon)
                                iconOpacity: actionMouse.containsMouse ? 1.0 : 0.82
                            }

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SystemStatus.systemAction(modelData.action)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: wirelessColumn.implicitHeight + 22
                    radius: 16
                    color: "#1019232f"
                    border.width: 0
                    antialiasing: true

                    Column {
                        id: wirelessColumn
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 42
                            spacing: 9

                            Rectangle {
                                visible: Services.SystemStatus.hasWifi
                                Layout.fillWidth: visible
                                Layout.preferredHeight: 42
                                radius: 14
                                color: wifiMouse.pressed ? "#28ffffff" : (wifiMouse.containsMouse || root.detailMode === "wifi" ? "#18ffffff" : (Services.SystemStatus.wifiEnabled ? "#16ffffff" : "#0dffffff"))
                                opacity: Services.SystemStatus.wifiEnabled ? 1.0 : 0.58
                                border.width: 0
                                antialiasing: true

                                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon { source: root.wifiIcon(); iconOpacity: 0.95 }

                                    Components.StyledText {
                                        text: "Wi-Fi"
                                        color: "#eef3f8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: wifiMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton)
                                            root.detailMode = root.detailMode === "wifi" ? "" : "wifi";
                                        else
                                            Services.SystemStatus.toggleWifi();
                                        mouse.accepted = true;
                                    }
                                }
                            }

                            Rectangle {
                                visible: Services.SystemStatus.hasEthernet
                                Layout.fillWidth: visible
                                Layout.preferredHeight: 42
                                radius: 14
                                color: ethernetMouse.pressed ? "#28ffffff" : (ethernetMouse.containsMouse || root.detailMode === "ethernet" ? "#18ffffff" : (Services.SystemStatus.ethernetActive ? "#16ffffff" : "#0dffffff"))
                                opacity: Services.SystemStatus.ethernetActive ? 1.0 : 0.55
                                border.width: 0
                                antialiasing: true

                                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon { source: root.rowIcon("ethernet"); iconOpacity: 0.95 }

                                    Components.StyledText {
                                        text: "Ethernet"
                                        color: "#eef3f8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: ethernetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.detailMode = root.detailMode === "ethernet" ? "" : "ethernet"
                                }
                            }

                            Rectangle {
                                visible: Services.SystemStatus.hasBluetooth
                                Layout.fillWidth: visible
                                Layout.preferredHeight: 42
                                radius: 14
                                color: bluetoothMouse.pressed ? "#28ffffff" : (bluetoothMouse.containsMouse || root.detailMode === "bluetooth" ? "#18ffffff" : (Services.SystemStatus.bluetoothEnabled ? "#16ffffff" : "#0dffffff"))
                                opacity: Services.SystemStatus.bluetoothEnabled ? 1.0 : 0.58
                                border.width: 0
                                antialiasing: true

                                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon { source: root.rowIcon("bluetooth"); iconOpacity: 0.95 }

                                    Components.StyledText {
                                        text: "Bluetooth"
                                        color: "#eef3f8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: bluetoothMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton)
                                            root.detailMode = root.detailMode === "bluetooth" ? "" : "bluetooth";
                                        else
                                            Services.SystemStatus.toggleBluetooth();
                                        mouse.accepted = true;
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: root.detailMode === "wifi" ? 158 : 0
                            visible: root.detailMode === "wifi"
                            radius: 14
                            color: "#0bffffff"
                            border.width: 0
                            antialiasing: true
                            clip: true

                            Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }

                            Flickable {
                                anchors.fill: parent
                                anchors.margins: 7
                                contentWidth: width
                                contentHeight: wifiListColumn.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: wifiListColumn
                                    width: parent.width
                                    spacing: 5

                                    Components.StyledText {
                                        width: parent.width
                                        height: Services.SystemStatus.wifiNetworks.length === 0 ? 28 : 0
                                        visible: Services.SystemStatus.wifiNetworks.length === 0
                                        text: Services.SystemStatus.wifiEnabled ? "Сети не найдены" : "Wi-Fi выключен"
                                        color: "#aeb8c6"
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    Repeater {
                                        model: Services.SystemStatus.wifiNetworks
                                        delegate: Rectangle {
                                            required property var modelData

                                            width: parent.width
                                            height: 28
                                            radius: 12
                                            color: wifiItemMouse.pressed ? "#22ffffff" : (wifiItemMouse.containsMouse ? "#14ffffff" : (modelData.active ? "#1cffffff" : "transparent"))
                                            border.width: 0
                                            antialiasing: true

                                            Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 8

                                                SystemIcon {
                                                    source: modelData.signal <= 25 ? root.rowIcon("wifi-0") : (modelData.signal <= 45 ? root.rowIcon("wifi-1") : (modelData.signal <= 70 ? root.rowIcon("wifi-2") : root.rowIcon("wifi-3")))
                                                    iconOpacity: modelData.active ? 1.0 : 0.72
                                                }

                                                Components.StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData.ssid || "Wi-Fi"
                                                    color: modelData.active ? "#f4f7fb" : "#c4ceda"
                                                    font.pixelSize: 11
                                                    font.weight: modelData.active ? Font.DemiBold : Font.Medium
                                                    elide: Text.ElideRight
                                                }

                                                Components.StyledText {
                                                    text: modelData.active ? "активно" : (modelData.signal + "%")
                                                    color: "#8f9aa8"
                                                    font.pixelSize: 10
                                                }
                                            }

                                            MouseArea {
                                                id: wifiItemMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (!modelData.active)
                                                        Services.SystemStatus.connectWifi(modelData.ssid);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: root.detailMode === "ethernet" ? 58 : 0
                            visible: root.detailMode === "ethernet"
                            radius: 14
                            color: "#0bffffff"
                            border.width: 0
                            antialiasing: true
                            clip: true

                            Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 3

                                Components.StyledText {
                                    width: parent.width
                                    text: Services.SystemStatus.ethernetActive ? "Ethernet активен" : "Ethernet не подключен"
                                    color: "#eef3f8"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Components.StyledText {
                                    width: parent.width
                                    text: root.ethernetText()
                                    color: "#aeb8c6"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: root.detailMode === "bluetooth" ? 136 : 0
                            visible: root.detailMode === "bluetooth"
                            radius: 14
                            color: "#0bffffff"
                            border.width: 0
                            antialiasing: true
                            clip: true

                            Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }

                            Flickable {
                                anchors.fill: parent
                                anchors.margins: 7
                                contentWidth: width
                                contentHeight: bluetoothListColumn.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: bluetoothListColumn
                                    width: parent.width
                                    spacing: 5

                                    Components.StyledText {
                                        width: parent.width
                                        height: Services.SystemStatus.bluetoothDevices.length === 0 ? 28 : 0
                                        visible: Services.SystemStatus.bluetoothDevices.length === 0
                                        text: Services.SystemStatus.bluetoothEnabled ? "Устройства не найдены" : "Bluetooth выключен"
                                        color: "#aeb8c6"
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    Repeater {
                                        model: Services.SystemStatus.bluetoothDevices
                                        delegate: Rectangle {
                                            required property var modelData

                                            width: parent.width
                                            height: 28
                                            radius: 12
                                            color: bluetoothItemMouse.pressed ? "#22ffffff" : (bluetoothItemMouse.containsMouse ? "#14ffffff" : (modelData.connected ? "#1cffffff" : "transparent"))
                                            border.width: 0
                                            antialiasing: true

                                            Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 8

                                                SystemIcon { source: root.rowIcon("bluetooth"); iconOpacity: modelData.connected ? 1.0 : 0.62 }

                                                Components.StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData.name || "Bluetooth"
                                                    color: modelData.connected ? "#f4f7fb" : "#c4ceda"
                                                    font.pixelSize: 11
                                                    font.weight: modelData.connected ? Font.DemiBold : Font.Medium
                                                    elide: Text.ElideRight
                                                }

                                                Components.StyledText {
                                                    text: modelData.connected ? "подключено" : ""
                                                    color: "#8f9aa8"
                                                    font.pixelSize: 10
                                                }
                                            }

                                            MouseArea {
                                                id: bluetoothItemMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.SystemStatus.toggleBluetoothDevice(modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 244
                    radius: 16
                    color: "#1019232f"
                    border.width: 0
                    antialiasing: true
                    clip: true

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 10

                            SystemIcon { source: root.volumeIcon(); iconOpacity: 0.95 }

                            Components.StyledText {
                                Layout.fillWidth: true
                                text: root.audioTitle()
                                color: "#eef3f8"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Components.StyledText {
                                text: Services.SystemStatus.hasAudio ? Services.SystemStatus.volume + "%" : "--"
                                color: "#aeb8c6"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }

                            Rectangle {
                                width: 54
                                height: 24
                                radius: 12
                                color: muteMouse.pressed ? "#26ffffff" : (muteMouse.containsMouse ? "#18ffffff" : "#12ffffff")
                                border.width: 0
                                antialiasing: true
                                opacity: Services.SystemStatus.hasAudio ? 1.0 : 0.45

                                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                Components.StyledText {
                                    anchors.centerIn: parent
                                    text: Services.SystemStatus.muted ? "unmute" : "mute"
                                    color: "#eef3f8"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: muteMouse
                                    anchors.fill: parent
                                    enabled: Services.SystemStatus.hasAudio
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemStatus.toggleMute()
                                }
                            }
                        }

                        SystemSlider {
                            width: parent.width
                            value: Services.SystemStatus.volume
                            minValue: 0
                            maxValue: 100
                            opacity: Services.SystemStatus.hasAudio ? 1.0 : 0.38
                            onValueCommitted: function(value) {
                                if (Services.SystemStatus.hasAudio)
                                    Services.SystemStatus.setVolume(value);
                            }
                        }

                        Flickable {
                            width: parent.width
                            height: 76
                            clip: true
                            contentWidth: width
                            contentHeight: appVolumeColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: appVolumeColumn
                                width: parent.width
                                spacing: 5

                                Components.StyledText {
                                    width: parent.width
                                    height: Services.SystemStatus.sinkInputs.length === 0 ? 24 : 0
                                    visible: Services.SystemStatus.sinkInputs.length === 0
                                    text: "Нет активных аудио-приложений"
                                    color: "#8f9aa8"
                                    font.pixelSize: 10
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Repeater {
                                    model: Services.SystemStatus.sinkInputs
                                    delegate: RowLayout {
                                        required property var modelData

                                        width: parent.width
                                        height: 31
                                        spacing: 8

                                        Rectangle {
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: "#18ffffff"
                                            border.width: 0
                                            antialiasing: true

                                            Components.StyledText {
                                                anchors.centerIn: parent
                                                text: (modelData.name || "A").substring(0, 1).toUpperCase()
                                                color: "#eef3f8"
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Components.StyledText {
                                            Layout.preferredWidth: 92
                                            text: modelData.name || "App"
                                            color: "#c4ceda"
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }

                                        SystemSlider {
                                            Layout.fillWidth: true
                                            value: modelData.volume || 0
                                            minValue: 0
                                            maxValue: 100
                                            onValueCommitted: function(value) {
                                                Services.SystemStatus.setAppVolume(modelData.index, value);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Flickable {
                            width: parent.width
                            height: 66
                            clip: true
                            contentWidth: width
                            contentHeight: outputColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: outputColumn
                                width: parent.width
                                spacing: 5

                                Repeater {
                                    model: Services.SystemStatus.audioDevices
                                    delegate: Rectangle {
                                        required property var modelData

                                        width: parent.width
                                        height: 28
                                        radius: 12
                                        color: deviceMouse.pressed ? "#22ffffff" : (deviceMouse.containsMouse ? "#14ffffff" : (modelData.active ? "#1cffffff" : "transparent"))
                                        border.width: 0
                                        antialiasing: true

                                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8

                                            Components.StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.label || modelData.name || "Audio device"
                                                color: modelData.active ? "#f4f7fb" : "#c4ceda"
                                                font.pixelSize: 11
                                                font.weight: modelData.active ? Font.DemiBold : Font.Medium
                                                elide: Text.ElideRight
                                            }

                                            Components.StyledText {
                                                text: modelData.active ? "активно" : ""
                                                color: "#8f9aa8"
                                                font.pixelSize: 10
                                            }
                                        }

                                        MouseArea {
                                            id: deviceMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!modelData.active)
                                                    Services.SystemStatus.setSink(modelData.name);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 374
                    radius: 16
                    color: "#1019232f"
                    border.width: 0
                    antialiasing: true
                    clip: true

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 24
                            spacing: 8

                            SystemIcon { source: root.rowIcon("bell"); iconOpacity: 0.88 }

                            Components.StyledText {
                                Layout.fillWidth: true
                                text: "Уведомления"
                                color: "#eef3f8"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Components.StyledText {
                                text: Services.SystemStatus.notificationsCount + ""
                                color: "#aeb8c6"
                                font.pixelSize: 11
                            }
                        }

                        Flickable {
                            width: parent.width
                            height: 292
                            clip: true
                            contentWidth: width
                            contentHeight: notificationColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: notificationColumn
                                width: parent.width
                                spacing: 7

                                Components.StyledText {
                                    width: parent.width
                                    height: Services.SystemStatus.notifications.length === 0 ? 50 : 0
                                    visible: Services.SystemStatus.notifications.length === 0
                                    text: "Нет уведомлений"
                                    color: "#8f9aa8"
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Repeater {
                                    model: Services.SystemStatus.notifications
                                    delegate: Rectangle {
                                        required property var modelData

                                        width: parent.width
                                        height: Math.max(68, notificationTextColumn.implicitHeight + 20)
                                        radius: 15
                                        color: notificationMouse.pressed ? "#20ffffff" : (notificationMouse.containsMouse ? "#16ffffff" : "#0dffffff")
                                        border.width: 0
                                        antialiasing: true

                                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            z: 1
                                            anchors.fill: parent
                                            anchors.margins: 9
                                            spacing: 9

                                            Rectangle {
                                                Layout.alignment: Qt.AlignTop
                                                width: 30
                                                height: 30
                                                radius: 15
                                                color: "#18ffffff"
                                                border.width: 0
                                                antialiasing: true

                                                Components.StyledText {
                                                    anchors.centerIn: parent
                                                    text: (modelData.app || "N").substring(0, 1).toUpperCase()
                                                    color: "#eef3f8"
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            Column {
                                                id: notificationTextColumn
                                                Layout.fillWidth: true
                                                spacing: 2

                                                RowLayout {
                                                    width: parent.width
                                                    height: 16

                                                    Components.StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData.app || "Notification"
                                                        color: "#d9e0ea"
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }

                                                    Components.StyledText {
                                                        text: modelData.time || ""
                                                        color: "#8f9aa8"
                                                        font.pixelSize: 9
                                                    }
                                                }

                                                Components.StyledText {
                                                    width: parent.width
                                                    text: modelData.title || "Уведомление"
                                                    color: "#f4f7fb"
                                                    font.pixelSize: 11
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }

                                                Components.StyledText {
                                                    width: parent.width
                                                    text: modelData.body || ""
                                                    color: "#aeb8c6"
                                                    font.pixelSize: 10
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                z: 2
                                                Layout.alignment: Qt.AlignTop
                                                width: 22
                                                height: 22
                                                radius: 11
                                                color: closeNotificationMouse.pressed ? "#24ffffff" : (closeNotificationMouse.containsMouse ? "#18ffffff" : "transparent")
                                                border.width: 0
                                                antialiasing: true

                                                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                                SystemIcon { anchors.centerIn: parent; source: root.rowIcon("x"); iconOpacity: 0.78 }

                                                MouseArea {
                                                    id: closeNotificationMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Services.SystemStatus.closeNotification(modelData.id)
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: notificationMouse
                                            anchors.fill: parent
                                            z: 0
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton
                                            cursorShape: Qt.PointingHandCursor

                                            onClicked: {
                                                Services.SystemStatus.openNotification(modelData);
                                                if (root.controller)
                                                    root.controller.closePopup();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 8

                            Components.StyledText {
                                Layout.fillWidth: true
                                text: Services.SystemStatus.notificationsCount + " notifications"
                                color: "#8f9aa8"
                                font.pixelSize: 10
                                verticalAlignment: Text.AlignVCenter
                            }

                            Rectangle {
                                width: 58
                                height: 24
                                radius: 12
                                color: silentMouse.pressed ? "#24ffffff" : (silentMouse.containsMouse || Services.SystemStatus.notificationsSilent ? "#18ffffff" : "#12ffffff")
                                border.width: 0
                                antialiasing: true

                                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                Components.StyledText {
                                    anchors.centerIn: parent
                                    text: "Silent"
                                    color: "#eef3f8"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: silentMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemStatus.toggleNotificationsSilent()
                                }
                            }

                            Rectangle {
                                width: 50
                                height: 24
                                radius: 12
                                color: clearMouse.pressed ? "#24ffffff" : (clearMouse.containsMouse ? "#18ffffff" : "#12ffffff")
                                border.width: 0
                                antialiasing: true

                                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                Components.StyledText {
                                    anchors.centerIn: parent
                                    text: "Clear"
                                    color: "#eef3f8"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: clearMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemStatus.clearNotifications()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Services.SystemStatus.hasBattery ? 54 : 0
                    visible: Services.SystemStatus.hasBattery
                    radius: 16
                    color: "#1019232f"
                    border.width: 0
                    antialiasing: true
                    opacity: Services.SystemStatus.hasBattery ? 1.0 : 0.0

                    Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        SystemIcon {
                            source: Services.SystemStatus.batteryCharging ? root.rowIcon("battery-charging") : (Services.SystemStatus.batteryPercent <= 10 ? root.rowIcon("battery-0") : (Services.SystemStatus.batteryPercent <= 25 ? root.rowIcon("battery-25") : (Services.SystemStatus.batteryPercent <= 50 ? root.rowIcon("battery-50") : (Services.SystemStatus.batteryPercent <= 80 ? root.rowIcon("battery-75") : root.rowIcon("battery-100")))))
                            iconOpacity: 0.95
                        }

                        Components.StyledText {
                            Layout.fillWidth: true
                            text: root.batteryLine()
                            color: "#d9e0ea"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.preferredWidth: 84
                            Layout.preferredHeight: 5
                            radius: 3
                            color: "#2affffff"
                            border.width: 0
                            antialiasing: true

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * Math.max(0, Math.min(1, Services.SystemStatus.batteryPercent / 100))
                                radius: parent.radius
                                color: "#eef3f8"
                                opacity: Services.SystemStatus.batteryPercent <= 10 ? 0.74 : 0.94
                                border.width: 0
                                antialiasing: true

                                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }
        }
    }
}
