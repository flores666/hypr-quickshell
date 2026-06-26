import QtQuick

Item {
    id: root

    readonly property string family: "Nunito"

    FontLoader { source: Qt.resolvedUrl("../assets/fonts/Nunito-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/fonts/Nunito-Medium.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/fonts/Nunito-SemiBold.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/fonts/Nunito-Bold.ttf") }
}
