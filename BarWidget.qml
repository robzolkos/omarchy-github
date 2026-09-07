import QtQuick
import Omarchy.PluginPresentation 1.0

Item {
    id: root
    implicitWidth: Style.bar.statusSlot
    implicitHeight: Style.bar.size

    readonly property int unreadCount: github.unreadCount
    readonly property bool readAvailable: runtime.hasPermission("bash.execute", "run")
    readonly property var settings: runtime.settings
    readonly property bool active: github.alarming && !settings.iconAlwaysUnlit

    Service { id: github }

    Rectangle {
        id: button
        anchors.fill: parent
        color: "transparent"
        opacity: root.readAvailable ? 1 : 0.5

        Text {
            anchors.centerIn: parent
            text: "\uf09b"
            color: root.active ? Color.bar.active : Color.bar.text
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
        }

        Rectangle {
            visible: root.unreadCount > 0
            width: 5
            height: 5
            radius: 3
            color: Color.bar.active
            anchors.right: parent.right
            anchors.top: parent.top
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) github.refresh()
                else runtime.requestSurfaceIntent("github", "toggle")
            }
        }
    }
}
