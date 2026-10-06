import QtQuick
import qs.Commons

// All motion on one meter, stepped by the widget's shared 30 Hz clock, which
// runs only while something is moving. Each tick redraws the whole bar window
// (measured: ~19% of a core at 30 Hz for even one moving pixel), so all
// motion shares one clock rather than each effect, or each record update,
// causing its own redraws.
//
// Three kinds of motion:
// - Fill: glides toward each new value, so a job publishing a few times a
//   second still grows smoothly instead of in steps.
// - Fronts: a bright band per step, for jobs moving a few steps a second.
//   Fronts are independent, so at 10 steps a second several cross at once.
// - Particles: for jobs too fast for one front per step (byte transfers,
//   thousands of steps a second), individual pixels stream along at their own
//   heights and speeds with short fading trails, dark against the fill.
//   Faster throughput emits more and moves them faster; when the job stalls,
//   emission stops and the stream drains away.
//
// Fixed pools are recycled, so running motion allocates nothing.
Item {
  id: stream

  // Whether particles are being emitted.
  property bool flowing: false
  // 0 (a trickle) to 1 (flat out).
  property real intensity: 0
  // Particle colour. Dark by default: light labels on top stay readable.
  property color color: "black"

  // The shared clock: an item with a `ticked(dt)` signal and a `busy` count.
  property Item clock: null
  // Fraction of the fill to show; `shown` glides toward it.
  property real target: 0
  property real shown: 0
  readonly property bool settling: Math.abs(target - shown) > 0.0005

  readonly property bool busy: visible && (flowing || moving || settling)
  onBusyChanged: if (clock) clock.busy += busy ? 1 : -1
  Component.onDestruction: if (busy && clock) clock.busy -= 1

  // Jumps back (a restarted job) and changes made while hidden snap.
  onTargetChanged: if (target < shown || !visible) shown = target
  onVisibleChanged: shown = target
  function snap() { shown = target }

  readonly property int poolSize: 160
  readonly property int frontPoolSize: 12
  readonly property real frontSpeed: 250
  property real spawnBudget: 0
  property bool moving: false

  clip: true

  // Steps that arrive in one update start staggered, one behind another, so
  // each still reads as its own front rather than a single stacked band.
  readonly property real frontSpacing: Style.space(20)
  function launchFronts(count) {
    for (var n = 0; n < count; n++) {
      for (var i = 0; i < fronts.count; i++) {
        var front = fronts.itemAt(i)
        if (!front || front.live) continue
        front.x = -front.width - n * frontSpacing
        front.live = true
        break
      }
    }
    moving = true
  }

  function spawn() {
    for (var i = 0; i < pool.count; i++) {
      var particle = pool.itemAt(i)
      if (!particle || particle.live) continue
      var size = Math.random() < 0.3 ? 1 : 1.5
      particle.dot = size
      particle.height = size
      particle.speed = (60 + 340 * intensity) * (0.6 + Math.random() * 0.8)
      // The trail grows with speed: a still frame still reads as motion.
      particle.width = size + particle.speed * 0.035
      particle.y = Math.round(Math.random() * Math.max(0, stream.height - size) * 2) / 2
      particle.x = -particle.width
      particle.opacity = 0.45 + Math.random() * 0.55
      particle.live = true
      return
    }
  }

  function advance(items, dt) {
    var live = false
    for (var i = 0; i < items.count; i++) {
      var item = items.itemAt(i)
      if (!item || !item.live) continue
      item.x += item.speed * dt
      if (item.x > stream.width) item.live = false
      else live = true
    }
    return live
  }

  function step(dt) {
    if (settling) shown += (target - shown) * (1 - Math.exp(-dt / 0.2))
    if (!settling) shown = target
    if (flowing) {
      spawnBudget += (15 + 165 * intensity) * dt
      while (spawnBudget >= 1) {
        spawnBudget -= 1
        spawn()
      }
    } else {
      spawnBudget = 0
    }
    var frontsLive = advance(fronts, dt)
    var particlesLive = advance(pool, dt)
    moving = frontsLive || particlesLive
  }

  Connections {
    target: stream.clock
    enabled: stream.busy
    function onTicked(dt) { stream.step(dt) }
  }

  Repeater {
    id: fronts
    model: stream.frontPoolSize
    delegate: Rectangle {
      property bool live: false
      readonly property real speed: stream.frontSpeed
      visible: live
      width: Style.space(72)
      height: stream.height
      opacity: 0.9
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.06) }
        GradientStop { position: 0.70; color: Qt.rgba(1, 1, 1, 0.24) }
        GradientStop { position: 0.88; color: Qt.rgba(1, 1, 1, 0.96) }
        GradientStop { position: 0.93; color: Qt.rgba(1, 1, 1, 0.96) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
  }

  Repeater {
    id: pool
    model: stream.poolSize
    delegate: Item {
      id: particle
      property bool live: false
      property real speed: 0
      property real dot: 1
      visible: live

      // Trail, fading in toward the head.
      Rectangle {
        anchors.left: parent.left
        anchors.right: head.left
        height: parent.height
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Qt.rgba(stream.color.r, stream.color.g, stream.color.b, 0) }
          GradientStop { position: 1.0; color: Qt.rgba(stream.color.r, stream.color.g, stream.color.b, 0.45) }
        }
      }
      Rectangle {
        id: head
        anchors.right: parent.right
        width: particle.dot
        height: parent.height
        color: stream.color
      }
    }
  }
}
