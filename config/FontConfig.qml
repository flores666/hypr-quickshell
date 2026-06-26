import QtQuick

Item {
    id: root

    readonly property string family: "Montserrat"

    FontLoader { source: Qt.resolvedUrl("../assets/fonts/Montserrat-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/fonts/Montserrat-Medium.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/fonts/Montserrat-SemiBold.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/fonts/Montserrat-Bold.ttf") }
}
