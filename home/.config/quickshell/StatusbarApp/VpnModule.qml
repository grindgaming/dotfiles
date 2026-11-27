import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.CustomTheme

// CyberGhost-VPN-Knopf (eigenes Modul, nicht ML4W). Backend: ~/.local/bin/cg-vpn
//   • Linksklick / Return → kleines Fenster mit Status und einem An/Aus-Knopf
//   • Rechtsklick         → direkt an/aus
// Verbindet automatisch mit dem Server mit der niedrigsten Last (Land: DE).
// Ist CyberGhost nicht installiert, bleibt das Modul unsichtbar.
Rectangle {
    id: vpn

    property string vpnState: "off"        // on | off | busy
    property string tooltip: ""
    property bool installed: true
    property bool menuOpen: false
    property bool focused: false

    readonly property bool active: mouseArea.containsMouse || focused || menuOpen
    readonly property bool collapsed: !installed

    readonly property string scriptPath: Quickshell.env("HOME") + "/.local/bin/cg-vpn"

    function iconFor(s) {
        if (s === "on") return "../shared/icons/shield.svg"
        if (s === "busy") return "../shared/icons/shield-busy.svg"
        return "../shared/icons/shield-off.svg"
    }

    function activate(): void { menuOpen = !menuOpen; refresh() }

    function refresh(): void {
        if (!statusProc.running) statusProc.running = true
    }

    function toggle(): void {
        if (vpn.vpnState === "busy" || toggleProc.running) return
        vpn.vpnState = "busy"
        vpn.tooltip = vpn.tooltip.indexOf("Verbunden") === 0 ? "Trenne …" : "Suche besten Server …"
        toggleProc.running = true
    }

    visible: installed
    implicitWidth: installed ? 30 : 0
    implicitHeight: 30
    radius: 15
    color: active ? Theme.primary : "transparent"
    Behavior on color { ColorAnimation { duration: 500; easing.type: Easing.OutQuint } }

    // Äußeres Item pulsiert beim Verbinden, das Bild selbst wird bei "aus" gedimmt.
    Item {
        id: pulse
        anchors.fill: parent
        SequentialAnimation on opacity {
            running: vpn.vpnState === "busy"
            loops: Animation.Infinite
            onStopped: pulse.opacity = 1.0
            NumberAnimation { to: 0.3; duration: 600 }
            NumberAnimation { to: 1.0; duration: 600 }
        }

        Image {
            id: icon
            anchors.centerIn: parent
            source: vpn.iconFor(vpn.vpnState)
            width: 18; height: 18
            sourceSize.width: 18; sourceSize.height: 18
            fillMode: Image.PreserveAspectFit
            opacity: vpn.vpnState === "off" && !vpn.active ? 0.45 : 1.0
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: vpn.active ? Theme.background : Theme.primary
                Behavior on colorizationColor { ColorAnimation { duration: 500; easing.type: Easing.OutQuint } }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) vpn.toggle()
            else vpn.activate()
        }
    }

    // ---- Backend ----
    Process {
        id: statusProc
        command: [vpn.scriptPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text)
                    if (!toggleProc.running) vpn.vpnState = d["class"]
                    vpn.tooltip = d.tooltip
                } catch (e) { }
            }
        }
        onExited: (code) => { if (code === 127) vpn.installed = false }
    }

    Process {
        id: toggleProc
        command: [vpn.scriptPath, "toggle"]
        onExited: vpn.refresh()
    }

    // Prüft einmal beim Start, ob CyberGhost überhaupt installiert ist.
    Process {
        id: checkProc
        running: true
        command: ["sh", "-c", "[ -x /usr/bin/cyberghostvpn ] && [ -x \"$HOME/.local/bin/cg-vpn\" ]"]
        onExited: (code) => { vpn.installed = (code === 0); if (vpn.installed) vpn.refresh() }
    }

    Timer {
        interval: (vpn.vpnState === "busy" || vpn.menuOpen) ? 1000 : 5000
        running: vpn.installed
        repeat: true
        onTriggered: vpn.refresh()
    }

    // ---- Popup ----
    PopupWindow {
        id: popup
        anchor.item: vpn
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10
        anchor.rect.x: vpn.width / 2 - popup.width / 2
        visible: vpn.menuOpen

        HyprlandFocusGrab {
            windows: [popup]
            active: vpn.menuOpen
            onCleared: vpn.menuOpen = false
        }

        implicitWidth: 260
        implicitHeight: col.implicitHeight + 24
        color: "transparent"

        FocusScope {
            id: keyScope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: vpn.menuOpen = false
            Keys.onReturnPressed: vpn.toggle()
        }
        onVisibleChanged: if (visible) keyScope.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.background
            border.color: Theme.primary
            border.width: 1
        }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "CyberGhost VPN"
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: vpn.tooltip
                wrapMode: Text.Wrap
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }

            Rectangle {
                id: bigButton
                Layout.fillWidth: true
                implicitHeight: 40
                radius: 20
                readonly property bool on: vpn.vpnState === "on"
                color: vpn.vpnState === "busy" ? Theme.surface_variant
                     : (btnMouse.containsMouse ? Theme.primary : (on ? Theme.primary_container : "transparent"))
                border.color: Theme.primary
                border.width: 1
                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: vpn.vpnState === "busy" ? "Bitte warten …" : (bigButton.on ? "Ausschalten" : "Einschalten")
                    color: btnMouse.containsMouse && vpn.vpnState !== "busy" ? Theme.background
                         : (bigButton.on ? Theme.on_primary_container : Theme.primary)
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }

                MouseArea {
                    id: btnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: vpn.vpnState !== "busy"
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vpn.toggle()
                }
            }
        }
    }
}
