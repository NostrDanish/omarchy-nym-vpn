import QtQuick

// Rolling traffic graph: two lines (down = solid, up = dimmer) over the
// samples the panel collects while open. Newest on the right.
Canvas {
  id: graph
  property color ink: "#39ff14"
  property color dim: "#1a5c0e"
  property var history: []   // [{rx, tx}] bytes/sec, oldest first
  property int maxSamples: 60

  implicitWidth: 200
  implicitHeight: 56

  onPaint: paintGraph()
  onHistoryChanged: requestPaint()

  function paintGraph() {
    var ctx = getContext("2d")
    var w = width
    var h = height
    ctx.clearRect(0, 0, w, h)
    if (history.length < 2) return

    var peak = 1024
    for (var i = 0; i < history.length; i++) {
      if (history[i].rx > peak) peak = history[i].rx
      if (history[i].tx > peak) peak = history[i].tx
    }

    var n = Math.min(history.length, maxSamples)
    var step = w / (maxSamples - 1)
    var start = history.length - n

    function line(key, color, alpha, width) {
      ctx.strokeStyle = color
      ctx.globalAlpha = alpha
      ctx.lineWidth = width
      ctx.lineJoin = "round"
      ctx.beginPath()
      for (var j = 0; j < n; j++) {
        var v = history[start + j][key] / peak
        var x = j * step
        var y = h - 2 - v * (h - 6)
        if (j === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.stroke()
    }

    // area fill under the down line
    ctx.globalAlpha = 0.12
    ctx.fillStyle = ink
    ctx.beginPath()
    ctx.moveTo(0, h)
    for (var k = 0; k < n; k++) {
      var vv = history[start + k].rx / peak
      ctx.lineTo(k * step, h - 2 - vv * (h - 6))
    }
    ctx.lineTo((n - 1) * step, h)
    ctx.closePath()
    ctx.fill()

    line("tx", dim, 0.9, 1.2)
    line("rx", ink, 0.95, 1.6)
    ctx.globalAlpha = 1
  }
}
