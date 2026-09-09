import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "kevin.mxmaster"

  property var status: ({"ok": true, "connected": false, "settings": {}})
  property bool busy: false

  // Writes take ~2.5s, so they are queued and applied one at a time while the
  // UI shows the requested value optimistically.
  property var queue: []

  readonly property bool connected: status && status.connected === true
  readonly property var battery: status && status.battery ? status.battery : null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function helperArgs(action) {
    return ["python3", Qt.resolvedUrl("mx_ctl.py").toString().replace("file://", ""), action]
  }

  function settingValue(name, fallback) {
    if (!status || !status.settings || !status.settings[name]) return fallback
    var value = status.settings[name].value
    return value === undefined ? fallback : value
  }

  function settingMeta(name) {
    if (!status || !status.settings) return null
    return status.settings[name] || null
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  // Reassign a copy so QML sees the change; the object is small enough that
  // cloning is cheaper than wiring per-setting properties.
  function applySetting(name, value) {
    var next = JSON.parse(JSON.stringify(root.status))
    if (next.settings && next.settings[name]) {
      next.settings[name].value = value
      if (next.settings[name].choices) {
        var index = next.settings[name].choices.indexOf(String(value))
        next.settings[name].index = index
      }
    }
    root.status = next

    var pending = root.queue.slice()
    pending.push({"name": name, "value": String(value)})
    root.queue = pending
    pumpQueue()
  }

  function pumpQueue() {
    if (setProcess.running || root.queue.length === 0) return
    var job = root.queue[0]
    root.busy = true
    setProcess.command = root.helperArgs("set").concat([job.name, job.value])
    setProcess.running = true
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Component.onCompleted: {
    cachedProcess.running = true
    refresh()
  }

  // Paints the bar immediately from the last known state instead of waiting
  // out the ~3.5s HID++ probe on shell start.
  Process {
    id: cachedProcess
    command: root.helperArgs("cached")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.status && root.status.connected) return
        try {
          var parsed = JSON.parse(String(text || "{}"))
          if (parsed && parsed.connected) root.status = parsed
        } catch (error) {}
      }
    }
  }

  Process {
    id: statusProcess
    command: root.helperArgs("status")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          if (parsed && parsed.ok !== false) root.status = parsed
        } catch (error) {}
      }
    }
  }

  Process {
    id: setProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          if (parsed && parsed.connected) root.status = parsed
        } catch (error) {}
      }
    }
    onExited: {
      var pending = root.queue.slice(1)
      root.queue = pending
      root.busy = pending.length > 0
      pumpQueue()
    }
  }

  // Battery moves slowly; a five-minute poll keeps the probe off the hot path.
  Timer {
    interval: 300000
    repeat: true
    running: true
    onTriggered: if (!root.busy) root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍽"
    tooltipText: {
      if (!root.connected) return "MX Master · not connected"
      var name = root.status.name || "MX Master"
      var parts = [name]
      if (root.battery && root.battery.level !== null && root.battery.level !== undefined)
        parts.push(root.battery.level + "%" + (root.battery.charging ? " charging" : ""))
      parts.push(root.settingValue("dpi", "?") + " DPI")
      return parts.join(" · ")
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
