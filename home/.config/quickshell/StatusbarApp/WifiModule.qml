import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.CustomTheme

// Wi-Fi status icon + themed network manager popup. Backed entirely by nmcli
// (NetworkManager), refreshed live through `nmcli monitor`.
//   • left click / Return → open the Wi-Fi panel
//   • right click         → toggle the Wi-Fi radio
// Panel: radio switch, current connection (disconnect / forget), scanned
// networks (click to connect; secured unknown networks ask for a password),
// rescan and a shortcut to nm-connection-editor for advanced settings.
Rectangle {
    id: wifi

    // ---- state (filled by refresh()) ----
    property bool radioOn: true
    property string activeSsid: ""
    property int activeSignal: 0
    property var networks: []          // [{ ssid, signal, secure, security, inUse, known }]
    property var knownNames: []        // saved wifi connection profile names
    property bool scanning: false

    // ---- UI state ----
    property bool menuOpen: false
    property bool focused: false
    property string pendingSsid: ""    // network whose password row is open
    property string busySsid: ""       // network currently being connected
    property string statusText: ""
    property bool statusError: false

    readonly property bool connected: activeSsid !== ""
    readonly property bool active: mouseArea.containsMouse || focused || menuOpen

    function iconFor(signal, on, conn) {
        if (!on) return "../shared/icons/wifi-off.svg"
        if (!conn) return "../shared/icons/wifi-zero.svg"
        if (signal >= 67) return "../shared/icons/wifi.svg"
        if (signal >= 34) return "../shared/icons/wifi-high.svg"
        return "../shared/icons/wifi-low.svg"
    }

    function activate(): void {
        menuOpen = !menuOpen
        if (menuOpen) rescan()
    }

    // nmcli -t escapes ':' and '\' with a backslash; split on unescaped ':'.
    function splitTerse(line) {
        let out = [], cur = ""
        for (let i = 0; i < line.length; i++) {
            let c = line[i]
            if (c === "\\" && i + 1 < line.length) cur += line[++i]
            else if (c === ":") { out.push(cur); cur = "" }
            else cur += c
        }
        out.push(cur)
        return out
    }

    function parseState(text) {
        let sections = text.split("\n---\n")
        if (sections.length < 3) return
        wifi.radioOn = sections[0].trim() === "enabled"

        let known = []
        for (let l of sections[1].split("\n")) {
            if (!l) continue
            let f = splitTerse(l)
            if (f[1] === "802-11-wireless") known.push(f[0])
        }
        wifi.knownNames = known

        let bySsid = {}
        let actSsid = "", actSig = 0
        for (let l of sections[2].split("\n")) {
            if (!l) continue
            let f = splitTerse(l)           // IN-USE, SIGNAL, SECURITY, SSID
            let ssid = f.slice(3).join(":")
            if (!ssid) continue
            let n = {
                ssid: ssid,
                signal: parseInt(f[1]) || 0,
                security: f[2],
                secure: f[2] !== "" && f[2] !== "--",
                inUse: f[0] === "*",
                known: known.indexOf(ssid) !== -1
            }
            if (n.inUse) { actSsid = ssid; actSig = n.signal }
            let prev = bySsid[ssid]
            if (!prev || n.inUse || (!prev.inUse && n.signal > prev.signal))
                bySsid[ssid] = n
        }
        let list = Object.values(bySsid)
        list.sort((a, b) => (b.inUse - a.inUse) || (b.known - a.known) || (b.signal - a.signal))
        wifi.activeSsid = actSsid
        wifi.activeSignal = actSig
        wifi.networks = list
    }

    function refresh(): void {
        if (!stateProc.running) stateProc.running = true
    }

    function rescan(): void {
        if (rescanProc.running) return
        wifi.scanning = true
        rescanProc.running = true
    }

    function run(cmd, onDone): void {
        let p = actionComp.createObject(wifi, { command: cmd })
        p.done.connect((code, err) => { onDone(code, err); p.destroy() })
        p.running = true
    }

    function connectTo(net, password): void {
        wifi.busySsid = net.ssid
        wifi.statusError = false
        wifi.statusText = "Connecting to " + net.ssid + "…"
        let cmd = ["nmcli", "--wait", "30", "dev", "wifi", "connect", net.ssid]
        if (password) cmd.push("password", password)
        let wasKnown = net.known
        run(cmd, (code, err) => {
            wifi.busySsid = ""
            if (code === 0) {
                wifi.statusText = ""
                wifi.pendingSsid = ""
            } else {
                // A failed first-time attempt leaves a broken profile behind.
                if (!wasKnown)
                    run(["nmcli", "con", "delete", "id", net.ssid], () => refresh())
                if (net.secure && /secret|password|802-1x|psk/i.test(err)) {
                    wifi.pendingSsid = net.ssid
                    wifi.statusText = password ? "Wrong password" : "Password required"
                } else {
                    wifi.statusText = (err.split("\n").filter(s => s).pop() || "Connection failed")
                        .replace(/^Error:\s*/, "")
                }
                wifi.statusError = true
            }
            refresh()
        })
    }

    function clickNetwork(net): void {
        if (net.inUse || wifi.busySsid !== "") return
        wifi.statusText = ""
        if (net.secure && !net.known) {
            wifi.pendingSsid = (wifi.pendingSsid === net.ssid) ? "" : net.ssid
        } else {
            wifi.pendingSsid = ""
            connectTo(net, "")
        }
    }

    function setRadio(on): void {
        wifi.radioOn = on
        run(["nmcli", "radio", "wifi", on ? "on" : "off"], () => refresh())
    }

    function disconnect(): void {
        run(["nmcli", "con", "down", "id", wifi.activeSsid], () => refresh())
    }

    function forget(ssid): void {
        run(["nmcli", "con", "delete", "id", ssid], () => refresh())
    }

    Component {
        id: actionComp
        Process {
            signal done(int code, string err)
            property string errText: ""
            stderr: StdioCollector { onStreamFinished: errText = text }
            stdout: StdioCollector { onStreamFinished: if (!errText) errText = text }
            onExited: code => Qt.callLater(() => done(code, errText))
        }
    }

    Process {
        id: stateProc
        command: ["sh", "-c",
            "nmcli -t -f WIFI g; echo ---; nmcli -t -f NAME,TYPE con show; echo ---; "
            + "nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan no"]
        stdout: StdioCollector { onStreamFinished: wifi.parseState(text) }
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        onExited: { wifi.scanning = false; wifi.refresh() }
    }

    // Live updates: any NetworkManager event triggers a (debounced) refresh.
    Process {
        id: monitorProc
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: debounce.restart() }
        onExited: monitorRestart.start()
    }
    Timer { id: monitorRestart; interval: 5000; onTriggered: monitorProc.running = true }
    Timer { id: debounce; interval: 300; onTriggered: wifi.refresh() }
    // Signal strength isn't reported by the monitor; poll it gently.
    Timer {
        interval: wifi.menuOpen ? 5000 : 30000
        running: true; repeat: true
        onTriggered: wifi.refresh()
    }
    Timer {
        interval: 20000
        running: wifi.menuOpen && wifi.radioOn; repeat: true
        onTriggered: wifi.rescan()
    }
    Component.onCompleted: refresh()

    // qs ipc call wifi toggle  — e.g. for a Hyprland keybinding.
    property bool ipcEnabled: true
    IpcHandler {
        enabled: wifi.ipcEnabled
        target: "wifi"
        function toggle(): void { wifi.activate() }
    }

    // ==========================================
    // BAR ICON
    // ==========================================
    implicitWidth: 30
    implicitHeight: 30
    radius: 15
    color: active ? Theme.primary : "transparent"
    Behavior on color { ColorAnimation { duration: 500; easing.type: Easing.OutQuint } }

    Image {
        anchors.centerIn: parent
        source: wifi.iconFor(wifi.activeSignal, wifi.radioOn, wifi.connected)
        width: 18; height: 18
        sourceSize.width: 18; sourceSize.height: 18
        opacity: (wifi.radioOn && !wifi.connected && !wifi.active) ? 0.6 : 1
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: wifi.active ? Theme.background : Theme.primary
            Behavior on colorizationColor { ColorAnimation { duration: 500; easing.type: Easing.OutQuint } }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) wifi.setRadio(!wifi.radioOn)
            else wifi.activate()
        }
    }

    // ==========================================
    // PANEL
    // ==========================================
    component Icon: Image {
        id: ic
        property color tint: Theme.primary
        width: 16; height: 16
        sourceSize.width: width; sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        layer.enabled: true
        layer.effect: MultiEffect { colorization: 1.0; colorizationColor: ic.tint }
    }

    component PillButton: Rectangle {
        id: pb
        property string label
        property bool danger: false
        signal clicked()
        implicitHeight: 28
        implicitWidth: pbText.implicitWidth + 24
        radius: 14
        color: pbMouse.containsMouse ? (danger ? Theme.error : Theme.primary) : "transparent"
        border.width: 1
        border.color: danger ? Theme.error : Theme.primary
        Behavior on color { ColorAnimation { duration: 200 } }
        Text {
            id: pbText
            anchors.centerIn: parent
            text: pb.label
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: pbMouse.containsMouse ? Theme.background : (pb.danger ? Theme.error : Theme.primary)
        }
        MouseArea {
            id: pbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }

    PopupWindow {
        id: popup
        anchor.item: wifi
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10
        anchor.rect.x: wifi.width / 2 - popup.width / 2
        visible: wifi.menuOpen
        color: "transparent"
        implicitWidth: 340
        implicitHeight: panel.implicitHeight + 24

        HyprlandFocusGrab {
            windows: [popup]
            active: wifi.menuOpen
            onCleared: wifi.menuOpen = false
        }

        onVisibleChanged: {
            if (visible) keyScope.forceActiveFocus()
            else { wifi.pendingSsid = ""; if (!wifi.statusError) wifi.statusText = "" }
        }

        FocusScope {
            id: keyScope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: wifi.menuOpen = false
        }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.background
            border.color: Theme.primary
            border.width: 1
        }

        ColumnLayout {
            id: panel
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ---- header ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Icon {
                    source: wifi.radioOn ? "../shared/icons/wifi.svg" : "../shared/icons/wifi-off.svg"
                    width: 20; height: 20
                }
                Text {
                    Layout.fillWidth: true
                    text: "Wi-Fi"
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    font.bold: true
                }

                // rescan
                Rectangle {
                    visible: wifi.radioOn
                    implicitWidth: 28; implicitHeight: 28; radius: 14
                    color: rescanMouse.containsMouse ? Theme.surface_container_high : "transparent"
                    Icon {
                        id: rescanIcon
                        anchors.centerIn: parent
                        source: "../shared/icons/refresh.svg"
                        RotationAnimation on rotation {
                            running: wifi.scanning
                            from: 0; to: 360; duration: 900
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) rescanIcon.rotation = 0
                        }
                    }
                    MouseArea {
                        id: rescanMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wifi.rescan()
                    }
                }

                // radio switch
                Rectangle {
                    implicitWidth: 44; implicitHeight: 24; radius: 12
                    color: wifi.radioOn ? Theme.primary : Theme.surface_container_highest
                    border.width: wifi.radioOn ? 0 : 1
                    border.color: Theme.outline
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: wifi.radioOn ? parent.width - width - 3 : 3
                        color: wifi.radioOn ? Theme.background : Theme.outline
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wifi.setRadio(!wifi.radioOn)
                    }
                }
            }

            // ---- current connection ----
            Rectangle {
                Layout.fillWidth: true
                visible: wifi.radioOn && wifi.connected
                implicitHeight: curCol.implicitHeight + 24
                radius: 10
                color: Theme.primary_container

                ColumnLayout {
                    id: curCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        spacing: 10
                        Rectangle {
                            implicitWidth: 36; implicitHeight: 36; radius: 18
                            color: Theme.primary
                            Icon {
                                anchors.centerIn: parent
                                source: wifi.iconFor(wifi.activeSignal, true, true)
                                width: 18; height: 18
                                tint: Theme.background
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: wifi.activeSsid
                                elide: Text.ElideRight
                                color: Theme.on_primary_container
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                            }
                            Text {
                                text: "Connected · " + wifi.activeSignal + "% signal"
                                color: Theme.on_primary_container
                                opacity: 0.75
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }
                    }
                    RowLayout {
                        spacing: 8
                        PillButton { label: "Disconnect"; onClicked: wifi.disconnect() }
                        PillButton { label: "Forget"; danger: true; onClicked: wifi.forget(wifi.activeSsid) }
                    }
                }
            }

            // ---- off state ----
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                visible: !wifi.radioOn
                horizontalAlignment: Text.AlignHCenter
                text: "Wi-Fi is turned off"
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }

            // ---- network list ----
            Text {
                visible: wifi.radioOn
                text: "AVAILABLE NETWORKS"
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1
            }

            Flickable {
                id: listFlick
                Layout.fillWidth: true
                visible: wifi.radioOn
                implicitHeight: Math.min(netColumn.implicitHeight, 320)
                contentHeight: netColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: netColumn
                    width: listFlick.width
                    spacing: 2

                    Text {
                        visible: wifi.networks.filter(n => !n.inUse).length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                        horizontalAlignment: Text.AlignHCenter
                        text: wifi.scanning ? "Scanning…" : "No networks found"
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }

                    Repeater {
                        model: wifi.networks.filter(n => !n.inUse)
                        delegate: ColumnLayout {
                            id: rowItem
                            required property var modelData
                            readonly property bool expanded: wifi.pendingSsid === modelData.ssid
                            readonly property bool busy: wifi.busySsid === modelData.ssid
                            Layout.fillWidth: true
                            spacing: 0

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                radius: 8
                                color: rowMouse.containsMouse || rowItem.expanded
                                    ? Theme.surface_container_high : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Icon {
                                        source: wifi.iconFor(rowItem.modelData.signal, true, true)
                                        width: 18; height: 18
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: rowItem.modelData.ssid
                                        elide: Text.ElideRight
                                        color: Theme.on_surface
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        visible: rowItem.busy
                                        text: "Connecting…"
                                        color: Theme.primary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }
                                    Rectangle {
                                        visible: rowItem.modelData.known && !rowItem.busy
                                        implicitWidth: savedText.implicitWidth + 12
                                        implicitHeight: 18
                                        radius: 9
                                        color: Theme.secondary_container
                                        Text {
                                            id: savedText
                                            anchors.centerIn: parent
                                            text: "Saved"
                                            color: Theme.on_secondary_container
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                        }
                                    }
                                    Icon {
                                        visible: rowItem.modelData.secure
                                        source: "../shared/icons/lock.svg"
                                        width: 13; height: 13
                                        tint: Theme.on_surface_variant
                                    }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton && rowItem.modelData.known)
                                            wifi.forget(rowItem.modelData.ssid)
                                        else
                                            wifi.clickNetwork(rowItem.modelData)
                                    }
                                }
                            }

                            // password row
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                Layout.rightMargin: 4
                                Layout.topMargin: 6
                                Layout.bottomMargin: 6
                                visible: rowItem.expanded
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 8
                                    color: Theme.surface_container
                                    border.width: 1
                                    border.color: pwInput.activeFocus ? Theme.primary : Theme.outline_variant

                                    TextInput {
                                        id: pwInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 34
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: showPw.checked ? TextInput.Normal : TextInput.Password
                                        color: Theme.on_surface
                                        selectionColor: Theme.primary
                                        selectedTextColor: Theme.background
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        clip: true
                                        onAccepted: if (text.length) wifi.connectTo(rowItem.modelData, text)
                                        Keys.onEscapePressed: wifi.pendingSsid = ""

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !pwInput.text && !pwInput.preeditText
                                            text: "Password"
                                            color: Theme.on_surface_variant
                                            opacity: 0.7
                                            font: pwInput.font
                                        }
                                    }
                                    // show / hide password
                                    MouseArea {
                                        id: showPw
                                        property bool checked: false
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 32; height: 32
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: checked = !checked
                                        Text {
                                            anchors.centerIn: parent
                                            text: showPw.checked ? "Hide" : "Show"
                                            color: Theme.primary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                                PillButton {
                                    label: "Connect"
                                    onClicked: if (pwInput.text.length) wifi.connectTo(rowItem.modelData, pwInput.text)
                                }

                                onVisibleChanged: {
                                    if (visible) { pwInput.text = ""; pwInput.forceActiveFocus() }
                                }
                            }
                        }
                    }
                }
            }

            // ---- status ----
            Text {
                Layout.fillWidth: true
                visible: wifi.statusText !== ""
                text: wifi.statusText
                wrapMode: Text.Wrap
                color: wifi.statusError ? Theme.error : Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            // ---- footer ----
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.outline_variant }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: 8
                color: settingsMouse.containsMouse ? Theme.surface_container_high : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    spacing: 10
                    Icon { source: "../shared/icons/settings.svg" }
                    Text {
                        Layout.fillWidth: true
                        text: "Network settings"
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }
                MouseArea {
                    id: settingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        wifi.menuOpen = false
                        Quickshell.execDetached(["nm-connection-editor"])
                    }
                }
            }
        }
    }
}
