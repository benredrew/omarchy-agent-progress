import QtQuick
import Quickshell.Io

// One atomically-written progress record. FileView follows replacement writes,
// so writers never expose partial JSON to the bar.
Item {
  id: root
  visible: false

  property string path: ""
  property var record: null
  property string lastText: ""

  FileView {
    id: jobFile
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    // A rename-based publish can briefly race this read. Keep the last valid
    // record; the parent directory listing owns removal of finished/deleted
    // jobs, so a transient miss must not make a live job vanish from the bar.
    onLoadFailed: {}
  }

  // File-system notifications can coalesce under a high-rate producer. This
  // small reconciliation read retains the current record even when one event
  // is missed; BarWidget derives the number of wave fronts from the progress
  // delta, so no pulse is lost.
  Timer {
    interval: 120
    running: root.path !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: jobFile.reload()
  }

  // The reconciliation timer re-reads unchanged files constantly; only a
  // changed record should notify BarWidget and trigger a rebuild.
  function parse(content) {
    var text = String(content || "")
    if (text === root.lastText && root.record) return
    root.lastText = text
    try {
      var parsed = JSON.parse(text)
      root.record = parsed && typeof parsed === "object" ? parsed : null
    } catch (error) {
      root.record = null
    }
  }
}
