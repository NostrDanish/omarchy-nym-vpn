import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "master.nym-vpn"
  ipcTarget: "master.nym-vpn"
  manageIpc: true

  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("status.py").toString().replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool live: phase === "connected"
  readonly property color markColor: phase === "error" ? urgent : (live ? foreground : dim)
  readonly property string barLabel: "NYM"

  property string phase: "idle"
  property string mode: "wg"
  property string label: "Off"
  property string detail: "Tunnel down"
  property string daemon: ""
  property string errorText: ""
  property string entryCode: ""
  property string exitCode: ""
  property string entryName: ""
  property string exitName: ""
  property string entryCity: ""
  property string exitCity: ""
  property real entryLat: 0
  property real entryLon: 0
  property real exitLat: 0
  property real exitLon: 0
  property bool hasEntry: false
  property bool hasExit: false
  property bool hasYou: false
  property real youLat: 0
  property real youLon: 0
  property string youCity: ""
  property var countries: []
  property var nodes: []
  property bool actionRunning: false
  property real flow: 0
  property real rxRate: 0
  property real txRate: 0
  property real rxTotal: 0
  property real txTotal: 0
  property real entryPing: -1
  property real exitPing: -1
  property var trafficHistory: []

  // v2 "full" payload state
  property bool authBlocked: false
  property string lastPhase: ""
  property bool lanAllowed: true
  property bool adBlockOn: false
  property bool ipv6On: false
  property bool ctOn: false
  property bool netstackOn: true
  property bool netStatsOn: false
  property bool socks5Enabled: false
  property string socks5Address: ""
  property int socks5Connections: 0
  property bool socks5Editing: false
  property string socksCc: ""
  property var excludedPids: []
  property bool splitSupported: true
  property bool loggedIn: false
  property string identity: ""
  property string accountState: ""
  property string subKind: ""
  property string subStatus: ""
  property real quotaUsed: 0
  property real quotaLimit: 0
  property string quotaReset: ""
  property int devicesLeft: -1
  property var dnsServers: []
  property var favEntryCodes: []
  property var favExitCodes: []
  property var recentsWgEntry: []
  property var recentsWgExit: []
  property string diagText: ""
  property int pidDraft: 0

  readonly property string routeMeta: {
    var s = root.live ? (root.mode === "mix" ? "Mixnet 5-hop up" : "WireGuard 2-hop up") : "Tunnel down"
    if (root.entryCode && root.exitCode) s += " · " + root.entryCode + " → " + root.exitCode
    return s
  }
  readonly property bool dialogOpen: logoutDialog.opened || splitClearDialog.opened || diagDialog.opened
  readonly property bool entryFav: root.favEntryCodes.indexOf(root.entryCode) >= 0
  readonly property bool exitFav: root.favExitCodes.indexOf(root.exitCode) >= 0
  readonly property string dnsCaption: root.dnsServers.length > 0 ? "Custom: " + root.dnsServers.join(", ") : "Default"
  readonly property string socksCaption: root.socks5Enabled
    ? root.socks5Address + " · " + root.socks5Connections + " connection" + (root.socks5Connections === 1 ? "" : "s")
    : "Off"

  implicitWidth: Math.max(button.implicitWidth, 52)
  implicitHeight: button.implicitHeight > 0 ? button.implicitHeight : 26

  onPhaseChanged: {
    if (root.lastPhase !== "" && root.lastPhase !== "idle" && root.lastPhase !== phase
        && (phase === "connected" || phase === "error" || phase === "disconnected")) {
      if (phase === "connected") root.notify("Connected · " + root.entryCode + " → " + root.exitCode)
      else if (phase === "disconnected") root.notify("Disconnected")
      else root.notify("Error: " + root.errorText)
    }
    root.lastPhase = phase
  }

  function fmtRate(b) {
    if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s"
    if (b >= 1024) return (b / 1024).toFixed(1) + " kB/s"
    return Math.round(b) + " B/s"
  }

  function fmtTotal(b) {
    if (b >= 1073741824) return (b / 1073741824).toFixed(2) + " GB"
    if (b >= 1048576) return (b / 1048576).toFixed(0) + " MB"
    return (b / 1024).toFixed(0) + " kB"
  }

  function midEllipsis(s, max) {
    s = String(s || "")
    if (s.length <= max) return s
    var half = Math.max(1, Math.floor((max - 1) / 2))
    return s.slice(0, half) + "…" + s.slice(s.length - half)
  }

  function codeFromLocation(loc) {
    var m = /\[([A-Za-z]{2})\]\s*$/.exec(String(loc || ""))
    return m ? m[1].toUpperCase() : ""
  }

  function favCodes(list) {
    var out = []
    var src = list || []
    for (var i = 0; i < src.length; i++) {
      var c = String(src[i].code || "")
      if (c && out.indexOf(c) < 0) out.push(c)
    }
    return out
  }

  function applyStatus(rawText) {
    try {
      var data = JSON.parse(String(rawText || "{}"))
      phase = String(data.phase || "idle")
      mode = String(data.mode || "wg")
      label = String(data.label || "Off")
      detail = String(data.detail || "")
      daemon = String(data.daemon || "")
      errorText = String(data.error || "")
      if (data.entry) setCountry("entry", String(data.entry), data)
      if (data.exit) setCountry("exit", String(data.exit), data)
      if (data.youLat !== undefined && data.youLat !== null) {
        youLat = Number(data.youLat)
        youLon = Number(data.youLon)
        youCity = String(data.youCity || "")
        hasYou = true
      }
      if (data.rxRate !== undefined) rxRate = Number(data.rxRate) || 0
      if (data.txRate !== undefined) txRate = Number(data.txRate) || 0
      if (data.rxTotal !== undefined) rxTotal = Number(data.rxTotal) || 0
      if (data.txTotal !== undefined) txTotal = Number(data.txTotal) || 0
      if (data.entryPing !== undefined && data.entryPing !== null) entryPing = Number(data.entryPing)
      if (data.exitPing !== undefined && data.exitPing !== null) exitPing = Number(data.exitPing)
      if (data.rxRate !== undefined && root.opened) {
        var hist = trafficHistory.slice()
        hist.push({ rx: rxRate, tx: txRate })
        if (hist.length > 60) hist = hist.slice(hist.length - 60)
        trafficHistory = hist
      }
    } catch (e) {
      phase = "error"
      errorText = "Could not read Nym status"
    }
  }

  function applyFull(rawText) {
    root.applyStatus(rawText)
    try {
      var data = JSON.parse(String(rawText || "{}"))
      root.authBlocked = false
      if (data.tunnel) {
        // Daemon truth wins over the local mode guess.
        mode = data.tunnel.twoHop ? "wg" : "mix"
        ipv6On = !!data.tunnel.ipv6
        netstackOn = !!data.tunnel.netstack
        ctOn = !!data.tunnel.circumvention
      }
      if (data.account) {
        loggedIn = !!data.account.loggedIn
        identity = String(data.account.identity || "")
        accountState = String(data.account.state || "")
        subKind = String(data.account.subscriptionKind || "")
        subStatus = String(data.account.subscriptionStatus || "")
        quotaUsed = data.account.quotaUsedGb !== undefined ? Number(data.account.quotaUsedGb) : 0
        quotaLimit = data.account.quotaLimitGb !== undefined && data.account.quotaLimitGb !== null ? Number(data.account.quotaLimitGb) : 0
        quotaReset = String(data.account.quotaReset || "")
        devicesLeft = data.account.devicesLeft !== undefined && data.account.devicesLeft !== null ? Number(data.account.devicesLeft) : -1
      }
      if (data.dns) dnsServers = data.dns.servers || []
      lanAllowed = data.lan === "allow"
      adBlockOn = !!data.adBlock
      if (data.socks5) {
        socks5Enabled = !!data.socks5.enabled
        socks5Address = String(data.socks5.address || "")
        socks5Connections = Number(data.socks5.connections) || 0
        if (socks5Enabled) socks5Editing = false
      }
      excludedPids = data.excludedProcesses || []
      if (data.splitSupported !== undefined) splitSupported = !!data.splitSupported
      if (data.networkStats) netStatsOn = !!data.networkStats.enabled
      var favs = data.favorites || {}
      favEntryCodes = favCodes(favs.entry)
      favExitCodes = favCodes(favs.exit)
      var rec = data.recents || {}
      recentsWgEntry = (rec.wgEntry || []).slice(0, 3)
      recentsWgExit = (rec.wgExit || []).slice(0, 3)
    } catch (e) {}
  }

  function setCountry(kind, code, data) {
    var prefix = kind === "entry" ? "entry" : "exit"
    if (kind === "entry") entryCode = code
    else exitCode = code
    var row = countryByCode(code)
    var name = data && data[prefix + "Name"] ? String(data[prefix + "Name"]) : (row ? row.name : code)
    var city = data && data[prefix + "City"] ? String(data[prefix + "City"]) : (row ? row.city : "")
    var lat = data && data[prefix + "Lat"] !== undefined && data[prefix + "Lat"] !== null ? Number(data[prefix + "Lat"]) : (row ? Number(row.lat) : 0)
    var lon = data && data[prefix + "Lon"] !== undefined && data[prefix + "Lon"] !== null ? Number(data[prefix + "Lon"]) : (row ? Number(row.lon) : 0)
    if (kind === "entry") {
      entryName = name
      entryCity = city
      entryLat = lat
      entryLon = lon
      hasEntry = true
    } else {
      exitName = name
      exitCity = city
      exitLat = lat
      exitLon = lon
      hasExit = true
    }
  }

  function countryByCode(code) {
    for (var i = 0; i < countries.length; i++) {
      if (countries[i].code === code) return countries[i]
    }
    return null
  }

  function pickerOptions(kind) {
    var out = []
    for (var i = 0; i < countries.length; i++) {
      var c = countries[i]
      var count = kind === "entry" ? c.entry : c.exit
      if (!count) continue
      out.push({
        value: String(c.code),
        label: String(c.code) + " · " + String(c.name || c.code),
        description: String(count) + (count === 1 ? " gateway" : " gateways") + (c.city ? " · " + c.city : "")
      })
    }
    return out
  }

  function refresh() {
    // Passive path only — daemon actions happen on explicit keys/clicks,
    // never on a timer, so nothing here can prompt.
    if (!statusProc.running) statusProc.running = true
  }

  function refreshStats() {
    if (root.opened && !statsProc.running) statsProc.running = true
  }

  function loadCatalog() {
    if (!catalogProc.running) catalogProc.running = true
  }

  function runFull() {
    if (root.opened && !fullProc.running) fullProc.running = true
  }

  function applyCatalog(rawText) {
    try {
      var data = JSON.parse(String(rawText || "{}"))
      countries = data.countries || []
      nodes = data.nodes || []
      if (data.error) errorText = String(data.error)
      if (entryCode) setCountry("entry", entryCode, {})
      if (exitCode) setCountry("exit", exitCode, {})
    } catch (e) {
      errorText = "Could not read the gateway directory"
    }
  }

  // Shared daemon-action guard: one action at a time, "ask once" notice,
  // full refresh when the process exits.
  function runDaemon(args) {
    if (actionRunning) return
    actionRunning = true
    errorText = "Asking the daemon once…"
    actionProc.command = ["/usr/bin/python3", helper].concat(args)
    actionProc.running = true
  }

  // Small actions whose output is just {ok, error} (toggle/dns/socks5/split/fav/mode).
  function runHelper(args) {
    if (actionRunning) return
    actionRunning = true
    errorText = "Asking the daemon once…"
    actProc.command = ["/usr/bin/python3", helper].concat(args)
    actProc.running = true
  }

  function afterAction(rawText) {
    try {
      var d = JSON.parse(String(rawText || "{}"))
      if (d.authBlocked) {
        authBlocked = true
        errorText = String(d.error || "Daemon action blocked — login required")
        return
      }
      if (d.ok === false) errorText = String(d.error || "Daemon action failed")
      else errorText = ""
    } catch (e) {}
  }

  function applyAction(rawText) {
    try {
      var d = JSON.parse(String(rawText || "{}"))
      if (d.authBlocked) {
        authBlocked = true
        errorText = String(d.error || "Daemon action blocked — login required")
        return
      }
    } catch (e) {}
    root.applyStatus(rawText)
  }

  function setMode(m) {
    if (m === mode || actionRunning) return
    mode = m
    runHelper(["mode", m])
  }

  function connectRoute() {
    if (!entryCode || !exitCode) {
      errorText = "Pick an entry country and an exit country"
      return
    }
    if (entryCode === exitCode) {
      errorText = "Entry and exit must be different countries"
      return
    }
    runDaemon(["apply", entryCode, exitCode, mode])
  }

  function disconnectRoute() {
    if (!root.live) return
    runDaemon(["disconnect"])
  }

  function pickFavorite(side, code) {
    if (actionRunning) return
    root.setCountry(side, code, {})
    root.connectRoute()
  }

  function toggleFavorite(side, code) {
    if (!code || actionRunning) return
    var fav = side === "entry" ? favEntryCodes : favExitCodes
    var has = fav.indexOf(code) >= 0
    runHelper([has ? "fav-remove-" + side : "fav-add-" + side, code])
  }

  function applyCustomDns() {
    var t = dnsField.text.replace(/\s+/g, "")
    if (t === "" || !/^[0-9.,]+$/.test(t)) {
      errorText = "DNS must be comma-separated IPv4 addresses"
      return
    }
    runHelper(["dns", "set", t])
  }

  function socks5Toggle() {
    if (actionRunning) return
    if (socks5Enabled) {
      runHelper(["socks5", "off"])
    } else {
      if (socksAddrField.text === "") socksAddrField.text = "127.0.0.1:1080"
      socks5Editing = true
    }
  }

  function socks5Start() {
    var addr = socksAddrField.text.trim()
    if (addr === "") {
      errorText = "SOCKS5 listen address required"
      return
    }
    var args = ["socks5", "on", addr]
    if (root.socksCc) args.push(root.socksCc)
    runHelper(args)
  }

  function doLogin() {
    var phrase = mnemonicField.text.trim()
    if (phrase === "") {
      errorText = "Enter your recovery phrase"
      return
    }
    if (actionRunning) return
    actionRunning = true
    errorText = "Asking the daemon once…"
    // Mnemonic travels via the process environment, never argv.
    loginProc.environment = ({ "NYM_MNEMONIC": phrase })
    loginProc.command = ["/usr/bin/python3", helper, "login"]
    loginProc.running = true
    mnemonicField.text = ""
  }

  function runDiag() {
    if (actionRunning) return
    actionRunning = true
    errorText = "Running diagnostic (up to 3 min)…"
    diagProc.running = true
  }

  function openApp() {
    appProc.running = true
  }

  function notify(msg) {
    notifyProc.command = ["notify-send", "NymVPN", msg]
    if (!notifyProc.running) notifyProc.running = true
  }

  function closeDialogs() {
    logoutDialog.opened = false
    splitClearDialog.opened = false
    diagDialog.opened = false
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.refreshStats()
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.runFull()
  }

  NumberAnimation on flow {
    running: root.opened && root.live
    from: 0
    to: 1
    duration: 2600
    loops: Animation.Infinite
  }

  onOpenedChanged: if (opened) {
    loadCatalog()
    runFull()
    refreshStats()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: statusProc
    command: ["/usr/bin/python3", root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: statsProc
    command: ["/usr/bin/python3", root.helper, "stats"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: catalogProc
    command: ["/usr/bin/python3", root.helper, "catalog"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCatalog(text)
    }
  }

  Process {
    id: fullProc
    command: ["/usr/bin/python3", root.helper, "full"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyFull(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAction(text)
    }
    onExited: {
      root.actionRunning = false
      root.runFull()
    }
  }

  Process {
    id: actProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.afterAction(text)
    }
    onExited: {
      root.actionRunning = false
      root.runFull()
    }
  }

  Process {
    id: loginProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || "{}"))
          if (d.authBlocked) {
            root.authBlocked = true
            root.errorText = String(d.error || "Login blocked")
          } else if (d.ok === false) {
            root.errorText = String(d.error || "Login failed")
          } else {
            root.errorText = ""
          }
        } catch (e) {}
      }
    }
    onExited: {
      loginProc.environment = ({}) // never keep the mnemonic on the Process object
      root.actionRunning = false
      root.runFull()
    }
  }

  Process {
    id: diagProc
    command: ["/usr/bin/python3", root.helper, "diag"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || "{}"))
          if (d.authBlocked) {
            root.authBlocked = true
            root.errorText = String(d.error || "Diagnostic blocked — login required")
          } else if (d.ok === false) {
            root.errorText = String(d.error || "Diagnostic failed")
            root.diagText = String(d.raw || d.error || "").slice(0, 4000)
          } else {
            root.errorText = ""
            root.diagText = String(d.raw || "").slice(0, 4000)
          }
        } catch (e) {
          root.diagText = String(text || "").slice(0, 4000)
        }
      }
    }
    onExited: {
      root.actionRunning = false
      root.runFull()
    }
  }

  Process {
    id: notifyProc
    command: ["notify-send", "NymVPN", ""]
  }

  Process {
    id: appProc
    command: ["gtk-launch", "nym-vpn"]
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    labelVisible: true
    hasVisualContent: true
    active: !root.live
    tooltipText: "NYM · " + root.detail
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: entryDrop.popupOpen || exitDrop.popupOpen || socksCcDrop.popupOpen || mnemonicField.activeFocus
      onCloseRequested: {
        if (root.dialogOpen) root.closeDialogs()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onDeleteRequested: if (!root.dialogOpen) root.runDaemon(["quick", "mix"])
      onTextKey: function(t) {
        if (root.dialogOpen) return
        if (t === "c" || t === "C") root.connectRoute()
        else if (t === "d" || t === "D") root.disconnectRoute()
        else if (t === "o" || t === "O") root.openApp()
        else if (t === "r" || t === "R") { root.runFull(); root.refreshStats() }
        else if (t === "q" || t === "Q") root.runDaemon(["quick", "wg"])
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "NYM"
            meta: root.routeMeta
            detail: root.label !== "" ? root.label.toUpperCase() : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.live ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "◈"
                color: root.markColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "⟳"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.actionRunning
                tooltipText: "Refresh"
                onClicked: root.refresh()
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Globe {
            width: parent.width
            height: Style.space(220)
            ink: root.foreground
            dim: root.dim
            live: root.live
            mode: root.mode
            flow: root.flow
            nodes: root.nodes
            hasYou: root.hasYou
            youLat: root.youLat
            youLon: root.youLon
            youCity: root.youCity
            hasEntry: root.hasEntry
            hasExit: root.hasExit
            entryLat: root.entryLat
            entryLon: root.entryLon
            exitLat: root.exitLat
            exitLon: root.exitLon
            entryCode: root.entryCode
            exitCode: root.exitCode
            entryCity: root.entryCity
            exitCity: root.exitCity
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            Text {
              text: "YOU" + (root.youCity ? " · " + root.youCity : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }
            Text { text: "→"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text {
              text: root.entryCode ? root.entryCode + (root.entryCity ? " · " + root.entryCity : "") : "entry —"
              color: root.entryCode ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              textFormat: Text.PlainText
            }
            Text {
              visible: root.mode === "mix"
              text: "→ M1 → M2 → M3"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }
            Text { text: "→"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text {
              text: root.exitCode ? root.exitCode + (root.exitCity ? " · " + root.exitCity : "") : "exit —"
              color: root.exitCode ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              textFormat: Text.PlainText
            }
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.space(16)

            Column {
              spacing: Style.space(1)
              Text {
                text: "↓ " + (root.live ? root.fmtRate(root.rxRate) : "—")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                textFormat: Text.PlainText
              }
              Text {
                text: "download · " + root.fmtTotal(root.rxTotal)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }
            }

            Column {
              spacing: Style.space(1)
              Text {
                text: "↑ " + (root.live ? root.fmtRate(root.txRate) : "—")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                textFormat: Text.PlainText
              }
              Text {
                text: "upload · " + root.fmtTotal(root.txTotal)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }
            }

            Column {
              spacing: Style.space(1)
              Text {
                text: root.live && root.entryPing >= 0 ? Math.round(root.entryPing) + " ms" : "—"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                textFormat: Text.PlainText
              }
              Text {
                text: "entry ping" + (root.exitPing >= 0 ? " · exit " + Math.round(root.exitPing) + " ms" : "")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }
            }
          }

          TrafficGraph {
            visible: root.trafficHistory.length > 1
            width: parent.width
            height: Style.space(56)
            ink: root.foreground
            dim: root.dim
            history: root.trafficHistory
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.space(8)

            SearchableDropdown {
              id: entryDrop
              width: (parent.width - entryStar.width - exitStar.width - parent.spacing * 3) / 2
              label: "ENTRY"
              options: root.pickerOptions("entry")
              value: root.entryCode
              placeholderText: "Search countries"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(v) { root.setCountry("entry", v, {}) }
            }

            PanelActionButton {
              id: entryStar
              anchors.verticalCenter: parent.verticalCenter
              iconText: "★"
              foreground: root.entryFav ? root.foreground : root.dim
              fontFamily: root.fontFamily
              tooltipText: root.entryFav ? "Unfavorite entry " + root.entryCode : "Favorite entry " + (root.entryCode || "country")
              enabled: root.entryCode !== "" && !root.actionRunning
              onClicked: root.toggleFavorite("entry", root.entryCode)
            }

            SearchableDropdown {
              id: exitDrop
              width: (parent.width - entryStar.width - exitStar.width - parent.spacing * 3) / 2
              label: "EXIT"
              options: root.pickerOptions("exit")
              value: root.exitCode
              placeholderText: "Search countries"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(v) { root.setCountry("exit", v, {}) }
            }

            PanelActionButton {
              id: exitStar
              anchors.verticalCenter: parent.verticalCenter
              iconText: "★"
              foreground: root.exitFav ? root.foreground : root.dim
              fontFamily: root.fontFamily
              tooltipText: root.exitFav ? "Unfavorite exit " + root.exitCode : "Favorite exit " + (root.exitCode || "country")
              enabled: root.exitCode !== "" && !root.actionRunning
              onClicked: root.toggleFavorite("exit", root.exitCode)
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - Style.space(8)) / 2
              text: "FAST · 2-HOP"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              selected: root.mode !== "mix"
              enabled: !root.actionRunning && !root.authBlocked
              onClicked: root.setMode("wg")
            }
            Button {
              width: (parent.width - Style.space(8)) / 2
              text: "ANON · 5-HOP"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              selected: root.mode === "mix"
              enabled: !root.actionRunning && !root.authBlocked
              onClicked: root.setMode("mix")
            }
          }

          Button {
            width: parent.width
            text: root.actionRunning ? "Working…" : (root.live ? "Reconnect · " + root.entryCode + " → " + root.exitCode : "Connect · " + (root.entryCode || "—") + " → " + (root.exitCode || "—"))
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            selected: root.live
            enabled: !root.actionRunning && !root.authBlocked
            onClicked: root.connectRoute()
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - Style.space(8)) / 2
              text: "Disconnect"
              foreground: root.dim
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.actionRunning && !root.authBlocked && root.live
              onClicked: root.disconnectRoute()
            }

            Button {
              width: (parent.width - Style.space(8)) / 2
              text: "Open app"
              foreground: root.dim
              fontFamily: root.fontFamily
              enabled: true
              onClicked: root.openApp()
            }
          }

          Item {
            width: parent.width
            height: colQuick.implicitHeight

            Column {
              id: colQuick
              width: parent.width
              spacing: Style.space(10)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "QUICK CONNECT"; foreground: root.foreground; fontFamily: root.fontFamily }

              Row {
                width: parent.width
                spacing: Style.space(8)

                Button {
                  width: (parent.width - Style.space(8) * 2) / 3
                  text: "FASTEST · WG"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !root.actionRunning && !root.authBlocked
                  onClicked: root.runDaemon(["quick", "wg"])
                }
                Button {
                  width: (parent.width - Style.space(8) * 2) / 3
                  text: "FASTEST · ANON"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !root.actionRunning && !root.authBlocked
                  onClicked: root.runDaemon(["quick", "mix"])
                }
                Button {
                  width: (parent.width - Style.space(8) * 2) / 3
                  text: "RECONNECT"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !root.actionRunning && !root.authBlocked
                  onClicked: root.runDaemon(["reconnect"])
                }
              }
            }
          }

          Item {
            width: parent.width
            height: colFav.implicitHeight
            visible: root.favEntryCodes.length > 0 || root.favExitCodes.length > 0

            Column {
              id: colFav
              width: parent.width
              spacing: Style.space(6)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "FAVORITES"; foreground: root.foreground; fontFamily: root.fontFamily }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.favEntryCodes
                  Button {
                    property string code: String(modelData)
                    text: code
                    fontSize: Style.font.bodySmall
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    bordered: true
                    tooltipText: "Connect via entry " + code
                    enabled: !root.actionRunning && !root.authBlocked
                    onClicked: root.pickFavorite("entry", code)
                  }
                }
                Repeater {
                  model: root.favExitCodes
                  Button {
                    property string code: String(modelData)
                    text: code
                    fontSize: Style.font.bodySmall
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    bordered: true
                    tooltipText: "Connect via exit " + code
                    enabled: !root.actionRunning && !root.authBlocked
                    onClicked: root.pickFavorite("exit", code)
                  }
                }
              }
            }
          }

          Item {
            width: parent.width
            height: colRec.implicitHeight
            visible: root.recentsWgEntry.length > 0 || root.recentsWgExit.length > 0

            Column {
              id: colRec
              width: parent.width
              spacing: Style.space(6)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "RECENTS"; foreground: root.foreground; fontFamily: root.fontFamily }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.recentsWgEntry
                  Button {
                    property string cc: root.codeFromLocation(modelData && modelData.location)
                    visible: cc !== ""
                    text: cc
                    fontSize: Style.font.bodySmall
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    bordered: true
                    tooltipText: (modelData && modelData.name ? String(modelData.name) : "") + (modelData && modelData.location ? " · " + String(modelData.location) : "")
                    enabled: !root.actionRunning
                    onClicked: root.setCountry("entry", cc, {})
                  }
                }
                Repeater {
                  model: root.recentsWgExit
                  Button {
                    property string cc: root.codeFromLocation(modelData && modelData.location)
                    visible: cc !== ""
                    text: cc
                    fontSize: Style.font.bodySmall
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    bordered: true
                    tooltipText: (modelData && modelData.name ? String(modelData.name) : "") + (modelData && modelData.location ? " · " + String(modelData.location) : "")
                    enabled: !root.actionRunning
                    onClicked: root.setCountry("exit", cc, {})
                  }
                }
              }
            }
          }

          Item {
            width: parent.width
            height: colSet.implicitHeight

            Column {
              id: colSet
              width: parent.width
              spacing: Style.space(8)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "SETTINGS"; foreground: root.foreground; fontFamily: root.fontFamily }

              Grid {
                width: parent.width
                columns: 2
                spacing: Style.space(8)
                readonly property real cellW: (width - spacing) / 2

                Toggle {
                  width: parent.cellW
                  label: "LAN access"
                  checked: root.lanAllowed
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !root.authBlocked
                  onClicked: root.runHelper(["toggle", "lan", root.lanAllowed ? "off" : "on"])
                }
                Toggle {
                  width: parent.cellW
                  label: "Ad-block"
                  checked: root.adBlockOn
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !root.authBlocked
                  onClicked: root.runHelper(["toggle", "adblock", root.adBlockOn ? "off" : "on"])
                }
                Toggle {
                  width: parent.cellW
                  label: "IPv6"
                  checked: root.ipv6On
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !root.authBlocked
                  onClicked: root.runHelper(["toggle", "ipv6", root.ipv6On ? "off" : "on"])
                }
                Toggle {
                  width: parent.cellW
                  label: "Circumvention"
                  checked: root.ctOn
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !root.authBlocked
                  onClicked: root.runHelper(["toggle", "ct", root.ctOn ? "off" : "on"])
                }
                Toggle {
                  width: parent.cellW
                  label: "Netstack"
                  checked: root.netstackOn
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !root.authBlocked
                  onClicked: root.runHelper(["toggle", "netstack", root.netstackOn ? "off" : "on"])
                }
                Toggle {
                  width: parent.cellW
                  label: "Anonymous net-stats"
                  checked: root.netStatsOn
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !root.authBlocked
                  onClicked: root.runHelper(["toggle", "netstats", root.netStatsOn ? "off" : "on"])
                }
              }
            }
          }

          Item {
            width: parent.width
            height: colDns.implicitHeight

            Column {
              id: colDns
              width: parent.width
              spacing: Style.space(8)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "DNS"; foreground: root.foreground; fontFamily: root.fontFamily }

              Text {
                width: parent.width
                text: root.dnsCaption
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }

              Dropdown {
                width: parent.width
                label: "Preset"
                value: "default"
                foreground: root.foreground
                fontFamily: root.fontFamily
                options: [
                  { value: "default", label: "Default (system resolver)" },
                  { value: "cloudflare", label: "Cloudflare · 1.1.1.1, 1.0.0.1" },
                  { value: "quad9", label: "Quad9 · 9.9.9.9, 149.112.112.112" },
                  { value: "adguard", label: "AdGuard · 94.140.14.14, 94.140.15.15" }
                ]
                onChanged: function(v) {
                  if (v === "cloudflare") root.runHelper(["dns", "set", "1.1.1.1,1.0.0.1"])
                  else if (v === "quad9") root.runHelper(["dns", "set", "9.9.9.9,149.112.112.112"])
                  else if (v === "adguard") root.runHelper(["dns", "set", "94.140.14.14,94.140.15.15"])
                  else root.runHelper(["dns", "clear"])
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: dnsField
                  width: parent.width - dnsApply.width - Style.space(8)
                  placeholderText: "Custom · e.g. 1.1.1.1, 1.0.0.1"
                  foreground: root.foreground
                }
                Button {
                  id: dnsApply
                  text: "Apply"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !root.actionRunning
                  onClicked: root.applyCustomDns()
                }
              }
            }
          }

          Item {
            width: parent.width
            height: colSocks.implicitHeight

            Column {
              id: colSocks
              width: parent.width
              spacing: Style.space(8)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "SOCKS5 PROXY"; foreground: root.foreground; fontFamily: root.fontFamily }

              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  width: parent.width - socksSwitch.width - parent.spacing
                  text: "SOCKS5 proxy"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  textFormat: Text.PlainText
                }
                ToggleSwitch {
                  id: socksSwitch
                  checked: root.socks5Enabled
                  foreground: root.foreground
                  busy: root.actionRunning
                  onToggled: root.socks5Toggle()
                }
              }

              Text {
                width: parent.width
                text: root.socksCaption
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                visible: root.socks5Editing && !root.socks5Enabled

                TextField {
                  id: socksAddrField
                  width: (parent.width - socksStart.width - parent.spacing * 2) * 0.45
                  text: "127.0.0.1:1080"
                  placeholderText: "127.0.0.1:1080"
                  foreground: root.foreground
                }
                SearchableDropdown {
                  id: socksCcDrop
                  width: (parent.width - socksStart.width - parent.spacing * 2) * 0.55
                  label: "EXIT (optional)"
                  options: root.pickerOptions("exit")
                  value: root.socksCc
                  placeholderText: "Search countries"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(v) { root.socksCc = v }
                }
                Button {
                  id: socksStart
                  text: "Start"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !root.actionRunning
                  onClicked: root.socks5Start()
                }
              }
            }
          }

          Item {
            width: parent.width
            height: colSplit.implicitHeight
            visible: root.splitSupported

            Column {
              id: colSplit
              width: parent.width
              spacing: Style.space(6)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "SPLIT TUNNEL"; foreground: root.foreground; fontFamily: root.fontFamily }

              Text {
                width: parent.width
                text: "excluded PIDs: " + root.excludedPids.length
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }

              Repeater {
                model: root.excludedPids
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    width: parent.width - rmPid.width - Style.space(8)
                    text: "pid " + String(modelData)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    textFormat: Text.PlainText
                  }
                  PanelActionButton {
                    id: rmPid
                    iconText: "✕"
                    foreground: root.foreground
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    tooltipText: "Remove " + String(modelData)
                    enabled: !root.actionRunning
                    onClicked: root.runHelper(["split", "remove", String(modelData)])
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                NumberField {
                  id: pidField
                  label: "PID"
                  from: 1
                  to: 4194303
                  fieldWidth: Style.space(120)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onModified: function(v) { root.pidDraft = v }
                }
                Button {
                  text: "Add"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  anchors.verticalCenter: parent.verticalCenter
                  enabled: !root.actionRunning && root.pidDraft > 0
                  onClicked: root.runHelper(["split", "add", String(root.pidDraft)])
                }
                Button {
                  text: "Clear"
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  bordered: true
                  anchors.verticalCenter: parent.verticalCenter
                  enabled: !root.actionRunning && root.excludedPids.length > 0
                  onClicked: root.splitClearDialog.opened = true
                }
              }
            }
          }

          Item {
            width: parent.width
            height: colAcct.implicitHeight

            Column {
              id: colAcct
              width: parent.width
              spacing: Style.space(8)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "ACCOUNT"; foreground: root.foreground; fontFamily: root.fontFamily }

              Text {
                width: parent.width
                visible: !root.loggedIn
                text: "Not logged in"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }

              Column {
                width: parent.width
                spacing: Style.space(2)
                visible: root.loggedIn

                Text {
                  width: parent.width
                  text: root.midEllipsis(root.identity, 26)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: (root.accountState || "—") + (root.subKind !== "" ? " · " + root.subKind + " / " + root.subStatus : "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }
                Text {
                  width: parent.width
                  visible: root.quotaLimit > 0
                  text: root.quotaUsed + " / " + root.quotaLimit + " GB · resets " + (root.quotaReset || "—")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }
                Text {
                  width: parent.width
                  visible: root.devicesLeft >= 0
                  text: root.devicesLeft + " devices left"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                visible: !root.loggedIn

                TextField {
                  id: mnemonicField
                  width: parent.width - loginBtn.width - Style.space(8)
                  password: true
                  placeholderText: "recovery phrase"
                  foreground: root.foreground
                }
                Button {
                  id: loginBtn
                  text: "Log in"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !root.actionRunning
                  onClicked: root.doLogin()
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                visible: root.loggedIn

                Button {
                  width: (parent.width - Style.space(8)) / 2
                  text: "Log out"
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !root.actionRunning
                  onClicked: root.logoutDialog.opened = true
                }
                Button {
                  width: (parent.width - Style.space(8)) / 2
                  text: "Rotate keys"
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !root.actionRunning && !root.authBlocked
                  onClicked: root.runHelper(["rotate-keys"])
                }
              }
            }
          }

          Item {
            width: parent.width
            height: colDiag.implicitHeight

            Column {
              id: colDiag
              width: parent.width
              spacing: Style.space(8)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader { text: "DIAGNOSTIC"; foreground: root.foreground; fontFamily: root.fontFamily }

              Button {
                width: parent.width
                text: "Run diagnostic…"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                enabled: !root.actionRunning && !root.authBlocked
                onClicked: root.diagDialog.opened = true
              }

              Flickable {
                visible: root.diagText !== ""
                width: parent.width
                height: Style.space(160)
                contentWidth: width
                contentHeight: diagTextOut.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Text {
                  id: diagTextOut
                  width: parent.width
                  text: root.diagText
                  color: root.dim
                  font.family: "monospace"
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "C connect · D disconnect · R refresh · O app — daemon actions ask once, never on a timer"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }
        }
      }

      ConfirmDialog {
        id: logoutDialog
        anchors.fill: parent
        z: 20
        message: "Log out of NymVPN?"
        confirmText: "Log out"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: opened = false
        onConfirmed: {
          opened = false
          root.runHelper(["logout"])
        }
      }

      ConfirmDialog {
        id: splitClearDialog
        anchors.fill: parent
        z: 20
        message: "Remove all split-tunnel exclusions?"
        confirmText: "Clear"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: opened = false
        onConfirmed: {
          opened = false
          root.runHelper(["split", "clear"])
        }
      }

      ConfirmDialog {
        id: diagDialog
        anchors.fill: parent
        z: 20
        message: "Run diagnostic? Takes up to 3 minutes and spends an entry ticket."
        confirmText: "Run"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: opened = false
        onConfirmed: {
          opened = false
          root.runDiag()
        }
      }
    }
  }
}
