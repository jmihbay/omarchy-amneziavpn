pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
    id: root
    // Omarchy exposes these token groups as dynamic QObjects.
    readonly property var themeFont: Commons.Style.font
    readonly property var themeSpacing: Commons.Style.spacing
    moduleName: "jmihbay.amneziaVPN"
    ipcTarget: "jmihbay.amneziaVPN"
    implicitWidth: root.bar && root.bar.vertical ? root.bar.barSize : Commons.Style.bar.iconSlot
    implicitHeight: root.bar && root.bar.vertical ? Commons.Style.bar.iconSlot : (root.bar ? root.bar.barSize : Commons.Style.bar.sizeHorizontal)
    width: implicitWidth
    height: implicitHeight
    readonly property var trayItem: {
        var items = SystemTray.items.values
        for (var i = 0; i < items.length; i++) {
            if (String(items[i].id).toLowerCase() === "amneziavpn") return items[i]
        }
        return null
    }
    readonly property var connectEntry: action("connect")
    readonly property var disconnectEntry: action("disconnect")
    readonly property var openEntry: action("open")
    readonly property var websiteEntry: action("website")
    readonly property bool canConnect: !!connectEntry && connectEntry.enabled
    readonly property bool canDisconnect: !!disconnectEntry && disconnectEntry.enabled
    readonly property string state: !trayItem ? "stopped"
        : canConnect && !canDisconnect ? "disconnected"
        : canDisconnect && !canConnect ? "connected"
        : connectEntry && disconnectEntry && !canConnect && !canDisconnect ? "transition" : "unknown"
    property string pendingState: ""
    property bool actionTimedOut: false
    readonly property string statusKey: pendingState !== "" ? "transition" : state

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    QsMenuOpener { id: menu; menu: root.trayItem ? root.trayItem.menu : null }

    // Discover actions each time: D-Bus owners and menu IDs change on restart.
    // Unknown translations deliberately disable switching rather than guess.
    function action(kind) {
        var labels = {
            connect: ["подключиться", "connect"],
            disconnect: ["отключиться", "disconnect"],
            open: ["показать amneziavpn", "show amneziavpn", "show"],
            website: ["посетить сайт", "visit website"]
        }
        var entries = menu.children.values
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i]
            var label = String(entry.text || "").replace(/&/g, "").trim().toLowerCase()
            if (!entry.isSeparator && labels[kind].indexOf(label) !== -1) return entry
        }
        return null
    }
    function switchConnection() {
        if (pendingState !== "") return
        var entry = state === "connected" ? disconnectEntry : state === "disconnected" ? connectEntry : null
        if (!entry || !entry.enabled) return
        actionTimedOut = false
        pendingState = state === "connected" ? "disconnected" : "connected"
        deadline.restart()
        entry.triggered()
    }
    onStateChanged: {
        observedSince = state === "connected" ? Date.now() : 0
        lastSample = 0
        rxSpeed = 0; txSpeed = 0
        if (root.opened) refreshData()
        if (state === pendingState || state === "stopped") {
            pendingState = ""
            deadline.stop()
        }
    }
    Timer {
        id: deadline
        interval: 30000
        onTriggered: { root.pendingState = ""; root.actionTimedOut = true }
    }

    property string profileName: ""
    property string countryName: ""
    property string countryCode: ""
    property int keyboardIndex: -1
    property int taglineIndex: 0
    function countryFlag() {
        if (!/^[a-zA-Z]{2}$/.test(countryCode)) return ""
        var code = countryCode.toUpperCase()
        return String.fromCodePoint(127397 + code.charCodeAt(0), 127397 + code.charCodeAt(1)) + " "
    }
    property double observedSince: 0
    property double now: Date.now()
    property double rxBytes: -1
    property double txBytes: -1
    property double rxSpeed: 0
    property double txSpeed: 0
    property double lastSample: 0
    property bool rxReady: false
    property bool txReady: false
    function bytes(value) {
        if (value < 0) return "—"
        var units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var i = 0
        while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ }
        return Commons.I18n.formatNumber(value, i === 0 ? 0 : 1) + " " + units[i]
    }
    function elapsed() {
        var seconds = Math.max(0, Math.floor((now - observedSince) / 1000))
        return Math.floor(seconds / 3600) + ":" + String(Math.floor(seconds / 60) % 60).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0")
    }
    function sample() {
        if (!rxReady || !txReady) return
        var rx = Number(rxFile.text().trim()), tx = Number(txFile.text().trim())
        var stamp = Date.now()
        if (!isFinite(rx) || !isFinite(tx) || rx < 0 || tx < 0) return
        var dt = (stamp - lastSample) / 1000
        rxSpeed = lastSample > 0 && rx >= rxBytes && dt > 0 ? (rx - rxBytes) / dt : 0
        txSpeed = lastSample > 0 && tx >= txBytes && dt > 0 ? (tx - txBytes) / dt : 0
        rxBytes = rx; txBytes = tx; lastSample = stamp
    }
    function refreshData() {
        now = Date.now()
        if (!profileReader.running) profileReader.running = true
        if (state === "connected") {
            rxReady = false; txReady = false
            rxFile.reload(); txFile.reload()
        } else { rxBytes = -1; txBytes = -1; lastSample = 0 }
    }
    onOpenedChanged: {
        root.keyboardIndex = -1
        lastSample = 0; rxSpeed = 0; txSpeed = 0
        if (root.opened) root.refreshData()
    }
    Process {
        id: profileReader
        command: ["python3", Qt.resolvedUrl("profile.py").toString().replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    root.profileName = data.name || ""
                    root.countryName = data.country || ""
                    root.countryCode = data.code || ""
                } catch (e) { root.profileName = ""; root.countryName = ""; root.countryCode = "" }
            }
        }
    }
    FileView {
        id: rxFile
        path: "/sys/class/net/amn0/statistics/rx_bytes"
        printErrors: false
        onLoaded: { root.rxReady = true; root.sample() }
        onLoadFailed: { root.rxBytes = -1; root.lastSample = 0 }
    }
    FileView {
        id: txFile
        path: "/sys/class/net/amn0/statistics/tx_bytes"
        printErrors: false
        onLoaded: { root.txReady = true; root.sample() }
        onLoadFailed: { root.txBytes = -1; root.lastSample = 0 }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.opened
        onTriggered: {
            root.now = Date.now()
            if (root.state === "connected") {
                root.rxReady = false; root.txReady = false
                rxFile.reload(); txFile.reload()
            }
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.opened
        onTriggered: if (!profileReader.running) profileReader.running = true
    }

    Timer {
        interval: 6000
        repeat: true
        running: root.opened
        onTriggered: root.taglineIndex = (root.taglineIndex + 1) % 4
    }

    Ui.BarIconButton {
        id: button
        width: root.width
        height: root.height
        bar: root.bar
        iconComponent: Component {
            Item {
                id: barMark
                readonly property bool changing: root.statusKey === "transition"
                property real pulse: 1
                SequentialAnimation on pulse {
                    running: barMark.changing && Commons.Style.duration(240) > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: Commons.Style.duration(240); easing.type: Easing.OutCubic }
                    PauseAnimation { duration: Commons.Style.duration(180) }
                    NumberAnimation { to: 1; duration: Commons.Style.duration(240); easing.type: Easing.OutCubic }
                    PauseAnimation { duration: Commons.Style.duration(180) }
                }
                Item {
                    anchors.centerIn: parent
                    width: button.iconSize * 1.12
                    height: width
                    opacity: barMark.changing ? barMark.pulse
                        : root.state === "connected" ? 1
                        : root.state === "stopped" ? 0.3 : 0.55
                    Image {
                        anchors.fill: parent
                        source: Qt.resolvedUrl("logo.svg")
                        fillMode: Image.PreserveAspectFit
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1
                            colorizationColor: button.foreground
                        }
                    }
                    Rectangle {
                        visible: root.state === "disconnected" && !barMark.changing
                        anchors.centerIn: parent
                        width: parent.width * 1.15
                        height: Math.max(1, Commons.Style.space(1.5))
                        radius: height / 2
                        rotation: -45
                        color: button.foreground
                    }
                }
            }
        }
        onPressed: mouseButton => {
            if (mouseButton === Qt.RightButton) root.switchConnection()
            else if (mouseButton === Qt.LeftButton) root.toggle()
        }
    }
    Ui.KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: panel.loadedContent
        contentWidth: panel.fittedContentWidth(Commons.Style.space(360))
        contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Commons.Style.space(500))
        content: Ui.PanelKeyCatcher {
            id: keyCatcher
            implicitHeight: column.implicitHeight
            function available(index) {
                if (index === 0) return powerSwitch.interactive && !powerSwitch.busy
                if (index === 1) return openButton.enabled
                return index === 2 && websiteButton.enabled
            }
            function moveCursor(direction) {
                var index = root.keyboardIndex
                if (index < 0) index = direction > 0 ? -1 : 3
                for (var i = 0; i < 3; i++) {
                    index = (index + direction + 3) % 3
                    if (available(index)) { root.keyboardIndex = index; return }
                }
                root.keyboardIndex = -1
            }
            onMoveRequested: (dx, dy) => keyCatcher.moveCursor(dy !== 0 ? dy : dx)
            onActivateRequested: {
                if (!keyCatcher.available(root.keyboardIndex)) return
                if (root.keyboardIndex === 0) root.switchConnection()
                else if (root.keyboardIndex === 1) openButton.clicked()
                else websiteButton.clicked()
            }
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)
            ColumnLayout {
                id: column
                width: parent.width
                spacing: Commons.Style.space(12)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Commons.Style.space(12)
                    Image {
                        Layout.preferredWidth: Commons.Style.space(38)
                        Layout.preferredHeight: Commons.Style.space(38)
                        source: Qt.resolvedUrl("logo.svg")
                        fillMode: Image.PreserveAspectFit
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1
                            colorizationColor: Commons.Color.foreground
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: Commons.Style.space(2)
                        Text {
                            Layout.fillWidth: true
                            text: "AmneziaVPN"
                            textFormat: Text.PlainText
                            color: Commons.Color.foreground
                            font.family: root.themeFont.family
                            font.pixelSize: root.themeFont.title
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: strings.t("tagline" + root.taglineIndex)
                            textFormat: Text.PlainText
                            color: Commons.Color.foreground
                            opacity: 0.65
                            font.family: root.themeFont.family
                            font.pixelSize: root.themeFont.caption
                            elide: Text.ElideRight
                        }
                    }
                    Ui.ToggleSwitch {
                        id: powerSwitch
                        hasCursor: root.keyboardIndex === 0 && interactive
                        onHovered: hovered => { if (hovered && interactive && !busy) root.keyboardIndex = 0 }
                        checked: root.pendingState !== "" ? root.pendingState === "connected" : root.state === "connected"
                        busy: root.pendingState !== "" || root.state === "transition"
                        interactive: !!root.trayItem && (root.state === "connected" || root.state === "disconnected" || busy)
                        opacity: interactive ? 1 : 0.5
                        Accessible.name: strings.t(root.state === "connected" ? "disconnect" : "connect")
                        onToggled: root.switchConnection()
                    }
                }
                Ui.PanelSeparator {
                    Layout.fillWidth: true
                    foreground: Commons.Color.foreground
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.profileName !== ""
                    text: root.countryFlag() + (root.countryName ? root.countryName + " · " : "") + root.profileName
                    textFormat: Text.PlainText
                    color: Commons.Color.foreground
                    font.family: root.themeFont.family
                    font.pixelSize: root.themeFont.body + Commons.Style.space(1)
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.statusKey !== "connected" && root.statusKey !== "disconnected"
                    text: strings.t(root.statusKey)
                    textFormat: Text.PlainText
                    color: Commons.Color.foreground
                    font.family: root.themeFont.family
                    font.pixelSize: root.themeFont.body
                    wrapMode: Text.WordWrap
                }
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.state === "connected"
                    columns: 2
                    columnSpacing: Commons.Style.space(20)
                    rowSpacing: root.themeSpacing.labelGap
                    StatLabel { text: strings.t("durationLabel") }
                    StatValue { text: root.observedSince > 0 ? root.elapsed() : "—" }
                }
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.state === "connected"
                    columns: 2
                    columnSpacing: Commons.Style.space(24)
                    rowSpacing: root.themeSpacing.labelGap
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Commons.Style.space(6)
                        StatLabel { text: strings.t("downloadLabel") }
                        StatValue { horizontalAlignment: Text.AlignLeft; text: root.rxBytes >= 0 ? root.bytes(root.rxSpeed) + strings.t("perSecond") : "—" }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Commons.Style.space(6)
                        StatLabel { text: strings.t("uploadLabel") }
                        StatValue { horizontalAlignment: Text.AlignLeft; text: root.txBytes >= 0 ? root.bytes(root.txSpeed) + strings.t("perSecond") : "—" }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Commons.Style.space(6)
                        StatLabel { text: strings.t("receivedLabel") }
                        StatValue { horizontalAlignment: Text.AlignLeft; text: root.bytes(root.rxBytes) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Commons.Style.space(6)
                        StatLabel { text: strings.t("sentLabel") }
                        StatValue { horizontalAlignment: Text.AlignLeft; text: root.bytes(root.txBytes) }
                    }
                }
                Ui.PanelSeparator {
                    Layout.fillWidth: true
                    visible: root.state === "connected"
                    foreground: Commons.Color.foreground
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.actionTimedOut
                    text: strings.t("timeout")
                    textFormat: Text.PlainText
                    color: Commons.Color.urgent
                    font.family: root.themeFont.family
                    font.pixelSize: root.themeFont.caption
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Commons.Style.space(8)
                    Ui.Button {
                        id: openButton
                        hasCursor: root.keyboardIndex === 1 && enabled
                        onHovered: hovered => { if (hovered && enabled) root.keyboardIndex = 1 }
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        fontSize: root.themeFont.caption
                        horizontalPadding: Commons.Style.space(6)
                        focusable: false
                        text: strings.t(root.trayItem ? "open" : "launch")
                        enabled: !root.trayItem || (!!root.openEntry && root.openEntry.enabled)
                        onClicked: {
                            if (root.trayItem) root.openEntry.triggered()
                            else Quickshell.execDetached(["/opt/AmneziaVPN/bin/AmneziaVPN"])
                            root.close()
                        }
                    }
                    Ui.Button {
                        id: websiteButton
                        hasCursor: root.keyboardIndex === 2 && enabled
                        onHovered: hovered => { if (hovered && enabled) root.keyboardIndex = 2 }
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        fontSize: root.themeFont.caption
                        horizontalPadding: Commons.Style.space(6)
                        focusable: false
                        text: strings.t("website")
                        enabled: !!root.websiteEntry && root.websiteEntry.enabled
                        onClicked: {
                            root.websiteEntry.triggered()
                            root.close()
                        }
                    }
                }
            }
        }
    }
    component StatLabel: Text {
        textFormat: Text.PlainText
        color: Commons.Color.foreground
        opacity: 0.6
        font.family: root.themeFont.family
        font.pixelSize: root.themeFont.bodySmall
    }
    component StatValue: Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        color: Commons.Color.foreground
        font.family: root.themeFont.family
        font.pixelSize: root.themeFont.bodySmall
    }

}
