import Quickshell
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    property int cornerSize: 28
    property color maskColor: "#000807"

    PanelWindow {
        id: topLeftCorner

        anchors {
            top: true
            left: true
        }

        margins {
            top: 0
            left: 0
        }

        implicitWidth: root.cornerSize
        implicitHeight: root.cornerSize
        color: "transparent"
        surfaceFormat.opaque: false
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: true

        WlrLayershell.namespace: "quickshell:rounded-corner-top-left"
        WlrLayershell.layer: WlrLayer.Overlay

        Canvas {
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d");
                const r = root.cornerSize;

                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.maskColor;
                ctx.beginPath();
                ctx.moveTo(0, r);
                ctx.quadraticCurveTo(0, 0, r, 0);
                ctx.lineTo(0, 0);
                ctx.closePath();
                ctx.fill();
            }

            Component.onCompleted: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    PanelWindow {
        id: topRightCorner

        anchors {
            top: true
            right: true
        }

        margins {
            top: 0
            right: 0
        }

        implicitWidth: root.cornerSize
        implicitHeight: root.cornerSize
        color: "transparent"
        surfaceFormat.opaque: false
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: true

        WlrLayershell.namespace: "quickshell:rounded-corner-top-right"
        WlrLayershell.layer: WlrLayer.Overlay

        Canvas {
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d");
                const r = root.cornerSize;

                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.maskColor;
                ctx.beginPath();
                ctx.moveTo(width - r, 0);
                ctx.quadraticCurveTo(width, 0, width, r);
                ctx.lineTo(width, 0);
                ctx.closePath();
                ctx.fill();
            }

            Component.onCompleted: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    PanelWindow {
        id: bottomLeftCorner

        anchors {
            bottom: true
            left: true
        }

        margins {
            bottom: 0
            left: 0
        }

        implicitWidth: root.cornerSize
        implicitHeight: root.cornerSize
        color: "transparent"
        surfaceFormat.opaque: false
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: true

        WlrLayershell.namespace: "quickshell:rounded-corner-bottom-left"
        WlrLayershell.layer: WlrLayer.Overlay

        Canvas {
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d");
                const r = root.cornerSize;

                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.maskColor;
                ctx.beginPath();
                ctx.moveTo(0, height - r);
                ctx.quadraticCurveTo(0, height, r, height);
                ctx.lineTo(0, height);
                ctx.closePath();
                ctx.fill();
            }

            Component.onCompleted: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    PanelWindow {
        id: bottomRightCorner

        anchors {
            bottom: true
            right: true
        }

        margins {
            bottom: 0
            right: 0
        }

        implicitWidth: root.cornerSize
        implicitHeight: root.cornerSize
        color: "transparent"
        surfaceFormat.opaque: false
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: true

        WlrLayershell.namespace: "quickshell:rounded-corner-bottom-right"
        WlrLayershell.layer: WlrLayer.Overlay

        Canvas {
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d");
                const r = root.cornerSize;

                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.maskColor;
                ctx.beginPath();
                ctx.moveTo(width - r, height);
                ctx.quadraticCurveTo(width, height, width, height - r);
                ctx.lineTo(width, height);
                ctx.closePath();
                ctx.fill();
            }

            Component.onCompleted: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }
}
