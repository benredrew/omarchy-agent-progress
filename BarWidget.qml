import QtQuick
import Quickshell
import Quickshell.Hyprland._GlobalShortcuts
import Quickshell.Io
import qs.Commons
import qs.Ui

// One permanent bar slot backed by the jobs in ~/.local/state/agent-progress.
// The command owns the file contract; the bar only renders its active records.
BarWidget {
  id: root
  moduleName: "benredrew.progress"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string progressDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/agent-progress"
  property var jobs: []
  // Picker rows are keyed by ID, and this list only changes when jobs start
  // or end. Rebuilding rows on every update (10 a second from a pipe) would
  // reset their particles and fronts before they crossed the row.
  property var activeIds: []
  property var jobIds: []
  property var progressSnapshot: ({})
  // Counts, rather than a boolean, preserve every progress unit that arrived
  // between FileView refreshes. A 10 Hz producer can therefore emit ten
  // distinct fronts without being visually rate-limited to one.
  property var advanceCounts: ({})
  property bool hasProgressSnapshot: false
  // Recent (time, current) samples per job, and the throughput derived from
  // them in steps (or bytes) per second.
  property var progressSamples: ({})
  property var rates: ({})
  // Jobs drawn as a continuous wavelet stream rather than one front per step.
  property var streamingIds: ({})
  // One front per step reads well up to a few dozen steps a second; past
  // that, fronts would merge into a solid sheen, so the meter streams.
  readonly property real streamEnterRate: 25
  readonly property real streamExitRate: 12
  readonly property int maximumFrontsPerUpdate: 8
  property string selectedId: ""
  property bool popupOpen: false
  property bool pickerKeysRequested: false
  property bool pickerKeysCommanded: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property var selectedJob: {
    for (var i = 0; i < jobs.length; i++) {
      if (String(jobs[i].id || "") === selectedId) return jobs[i]
    }
    return jobs.length > 0 ? jobs[0] : null
  }

  function jobFraction(job) {
    if (!job) return 0
    var total = job.total === null || job.total === undefined ? 0 : Number(job.total)
    if (total <= 0) return 0.22
    return Math.max(0.05, Math.min(1, Number(job.current || 0) / total))
  }

  readonly property real progressFraction: jobFraction(selectedJob)

  function jobById(id) {
    for (var i = 0; i < jobs.length; i++) {
      if (String(jobs[i].id || "") === id) return jobs[i]
    }
    return { id: id }
  }

  function isBytes(job) {
    return !!job && String(job.unit || "") === "bytes"
  }

  // Decimal units, scaled to `reference` so a pair reads "1.2/4.8 GB".
  readonly property var byteUnits: ["B", "KB", "MB", "GB", "TB"]
  function byteExponent(reference) {
    return reference < 1000 ? 0 : Math.min(4, Math.floor(Math.log(reference) / Math.log(1000)))
  }
  function byteValue(bytes, exponent) {
    var value = bytes / Math.pow(1000, exponent)
    return exponent === 0 || value >= 10 ? String(Math.round(value)) : value.toFixed(1)
  }
  function formatBytes(bytes) {
    var exponent = byteExponent(bytes)
    return byteValue(bytes, exponent) + " " + byteUnits[exponent]
  }

  function progressText(job) {
    var current = Number(job.current || 0)
    var total = job.total === null || job.total === undefined ? null : Number(job.total)
    var percent = total !== null && total > 0 ? " · " + String(Math.round(current * 100 / total)) + "%" : ""
    if (isBytes(job)) {
      if (!percent) return current > 0 ? formatBytes(current) : "working"
      var exponent = byteExponent(total)
      return byteValue(current, exponent) + "/" + byteValue(total, exponent) + " " + byteUnits[exponent] + percent
    }
    if (percent) return String(current) + "/" + String(total) + percent
    return current > 0 ? String(current) + (job.unit ? " " + String(job.unit) : "") : "working"
  }

  function rateText(job) {
    var rate = Number(rates[String(job.id || "")] || 0)
    if (rate <= 0) return ""
    if (isBytes(job)) return formatBytes(rate) + "/s"
    return String(Math.round(rate)) + " " + String(job.unit || "items") + "/s"
  }

  function isStreaming(job) {
    return !!job && streamingIds[String(job.id || "")] === true
  }

  // 0 at a trickle, 1 flat out, on a log scale: 10 KB/s to 100 MB/s for
  // bytes, 25 to 2,500 steps a second otherwise.
  function streamIntensity(job) {
    var rate = Number(rates[String(job ? job.id || "" : "")] || 0)
    if (rate <= 0) return 0
    var level = isBytes(job) ? (Math.log(rate) / Math.LN10 - 4) / 4 : (Math.log(rate) / Math.LN10 - 1.4) / 2
    return Math.max(0, Math.min(1, level))
  }

  // The slot is intentionally permanent. A job starting never shifts the
  // clock or Dual City.
  readonly property string label: selectedJob
    ? (compact ? String(Math.round(progressFraction * 100)) + "%" : progressText(selectedJob))
    : "Idle"

  // Placed in the centre section just before the anchor (Dual City, or
  // Omarchy's clock), the slot's right edge is pinned and only its width is
  // free. Fill the room back to the bar's left section (workspaces), less
  // whatever shares this group to the meter's left. The plugin API hides other
  // widgets, so both sections are found by `region` in this bar window's own
  // item tree and only their geometry is read. Anywhere else, keep the
  // default width.
  readonly property real defaultWidth: Style.space(152)
  readonly property real maximumWidth: Style.space(320)
  readonly property real minimumWidth: Style.space(56)
  // Visible gaps match on both sides: the workspaces end with ~9 of empty
  // padding and the anchor's text starts with ~8, so the raw gaps differ.
  readonly property real sectionGap: Style.space(4)
  property real room: defaultWidth
  property Item leftSection: null
  readonly property real slotWidth: Math.round(Math.max(minimumWidth, Math.min(maximumWidth, room)))
  readonly property bool compact: slotWidth < Style.space(128)

  function findLeftSection(item) {
    if (!item) return null
    if (item.region === "left" && item.entries !== undefined) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findLeftSection(children[i])
      if (found) return found
    }
    return null
  }

  function enclosingSection() {
    for (var item = root.parent; item; item = item.parent) {
      if (item.region !== undefined && item.entries !== undefined) return item
    }
    return null
  }

  function measureRoom() {
    // Only the group before the anchor ends left of the bar's middle; after
    // the anchor, the right edge is not pinned and growing would push it.
    var group = enclosingSection()
    var top = root
    while (top.parent) top = top.parent
    var beforeAnchor = group && group.region === "center"
      && group.mapToItem(null, group.width, 0).x <= top.width / 2
    if (vertical || !beforeAnchor) {
      if (room !== defaultWidth) room = defaultWidth
      return
    }
    if (!leftSection || !leftSection.visible) {
      leftSection = findLeftSection(top)
      if (!leftSection) return
    }
    var right = root.mapToItem(null, root.width, 0).x
    var before = root.mapToItem(null, 0, 0).x - group.mapToItem(null, 0, 0).x
    var leftEdge = leftSection.mapToItem(null, leftSection.width, 0).x
    var next = right - leftEdge - sectionGap - before
    if (Math.abs(next - room) >= 1) room = next
  }

  // Workspace and neighbour widths change with live text; a slow poll is
  // simpler than wiring every geometry signal of the shell's private items.
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.measureRoom()
  }

  readonly property string tooltip: {
    if (!selectedJob) return "No active work"
    var lines = []
    for (var i = 0; i < jobs.length; i++) {
      var job = jobs[i]
      var title = String(job.title || job.id || "Work")
      var detail = job.detail ? " — " + String(job.detail) : ""
      var rate = rateText(job)
      lines.push(title + ": " + progressText(job) + (rate ? " · " + rate : "") + detail)
    }
    return lines.join("\n")
  }

  function applyJobListing(output) {
    var ids = []
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var name = lines[i].trim()
      if (name.slice(-5) === ".json") ids.push(name.slice(0, -5))
    }
    ids.sort()
    if (JSON.stringify(ids) !== JSON.stringify(jobIds)) jobIds = ids
  }

  function selectJob(id) {
    selectedId = id
    popupOpen = false
  }

  // Keyboard movement previews another job immediately; clicking a row still
  // selects it and dismisses the picker.
  function selectRelative(delta) {
    if (jobs.length === 0) return
    var index = 0
    for (var i = 0; i < jobs.length; i++) {
      if (String(jobs[i].id || "") === selectedId) {
        index = i
        break
      }
    }
    index = (index + delta + jobs.length) % jobs.length
    selectedId = String(jobs[index].id || "")
  }

  function rebuildJobs() {
    var active = []
    var nextSnapshot = {}
    var advances = {}
    for (var i = 0; i < jobInstantiator.count; i++) {
      var job = jobInstantiator.objectAt(i)
      var record = job ? job.record : null
      if (!record) continue
      var state = String(record.state || "")
      if (state === "running" || state === "paused" || state === "blocked") {
        active.push(record)
        var id = String(record.id || "")
        var current = Number(record.current || 0)
        if (hasProgressSnapshot && progressSnapshot[id] !== undefined && current > Number(progressSnapshot[id]))
          advances[id] = current - Number(progressSnapshot[id])
        nextSnapshot[id] = current
        if (progressSnapshot[id] === undefined || current !== Number(progressSnapshot[id])) {
          if (!progressSamples[id]) progressSamples[id] = []
          progressSamples[id].push([Date.now(), current])
        }
      }
    }
    active.sort(function(a, b) {
      return String(a.startedAt || "").localeCompare(String(b.startedAt || ""))
    })
    jobs = active
    var ids = active.map(function(record) { return String(record.id || "") })
    if (JSON.stringify(ids) !== JSON.stringify(activeIds)) activeIds = ids

    var selectedStillActive = false
    for (var j = 0; j < jobs.length; j++) {
      if (String(jobs[j].id || "") === selectedId) selectedStillActive = true
    }
    if (!selectedStillActive) selectedId = jobs.length > 0 ? String(jobs[0].id || "") : ""

    progressSnapshot = nextSnapshot
    advanceCounts = advances
    if (hasProgressSnapshot && Number(advances[selectedId] || 0) > 0 && !isStreaming(selectedJob))
      Qt.callLater(function() { motion.launchFronts(Math.min(Number(advances[selectedId]), root.maximumFrontsPerUpdate)) })
    hasProgressSnapshot = true
  }

  // Throughput over the last two seconds, and the stream/front choice with
  // hysteresis so a job near the threshold doesn't flicker between modes.
  function updateRates() {
    var now = Date.now()
    var nextRates = {}
    var nextStreaming = {}
    var nextSamples = {}
    for (var i = 0; i < jobs.length; i++) {
      var job = jobs[i]
      var id = String(job.id || "")
      var samples = (progressSamples[id] || []).filter(function(sample) { return now - sample[0] <= 2000 })
      nextSamples[id] = samples
      // Measured to now, not to the latest sample, so a stalled job's rate
      // falls away instead of holding its last speed.
      var rate = 0
      if (samples.length > 1) {
        var oldest = samples[0]
        var latest = samples[samples.length - 1]
        rate = Math.max(0, (latest[1] - oldest[1]) / Math.max(0.25, (now - oldest[0]) / 1000))
      }
      nextRates[id] = rate
      var wasStreaming = streamingIds[id] === true
      nextStreaming[id] = isBytes(job) || (wasStreaming ? rate > streamExitRate : rate > streamEnterRate)
    }
    progressSamples = nextSamples
    rates = nextRates
    streamingIds = nextStreaming
  }

  Timer {
    interval: 250
    running: root.jobs.length > 0
    repeat: true
    onTriggered: root.updateRates()
  }

  // The one animation clock for the meter and the picker rows. Every Motion
  // steps on its tick, so the bar redraws at most 30 times a second however
  // many things move, and not at all when nothing does.
  Item {
    id: animationClock
    signal ticked(real dt)
    property int busy: 0
    property real lastTick: 0
    Timer {
      interval: 33
      repeat: true
      running: animationClock.busy > 0
      onRunningChanged: animationClock.lastTick = Date.now()
      onTriggered: {
        var now = Date.now()
        var dt = Math.min((now - animationClock.lastTick) / 1000, 0.1)
        animationClock.lastTick = now
        animationClock.ticked(dt)
      }
    }
  }

  // Switching jobs shows the new job's fill at once rather than gliding.
  onSelectedIdChanged: Qt.callLater(function() { motion.snap() })

  function refresh() {
    if (!listProcess.running) listProcess.running = true
  }

  readonly property bool opened: popupOpen
  function open() {
    popupOpen = true
    Qt.callLater(function() { content.forceActiveFocus() })
  }
  function close() { popupOpen = false }
  function toggle() {
    if (popupOpen) close()
    else open()
  }
  function closeForPopoutSwitch() { close() }

  // Keep the compositor binding state in step with the popup even if it is
  // toggled again before a preceding hyprctl call has exited.
  function requestPickerKeys(enabled) {
    pickerKeysRequested = enabled
    if (!pickerKeys.running) {
      pickerKeysCommanded = pickerKeysRequested
      pickerKeys.command = ["/usr/bin/hyprctl", "eval", "benredrew_progress_keys(" + (pickerKeysCommanded ? "true" : "false") + ")"]
      pickerKeys.running = true
    }
  }

  Process {
    id: listProcess
    running: false
    command: ["find", root.progressDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyJobListing(text)
    }
  }

  Instantiator {
    id: jobInstantiator
    model: root.jobIds

    delegate: ProgressJob {
      required property var modelData
      path: root.progressDir + "/" + modelData + ".json"
      onRecordChanged: root.rebuildJobs()
    }

    onObjectAdded: root.rebuildJobs()
    onObjectRemoved: root.rebuildJobs()
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "benredrew.progress"
    function open(): void { root.open() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function previous(): void { if (root.popupOpen) root.selectRelative(-1) }
    function next(): void { if (root.popupOpen) root.selectRelative(1) }
    function close(): void { root.close() }
  }

  // Hyprland invokes these in the already-running Quickshell process. Unlike
  // shell IPC, there is no process launch on each arrow or I/K keypress.
  GlobalShortcut {
    appid: "benredrew.progress"
    name: "toggle"
    description: "Toggle work progress picker"
    onPressed: root.toggle()
  }
  GlobalShortcut {
    appid: "benredrew.progress"
    name: "previous"
    description: "Previous progress timer"
    onPressed: { if (root.popupOpen) root.selectRelative(-1) }
  }
  GlobalShortcut {
    appid: "benredrew.progress"
    name: "next"
    description: "Next progress timer"
    onPressed: { if (root.popupOpen) root.selectRelative(1) }
  }
  GlobalShortcut {
    appid: "benredrew.progress"
    name: "close"
    description: "Close work progress picker"
    onPressed: root.close()
  }
  GlobalShortcut {
    appid: "benredrew.progress"
    name: "confirm"
    description: "Confirm work progress timer"
    onPressed: root.close()
  }

  // PopupWindow surfaces are mouse-focusable but do not reliably receive
  // keyboard input on this compositor. Enable picker keys only while open.
  Process {
    id: pickerKeys
    running: false
    command: []
    onExited: {
      if (root.pickerKeysCommanded !== root.pickerKeysRequested)
        root.requestPickerKeys(root.pickerKeysRequested)
    }
  }

  onPopupOpenChanged: {
    requestPickerKeys(popupOpen)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    tooltipText: root.popupOpen ? "" : root.tooltip
    // The width follows the room measured above, never the label, so changing
    // percentages do not jitter. Its fill is deliberately quieter than an OSD.
    fixedWidth: root.slotWidth
    fixedHeight: root.barSize
    active: false
    labelVisible: false
    horizontalMargin: 8
    clip: true
    onPressed: function(button) {
      if (button === Qt.LeftButton) {
        if (root.popupOpen) root.close()
        else root.open()
      }
      else root.refresh()
    }

    Rectangle {
      id: track
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(3)
      anchors.rightMargin: Style.space(8)
      height: parent.height - Style.space(10)
      z: 0
      clip: true
      radius: Style.space(3)
      color: Style.normalFillFor(root.bar.foreground, Color.accent)
      border.width: 1
      border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14)

      Rectangle {
        id: fill
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * motion.shown
        height: parent.height
        radius: parent.radius
        color: Color.accent
        opacity: root.selectedJob ? 0.66 : 0
        clip: true

        Motion {
          id: motion
          anchors.fill: parent
          z: 1
          clock: animationClock
          target: root.progressFraction
          flowing: root.isStreaming(root.selectedJob) && Number(root.rates[root.selectedId] || 0) > 0
          intensity: root.streamIntensity(root.selectedJob)
          color: root.bar.background
        }
      }
    }

    Text {
      anchors.centerIn: parent
      z: 1
      text: root.label
      textFormat: Text.PlainText
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      // Regular weight and default rendering, like Dual City's city names:
      // at 1.5x, bold native rendering fills in the eye of the "e".
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    // PopupWindow leaves keyboard focus with the previous app unless this is
    // enabled. The picker needs that focus for arrow and I/K navigation.
    grabFocus: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(330))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(6)
      focus: root.popupOpen
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up || event.key === Qt.Key_I) {
          root.selectRelative(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_K) {
          root.selectRelative(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }

      Text {
        text: "Work Progress"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        visible: root.jobs.length === 0
        text: "No active work"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: root.activeIds

        delegate: Rectangle {
          required property var modelData
          readonly property var job: root.jobById(modelData)
          readonly property bool selected: String(job.id || "") === root.selectedId
          width: content.width
          height: Style.space(42)
          radius: Style.space(3)
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          clip: true
          border.width: selected ? 2 : 1
          border.color: selected ? Color.accent : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14)

          Rectangle {
            id: rowFill
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * rowMotion.shown
            height: parent.height
            radius: parent.radius
            color: Color.accent
            opacity: parent.selected ? 0.8 : 0.56
            clip: true

            Motion {
              id: rowMotion
              anchors.fill: parent
              z: 1
              clock: animationClock
              target: root.jobFraction(job)
              // A closed picker's window is hidden, but its animations would
              // keep ticking; only animate rows while it is open.
              visible: root.popupOpen
              flowing: root.isStreaming(job) && Number(root.rates[String(job.id || "")] || 0) > 0
              intensity: root.streamIntensity(job)
              color: root.bar.background
            }
          }

          Connections {
            target: root
            function onAdvanceCountsChanged() {
              var count = Number(root.advanceCounts[String(job.id || "")] || 0)
              if (count > 0 && root.popupOpen && !root.isStreaming(job))
                Qt.callLater(function() { rowMotion.launchFronts(Math.min(count, root.maximumFrontsPerUpdate)) })
            }
          }

          // Title, and below it the agent that reported the job, when known.
          Column {
            anchors.left: parent.left
            anchors.right: progress.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)

            Text {
              width: parent.width
              text: String(job.title || job.id || "Work")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              width: parent.width
              visible: text !== ""
              text: String(job.agent || "")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.bar.foreground
              opacity: 0.7
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            id: progress
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.space(10)
            text: root.progressText(job)
            textFormat: Text.PlainText
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectJob(String(parent.job.id || ""))
          }
        }
      }
    }
  }
}
