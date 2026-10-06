import QtQuick

// Particle flow for jobs that advance too fast for one wave front per step
// (byte transfers, or thousands of steps a second): individual pixels stream
// along the fill at their own heights and speeds, each with a short fading
// trail, dark against the fill. Faster throughput emits more particles and
// moves them faster. A fixed pool is recycled by one per-frame driver, so a
// running stream allocates nothing. When the job stalls, emission stops and
// the stream drains away.
Item {
  id: stream

  // Whether new particles are being emitted.
  property bool flowing: false
  // 0 (a trickle) to 1 (flat out).
  property real intensity: 0
  // Dark by default: light labels on top stay readable over the particles.
  property color color: "black"

  readonly property int poolSize: 160
  property real spawnBudget: 0
  property bool draining: false

  clip: true

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

  FrameAnimation {
    running: stream.visible && (stream.flowing || stream.draining)
    onTriggered: {
      var dt = Math.min(frameTime, 0.1)
      if (stream.flowing) {
        stream.spawnBudget += (15 + 165 * stream.intensity) * dt
        while (stream.spawnBudget >= 1) {
          stream.spawnBudget -= 1
          stream.spawn()
        }
      } else {
        stream.spawnBudget = 0
      }
      var live = false
      for (var i = 0; i < pool.count; i++) {
        var particle = pool.itemAt(i)
        if (!particle || !particle.live) continue
        particle.x += particle.speed * dt
        if (particle.x > stream.width) particle.live = false
        else live = true
      }
      stream.draining = live
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
