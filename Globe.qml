import QtQuick
import Quickshell.Io

Canvas {
  id: map
  property color ink: "#39ff14"
  property color dim: "#1a5c0e"
  property bool live: false
  property string mode: "wg"
  property real flow: 0
  property bool hasYou: false
  property real youLat: 0
  property real youLon: 0
  property string youCity: ""
  property bool hasEntry: false
  property real entryLat: 0
  property real entryLon: 0
  property string entryCode: ""
  property string entryCity: ""
  property bool hasExit: false
  property real exitLat: 0
  property real exitLon: 0
  property string exitCode: ""
  property string exitCity: ""
  property var nodes: []
  property var land: []

  implicitWidth: 440
  implicitHeight: 220

  FileView {
    id: landFile
    path: Qt.resolvedUrl("world-land.json").toString().replace(/^file:\/\//, "")
    watchChanges: false
    onLoaded: {
      try {
        var data = JSON.parse(text())
        map.land = data.land || []
        map.requestPaint()
      } catch (e) {}
    }
  }

  onPaint: paintMap()
  onFlowChanged: requestPaint()
  onNodesChanged: requestPaint()
  onHasYouChanged: requestPaint()
  onHasEntryChanged: requestPaint()
  onHasExitChanged: requestPaint()
  onLiveChanged: requestPaint()
  onModeChanged: requestPaint()

  // Equirectangular projection — flat map, always readable.
  function proj(lat, lon) {
    return {
      x: (lon + 180) / 360 * width,
      y: (90 - lat) / 180 * height
    }
  }

  function hopChain() {
    var chain = []
    if (hasYou) chain.push({ lat: youLat, lon: youLon, kind: "you", label: "YOU", sub: youCity })
    if (hasEntry) chain.push({ lat: entryLat, lon: entryLon, kind: "entry", label: entryCode, sub: entryCity })
    if (mode === "mix" && hasEntry && hasExit) {
      for (var i = 1; i <= 3; i++) {
        var t = i / 4
        chain.push({
          lat: entryLat + (exitLat - entryLat) * t,
          lon: entryLon + (exitLon - entryLon) * t,
          kind: "mix",
          label: "M" + i,
          sub: "mix"
        })
      }
    }
    if (hasExit) chain.push({ lat: exitLat, lon: exitLon, kind: "exit", label: exitCode, sub: exitCity })
    return chain
  }

  function paintMap() {
    var ctx = getContext("2d")
    var w = width
    var h = height
    ctx.clearRect(0, 0, w, h)

    // ---- graticule ----
    ctx.strokeStyle = ink
    ctx.globalAlpha = 0.06
    ctx.lineWidth = 1
    var lon, lat, p
    for (lon = -150; lon <= 150; lon += 30) {
      p = proj(0, lon)
      ctx.beginPath(); ctx.moveTo(p.x, 0); ctx.lineTo(p.x, h); ctx.stroke()
    }
    for (lat = -60; lat <= 60; lat += 30) {
      p = proj(lat, 0)
      ctx.beginPath(); ctx.moveTo(0, p.y); ctx.lineTo(w, p.y); ctx.stroke()
    }

    // ---- continents ----
    ctx.strokeStyle = ink
    ctx.fillStyle = ink
    for (var li = 0; li < land.length; li++) {
      var ring = land[li]
      if (ring.length < 6) continue
      ctx.beginPath()
      var started = false
      var px = 0
      for (var i = 0; i + 1 < ring.length; i += 2) {
        p = proj(ring[i + 1], ring[i])
        // antimeridian wrap guard
        if (started && Math.abs(p.x - px) > w * 0.5) started = false
        if (!started) { ctx.moveTo(p.x, p.y); started = true }
        else ctx.lineTo(p.x, p.y)
        px = p.x
      }
      ctx.globalAlpha = 0.10
      ctx.fill()
      ctx.globalAlpha = 0.45
      ctx.lineWidth = 0.7
      ctx.stroke()
    }

    // ---- gateway nodes ----
    for (var ni = 0; ni < nodes.length; ni++) {
      var n = nodes[ni]
      p = proj(n.lat, n.lon)
      ctx.globalAlpha = live ? 0.55 : 0.35
      ctx.beginPath()
      ctx.arc(p.x, p.y, 1.4, 0, Math.PI * 2)
      ctx.fill()
    }

    var chain = hopChain()
    if (chain.length < 2) {
      if (hasYou) {
        p = proj(youLat, youLon)
        ctx.globalAlpha = 1
        ctx.beginPath(); ctx.arc(p.x, p.y, 3.5, 0, Math.PI * 2); ctx.fill()
        ctx.globalAlpha = 0.35
        ctx.lineWidth = 1.2
        ctx.beginPath(); ctx.arc(p.x, p.y, 8, 0, Math.PI * 2); ctx.stroke()
      }
      return
    }

    // ---- route path (arcs between hops) ----
    var pathPts = []
    for (var hi = 0; hi + 1 < chain.length; hi++) {
      var a = proj(chain[hi].lat, chain[hi].lon)
      var b = proj(chain[hi + 1].lat, chain[hi + 1].lon)
      var segs = 16
      for (var s = 0; s <= segs; s++) {
        var t = s / segs
        var lift = Math.sin(t * Math.PI) * Math.min(20, Math.abs(b.x - a.x) * 0.12)
        pathPts.push({
          x: a.x + (b.x - a.x) * t,
          y: a.y + (b.y - a.y) * t - lift
        })
      }
    }

    ctx.strokeStyle = ink
    ctx.lineWidth = live ? 2 : 1.4
    ctx.globalAlpha = live ? 0.95 : 0.55
    ctx.beginPath()
    ctx.moveTo(pathPts[0].x, pathPts[0].y)
    for (var pi = 1; pi < pathPts.length; pi++) ctx.lineTo(pathPts[pi].x, pathPts[pi].y)
    ctx.stroke()

    // flow pulse
    if (live && pathPts.length > 1) {
      var idx = Math.floor(flow * (pathPts.length - 1))
      var fq = pathPts[idx]
      ctx.globalAlpha = 1
      ctx.beginPath(); ctx.arc(fq.x, fq.y, 3, 0, Math.PI * 2); ctx.fill()
      ctx.globalAlpha = 0.3
      ctx.beginPath(); ctx.arc(fq.x, fq.y, 7, 0, Math.PI * 2); ctx.fill()
    }

    // ---- hop markers + labels ----
    ctx.font = "bold 10px monospace"
    for (var mj = 0; mj < chain.length; mj++) {
      var hop = chain[mj]
      p = proj(hop.lat, hop.lon)
      var strong = hop.kind !== "mix"
      ctx.globalAlpha = strong ? 0.35 : 0.18
      ctx.beginPath(); ctx.arc(p.x, p.y, strong ? 7 : 5, 0, Math.PI * 2); ctx.fill()
      ctx.globalAlpha = 1
      ctx.beginPath(); ctx.arc(p.x, p.y, strong ? 3.4 : 2.2, 0, Math.PI * 2); ctx.fill()
      if (hop.kind === "you" || hop.kind === "exit") {
        ctx.lineWidth = 1.2
        ctx.globalAlpha = 0.9
        ctx.beginPath(); ctx.arc(p.x, p.y, 7, 0, Math.PI * 2); ctx.stroke()
      }
      var label = hop.kind === "you" ? "YOU" : hop.label
      ctx.globalAlpha = hop.kind === "mix" ? 0.5 : 0.95
      var tw = ctx.measureText(label).width
      var lx = Math.max(2, Math.min(w - tw - 2, p.x - tw / 2))
      var ly = p.y - 10
      if (ly < 10) ly = p.y + 16
      ctx.fillText(label, lx, ly)
    }
  }
}
