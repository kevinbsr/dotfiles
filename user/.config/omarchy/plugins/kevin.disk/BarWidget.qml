import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A disk warning that sits still instead of interrupting.
//
// This replaces a timer that fired `notify-send -u critical` every ten
// minutes. Critical notifications never expire by specification, so identical
// warnings piled up until they covered the screen -- and a warning dismissed
// twenty times a day is one nobody reads. A filesystem filling up is a state,
// not an event: it belongs in the bar, visible while it lasts and gone when it
// is fixed.
//
// Percentages come from df: used over used+available, the space that can still
// be written. Dividing by the device size counts chunks btrfs has allocated
// and will not hand out, which is why the hub used to say 90% while df said 91.
BarWidget {
  id: root
  moduleName: "kevin.disk"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property var mounts: settings && settings.mounts ? settings.mounts : ["/", "/home"]
  readonly property int warnPercent: settings && settings.warnPercent ? settings.warnPercent : 90
  readonly property int criticalPercent: settings && settings.criticalPercent ? settings.criticalPercent : 97
  readonly property int intervalSec: settings && settings.intervalSec ? settings.intervalSec : 120

  // [{ mount, percent, availGib }], worst first, only those over the threshold.
  property var alerts: []
  readonly property var worst: alerts.length > 0 ? alerts[0] : null
  readonly property bool critical: worst ? worst.percent >= root.criticalPercent : false

  // nf-md-harddisk (󰋊) and nf-md-alert (󰀦) for the point of no return.
  readonly property string icon: critical ? "󰀦" : "󰋊"

  visible: alerts.length > 0
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  function describe() {
    if (alerts.length === 0) return ""
    return alerts.map(function(a) {
      return a.mount + " " + a.percent + "% · " + a.availGib + " GiB free"
    }).join("\n") + "\nClick to see what is using the space"
  }

  Process {
    id: probe
    // POSIX output keeps one filesystem per line whatever the device name's
    // length; the awk prints only what the widget needs.
    command: ["sh", "-c",
      "df -P -B1 " + root.mounts.map(function(m) { return "'" + m + "'" }).join(" ") +
      " 2>/dev/null | awk 'NR>1 { used=$3; avail=$4; usable=used+avail;" +
      " if (usable>0) printf \"%s %d %.1f\\n\", $6, int(100*used/usable+0.999999), avail/1073741824 }'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var found = []
        String(text || "").trim().split("\n").forEach(function(line) {
          var parts = line.trim().split(/\s+/)
          if (parts.length !== 3) return
          var percent = parseInt(parts[1], 10)
          if (isNaN(percent) || percent < root.warnPercent) return
          found.push({ mount: parts[0], percent: percent, availGib: parts[2] })
        })
        found.sort(function(a, b) { return b.percent - a.percent })
        root.alerts = found
      }
    }
  }

  Timer {
    interval: root.intervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    // Urgent colouring is the whole escalation: no sticky popup, just a colour
    // the eye catches on the way past.
    foreground: root.critical ? Color.urgent : root.foreground
    tooltipText: root.describe()
    onPressed: function(b) {
      if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation ncdu " +
                                 (root.worst ? root.worst.mount : "/home"))
    }
  }
}
