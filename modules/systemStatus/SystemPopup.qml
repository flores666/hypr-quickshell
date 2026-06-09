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

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function networkTitle() {
        if (Services.SystemStatus.networkState === "connecting")
            return "Подключение";
        if (Services.SystemStatus.networkType === "ethernet" && Services.SystemStatus.networkState === "connected")
            return "Ethernet активен";
        if (Services.SystemStatus.networkType === "wifi" && Services.SystemStatus.networkState === "connected")
            return Services.SystemStatus.wifiSsid || Services.SystemStatus.networkConnection || "Wi-Fi подключен";
        if (Services.SystemStatus.hasWifi && Services.SystemStatus.wifiEnabled)
            return "Wi-Fi включен";
        if (Services.SystemStatus.hasWifi && !Services.SystemStatus.wifiEnabled)
            return "Wi-Fi выключен";
        return "Нет подключения";
    }

    function networkSubtitle() {
        if (Services.SystemStatus.networkType === "ethernet" && Services.SystemStatus.networkState === "connected")
            return Services.SystemStatus.networkConnection || Services.SystemStatus.networkDevice || "Проводное подключение";
        if (Services.SystemStatus.networkType === "wifi" && Services.SystemStatus.networkState === "connected")
            return "Сигнал " + Services.SystemStatus.wifiSignal + "%";
        if (Services.SystemStatus.networkState === "connecting")
            return "Система устанавливает соединение";
        return Services.SystemStatus.networkState === "error" ? "Данные сети недоступны" : "Активной сети нет";
    }

    function audioTitle() {
        if (!Services.SystemStatus.hasAudio)
            return "Аудиоустройство недоступно";
        if (Services.SystemStatus.muted)
            return "Звук заглушен";
        return "Громкость " + Services.SystemStatus.volume + "%";
    }

    function batteryTitle() {
        if (!Services.SystemStatus.hasBattery)
            return "";
        if (Services.SystemStatus.batteryStatus === "full")
            return "Батарея заряжена";
        if (Services.SystemStatus.batteryCharging || Services.SystemStatus.batteryStatus === "charging")
            return "Заряжается";
        if (Services.SystemStatus.batteryPercent <= 10)
            return "Критический заряд";
        if (Services.SystemStatus.batteryPercent <= 25)
            return "Низкий заряд";
        return "Питание от батареи";
    }

    function batterySubtitle() {
        if (!Services.SystemStatus.hasBattery)
            return "";
        var parts = [Services.SystemStatus.batteryPercent + "%"];
        if (Services.SystemStatus.acOnline)
            parts.push("питание от сети");
        if (Services.SystemStatus.batteryTime !== "")
            parts.push(Services.SystemStatus.batteryTime);
        return parts.join(" · ");
    }

    function rowIcon(name) {
        return Qt.resolvedUrl("icons/" + name + ".svg");
    }

    anchor.window: hostWindow
    anchor.rect.x: popupX
    anchor.rect.y: popupY
    implicitWidth: 358
    implicitHeight: Services.SystemStatus.hasBattery ? 454 : 370
    visible: popupState.renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    onTargetVisibleChanged: {
        if (targetVisible)
            Services.SystemStatus.requestRefresh();
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
            opacity: Math.max(0, Math.min(1, (root.reveal - 0.10) / 0.90))

            Column {
                id: contentColumn
                width: contentFlick.width
                spacing: 12

                RowLayout {
                    width: parent.width
                    height: 28
                    opacity: Math.max(0, Math.min(1, (root.reveal - 0.12) / 0.74))

                    Components.StyledText {
                        Layout.fillWidth: true
                        text: "Система"
                        color: "#f4f7fb"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        width: 58
                        height: 24
                        radius: 12
                        color: Services.SystemStatus.actionRunning ? "#18ffffff" : "#12ffffff"
                        border.width: 0
                        antialiasing: true

                        Components.StyledText {
                            anchors.centerIn: parent
                            text: Services.SystemStatus.actionRunning ? "..." : "обновить"
                            color: "#dbe3ee"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.SystemStatus.requestRefresh()
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: networkSection.implicitHeight + 24
                    radius: 16
                    color: "#1019232f"
                    border.width: 0
                    antialiasing: true

                    Column {
                        id: networkSection
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 10

                            SystemIcon {
                                source: Services.SystemStatus.networkType === "ethernet" ? rowIcon("ethernet") : (Services.SystemStatus.networkState === "connected" ? rowIcon("wifi-3") : rowIcon("wifi-off"))
                                iconOpacity: 0.95
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Components.StyledText {
                                    Layout.fillWidth: true
                                    text: root.networkTitle()
                                    color: "#eef3f8"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Components.StyledText {
                                    Layout.fillWidth: true
                                    text: root.networkSubtitle()
                                    color: "#aeb8c6"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                visible: Services.SystemStatus.hasWifi
                                width: 54
                                height: 24
                                radius: 12
                                color: wifiToggleMouse.pressed ? "#26ffffff" : (wifiToggleMouse.containsMouse ? "#18ffffff" : "#12ffffff")
                                border.width: 0
                                antialiasing: true

                                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                Components.StyledText {
                                    anchors.centerIn: parent
                                    text: Services.SystemStatus.wifiEnabled ? "Wi-Fi" : "off"
                                    color: "#eef3f8"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: wifiToggleMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.SystemStatus.toggleWifi()
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 6
                            visible: Services.SystemStatus.hasWifi && Services.SystemStatus.wifiEnabled
                            height: visible ? implicitHeight : 0

                            Repeater {
                                model: Services.SystemStatus.wifiNetworks
                                delegate: Rectangle {
                                    required property var modelData

                                    width: parent.width
                                    height: 27
                                    radius: 12
                                    color: wifiMouse.pressed ? "#22ffffff" : (wifiMouse.containsMouse ? "#14ffffff" : "transparent")
                                    border.width: 0
                                    antialiasing: true

                                    Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        SystemIcon {
                                            source: modelData.signal <= 25 ? rowIcon("wifi-0") : (modelData.signal <= 45 ? rowIcon("wifi-1") : (modelData.signal <= 70 ? rowIcon("wifi-2") : rowIcon("wifi-3")))
                                            iconOpacity: modelData.active ? 1.0 : 0.68
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
                                        id: wifiMouse
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
                    height: audioSection.implicitHeight + 24
                    radius: 16
                    color: "#1019232f"
                    border.width: 0
                    antialiasing: true

                    Column {
                        id: audioSection
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 10

                            SystemIcon {
                                source: !Services.SystemStatus.hasAudio ? rowIcon("volume-none") : (Services.SystemStatus.muted || Services.SystemStatus.volume <= 0 ? rowIcon("volume-muted") : (Services.SystemStatus.volume <= 33 ? rowIcon("volume-low") : (Services.SystemStatus.volume <= 66 ? rowIcon("volume-medium") : rowIcon("volume-high"))))
                                iconOpacity: 0.95
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Components.StyledText {
                                    Layout.fillWidth: true
                                    text: root.audioTitle()
                                    color: "#eef3f8"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Components.StyledText {
                                    Layout.fillWidth: true
                                    text: Services.SystemStatus.audioDevice !== "" ? Services.SystemStatus.audioDevice : "Устройство вывода не найдено"
                                    color: "#aeb8c6"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: 50
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

                        Column {
                            width: parent.width
                            spacing: 6
                            visible: Services.SystemStatus.audioDevices.length > 1
                            height: visible ? implicitHeight : 0

                            Repeater {
                                model: Services.SystemStatus.audioDevices
                                delegate: Rectangle {
                                    required property var modelData

                                    width: parent.width
                                    height: 26
                                    radius: 12
                                    color: deviceMouse.pressed ? "#22ffffff" : (deviceMouse.containsMouse ? "#14ffffff" : "transparent")
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

                Rectangle {
                    width: parent.width
                    height: Services.SystemStatus.hasBattery ? batterySection.implicitHeight + 24 : 0
                    visible: Services.SystemStatus.hasBattery
                    radius: 16
                    color: "#1019232f"
                    border.width: 0
                    antialiasing: true
                    opacity: Services.SystemStatus.hasBattery ? 1.0 : 0.0

                    Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }

                    Column {
                        id: batterySection
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 10

                            SystemIcon {
                                source: Services.SystemStatus.batteryCharging ? rowIcon("battery-charging") : (Services.SystemStatus.batteryPercent <= 10 ? rowIcon("battery-0") : (Services.SystemStatus.batteryPercent <= 25 ? rowIcon("battery-25") : (Services.SystemStatus.batteryPercent <= 50 ? rowIcon("battery-50") : (Services.SystemStatus.batteryPercent <= 80 ? rowIcon("battery-75") : rowIcon("battery-100")))))
                                iconOpacity: 0.95
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Components.StyledText {
                                    Layout.fillWidth: true
                                    text: root.batteryTitle()
                                    color: "#eef3f8"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Components.StyledText {
                                    Layout.fillWidth: true
                                    text: root.batterySubtitle()
                                    color: "#aeb8c6"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 5
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
