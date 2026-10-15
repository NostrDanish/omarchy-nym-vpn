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

  readonly property string routeMeta: {
    var s = root.live ? (root.mode === "mix" ? "Mixnet 5-hop up" : "WireGuard 2-hop up") : "Tunnel down"
    if (root.entryCode && root.exitCode) s += " · " + root.entryCode + " → " + root.exitCode
    return s
  }

  implicitWidth: Math.max(button.implicitWidth, 52)
  implicitHeight: button.implicitHeight > 0 ? button.implicitHeight : 26

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
    // Passive path only — the daemon call (route-live) happens on explicit R
    // or after connect/disconnect, so opening the panel never prompts.
    if (!statusProc.running) statusProc.running = true
  }

  function refreshRoute() {
    if (!routeProc.running) routeProc.running = true
  }

  function refreshStats() {
    if (root.opened && !statsProc.running) statsProc.running = true
  }

  function loadCatalog() {
    if (!catalogProc.running) catalogProc.running = true
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

  function setMode(m) {
    if (m === mode || actionRunning) return
    mode = m
    if (actionRunning) return
    actionRunning = true
    errorText = "Asking the daemon once…"
    actionProc.command = ["/usr/bin/python3", helper, "mode", m]
    actionProc.running = true
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
    if (actionRunning) return
    actionRunning = true
    errorText = "Asking the daemon once…"
    actionProc.command = ["/usr/bin/python3", helper, "apply", entryCode, exitCode, mode]
    actionProc.running = true
  }

  function disconnectRoute() {
    if (actionRunning) return
    actionRunning = true
    errorText = "Asking the daemon once…"
    actionProc.command = ["/usr/bin/python3", helper, "disconnect"]
    actionProc.running = true
  }

  function openApp() {
    appProc.running = true
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

  NumberAnimation on flow {
    running: root.opened && root.live
    from: 0
    to: 1
    duration: 2600
    loops: Animation.Infinite
  }

  onOpenedChanged: if (opened) {
    loadCatalog()
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
    id: routeProc
    command: ["/usr/bin/python3", root.helper, "route-live"]
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
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: root.actionRunning = false
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
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(660))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: entryDrop.popupOpen || exitDrop.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "c" || t === "C") root.connectRoute()
        else if (t === "d" || t === "D") root.disconnectRoute()
        else if (t === "o" || t === "O") root.openApp()
        else if (t === "r" || t === "R") root.refreshRoute()
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
              width: (parent.width - Style.space(8)) / 2
              label: "ENTRY"
              options: root.pickerOptions("entry")
              value: root.entryCode
              placeholderText: "Search countries"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(v) { root.setCountry("entry", v, {}) }
            }

            SearchableDropdown {
              id: exitDrop
              width: (parent.width - Style.space(8)) / 2
              label: "EXIT"
              options: root.pickerOptions("exit")
              value: root.exitCode
              placeholderText: "Search countries"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(v) { root.setCountry("exit", v, {}) }
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
              enabled: !root.actionRunning
              onClicked: root.setMode("wg")
            }
            Button {
              width: (parent.width - Style.space(8)) / 2
              text: "ANON · 5-HOP"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              selected: root.mode === "mix"
              enabled: !root.actionRunning
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
            enabled: !root.actionRunning
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
              enabled: !root.actionRunning && root.live
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
    }
  }
}
