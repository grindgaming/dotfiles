import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.CustomTheme

Rectangle {
    id: backlight
    property int percent: 0
    property bool focused: false

    Process {
        id: brightProc
        command: ["sh", "-c", "brightnessctl -m | awk -F, '{print $4}' | tr -d '%'; while inotifywait -qq -e modify /sys/class/backlight/*/brightness; do brightnessctl -m | awk -F, '{print $4}' | tr -d '%'; done"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                let val = parseInt(data.trim())
                if (!isNaN(val)) backlight.percent = val
            }
        }
    }

    function step(dir: int): void {
        let cmd = dir > 0 ? "5%+" : "5%-"
        Quickshell.execDetached(["brightnessctl", "set", cmd])
    }

    readonly property bool active: mouseArea.containsMouse || backlight.focused
    implicitWidth: row.implicitWidth + 6
    implicitHeight: 30
    radius: 15
    color: active ? Theme.primary : "transparent"

    Behavior on color { ColorAnimation { duration: 500; easing.type: Easing.OutQuint } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Image {
            Layout.alignment: Qt.AlignVCenter
            source: "../shared/icons/brightness.svg"
            sourceSize.width: 18
            sourceSize.height: 18
            width: 18
            height: 18
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: backlight.active ? Theme.background : Theme.primary
                Behavior on colorizationColor { ColorAnimation { duration: 500; easing.type: Easing.OutQuint } }
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: backlight.percent + "%"
            color: backlight.active ? Theme.background : Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.bold: true
            Behavior on color { ColorAnimation { duration: 500; easing.type: Easing.OutQuint } }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onWheel: wheel => backlight.step(wheel.angleDelta.y > 0 ? 1 : -1)
    }
}
