import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import ".."
import "FluxModel.js" as FluxModel

// The Phone page, talking to Flux (github.com/bjarneo/flux) instead of KDE
// Connect. Same job as the KDE Connect view beside it: the devices, their
// battery, and the few actions worth reaching without opening another window.
//
// TWO WAYS IN, in this order:
//
//   1. Flux's own Backend.qml, loaded by HubIntegrations from the plugin the
//      user installed. It holds the socket to fluxd and pushes state, so the
//      page is live: a phone that unplugs updates the moment fluxd says so.
//   2. The `flux` command, polled every five seconds while this page is on
//      screen. This is what answers when the shell plugin is not installed --
//      the CLI ships with the package either way.
//
// Nothing of Flux is copied into this repository. Its backend is *loaded from
// the user's own installation*, never vendored: Flux carries no license yet
// (its Arch package records `license=('LicenseRef-unknown')`), and shipping
// someone's unlicensed source inside a plugin published on the marketplace is
// not a thing to do while waiting for them to pick one. Loading what is
// already on the machine raises no such question, and is how the Hub reaches
// every other installed engine.
//
// Nothing here runs unless Flux is installed: `available` gates the whole
// section, and the tab falls back to KDE Connect, which is untouched.
Column {
  id: root

  required property var hub
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  // Whether this page is the one on screen. The poll only runs then, the same
  // contract the rest of the Hub follows.
  property bool active: false

  // Flux's own backend when it is installed; null otherwise.
  readonly property var backend: hub && hub.hubService && hub.hubService.integrations
    ? hub.hubService.integrations.flux : null
  readonly property bool live: !!backend && !!backend.connected

  // The phone this page is about: the first paired, reachable one. Flux can
  // hold several, but the notifications and the clipboard belong to whichever
  // is actually connected, and a picker for a list of one would be furniture.
  readonly property var activeDevice: {
    for (var i = 0; i < devices.length; i++)
      if (FluxModel.usable(devices[i])) return devices[i]
    return null
  }
  // Both of these come from the pushed state, so they exist on the backend
  // path only. The CLI fallback keeps devices and actions; parsing the text of
  // `flux notifications` to rebuild this would be a second, worse reader.
  readonly property var notifications: live ? FluxModel.notifications(activeDevice, 6) : []
  readonly property int notificationTotal: live ? FluxModel.notificationCount(activeDevice) : 0
  readonly property var clips: live ? FluxModel.clipboard({ clipboard: backend.clipboard }, 3) : []

  // One clock for every "2m" on the page, ticking a minute at a time while it
  // is open. Per-row timers would be dozens of them for a number that changes
  // once a minute.
  property int nowSeconds: Math.floor(Date.now() / 1000)
  Timer {
    interval: 60000
    repeat: true
    running: root.active
    onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
  }

  function dismiss(entry) {
    if (!live || !activeDevice || !entry) return
    backend.call("notification.dismiss", { device: activeDevice.id, id: entry.id }, function () {})
  }

  // Copying back into this machine's clipboard is a local act; Flux has no
  // method for it, and wl-copy is what the rest of the Hub uses.
  function copyLocally(entry) {
    if (!entry || !entry.text) return
    copyProc.command = ["wl-copy", "--", String(entry.text)]
    copyProc.running = true
  }

  // Live state when the backend is there, polled state when it is not.
  readonly property var devices: live ? FluxModel.devices({ devices: backend.devices }) : polledDevices

  property var polledDevices: []
  property bool ready: false
  // Whether Flux is on this machine at all. One probe decides it: `flux
  // status` either answers or the command is not there, and the tab shows the
  // KDE Connect setup instead. Checked once at load, not polled -- a plugin
  // appearing mid-session is not worth a timer.
  property bool available: false
  onBackendChanged: if (backend) available = true
  property string errorText: ""
  readonly property var pairing: FluxModel.pendingPairing(devices)

  function refresh() {
    // The backend pushes; only the CLI path has anything to poll.
    if (live) return
    if (!statusProc.running) statusProc.running = true
  }

  // One call, whichever way in is available. The RPC method names and their
  // one parameter are Flux's own (`ring`, `clipboard.send`, `pair.request`,
  // `pair.accept`, `pair.reject`, all taking { device: <id> }); the CLI verbs
  // take the device *name* instead, which is why both forms are passed in.
  function act(method, cliArgs, device) {
    if (live) {
      backend.call(method, { device: device.id }, function () {})
      return
    }
    actionProc.command = ["flux"].concat(cliArgs)
    actionProc.running = true
  }

  function run(args) {
    actionProc.command = ["flux"].concat(args)
    actionProc.running = true
  }

  onActiveChanged: {
    if (active) refresh()
    poll.running = active && available && !live
  }
  // Losing the socket falls back to polling rather than to an empty page.
  onLiveChanged: {
    poll.running = active && available && !live
    if (!live) refresh()
  }

  // The probe runs whether or not the page is on screen: the tab needs the
  // answer to decide which phone stack to draw before anyone opens it.
  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["flux", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.polledDevices = FluxModel.devices(JSON.parse(String(text || "")))
          root.errorText = ""
          root.available = true
        } catch (error) {
          root.errorText = "Could not read the Flux status."
        }
        root.ready = true
      }
    }
    onExited: function(code) {
      if (code !== 0) {
        // 127 is "no flux here"; anything else is fluxd being down or busy.
        // Neither is worth a red line on a page the person may not even use.
        if (code === 127) root.available = false
        // fluxd not running is the ordinary case here, not an error worth a
        // red line: the tab simply offers to start it.
        root.polledDevices = []
        root.ready = true
      }
    }
  }

  Process {
    id: actionProc
    onExited: Qt.callLater(root.refresh)
  }

  Process { id: copyProc }

  Timer {
    id: poll
    interval: 5000
    repeat: true
    onTriggered: root.refresh()
  }

  width: parent ? parent.width : 0
  spacing: Style.space(8)

  Text {
    textFormat: Text.PlainText
    text: "FLUX"
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
    font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1
  }

  Text {
    textFormat: Text.PlainText
    visible: root.errorText !== ""
    width: parent.width
    text: root.errorText
    color: Color.urgent
    wrapMode: Text.WordWrap
    font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
  }

  Text {
    textFormat: Text.PlainText
    visible: root.ready && root.devices.length === 0 && root.errorText === ""
    width: parent.width
    text: "No devices yet. Open Flux on the phone with both on the same network, then pair."
    color: root.dim
    wrapMode: Text.WordWrap
    font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
  }

  // A device asking to pair takes the whole attention: the key has to be read
  // off both screens and compared, which is the one moment this page cannot
  // do anything useful on its own.
  Rectangle {
    visible: !!root.pairing
    width: parent.width
    height: pairColumn.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)

    Column {
      id: pairColumn
      x: Style.space(12); y: Style.space(12)
      width: parent.width - Style.space(24)
      spacing: Style.spacing.xs

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.pairing ? root.pairing.name + " wants to pair" : ""
        color: root.foreground
        font.family: root.fontFamily; font.pixelSize: Style.font.body; font.weight: Font.Medium
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.pairing && root.pairing.pairKey ? "Key " + root.pairing.pairKey + " — it must match the phone" : "Compare the key on both screens"
        color: root.dim
        wrapMode: Text.WordWrap
        font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
      Row {
        spacing: Style.spacing.xs
        Button {
          text: "Accept"
          bordered: true
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: if (root.pairing) root.act("pair.accept", ["accept", root.pairing.name], root.pairing)
        }
        Button {
          text: "Reject"
          bordered: true
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: if (root.pairing) root.act("pair.reject", ["reject", root.pairing.name], root.pairing)
        }
      }
    }
  }

  Repeater {
    model: root.devices

    delegate: Item {
      id: row
      required property var modelData
      width: parent ? parent.width : 0
      height: Math.max(rowText.implicitHeight, rowActions.implicitHeight) + Style.spacing.sm

      Column {
        id: rowText
        anchors.left: parent.left
        anchors.right: rowActions.left
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: FluxModel.deviceTitle(row.modelData)
          color: row.modelData.online ? root.foreground : root.dim
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.weight: Font.Medium
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: FluxModel.deviceSubtitle(row.modelData)
          color: root.dim
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: rowActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        PanelActionButton {
          visible: FluxModel.usable(row.modelData)
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰂚"
          tooltipText: "Ring the phone"
          onClicked: root.act("ring", ["ring", "--device", row.modelData.name], row.modelData)
        }
        PanelActionButton {
          visible: FluxModel.usable(row.modelData)
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰅇"
          tooltipText: "Send this computer's clipboard"
          onClicked: root.act("clipboard.send", ["clip", "--device", row.modelData.name], row.modelData)
        }
        Button {
          visible: !row.modelData.paired
          text: "Pair"
          bordered: true
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: root.act("pair.request", ["pair", row.modelData.name], row.modelData)
        }
      }
    }
  }

  // ---- What the phone is showing.
  PanelSeparator { visible: root.notifications.length > 0; width: parent.width }

  Text {
    textFormat: Text.PlainText
    visible: root.notifications.length > 0
    text: "NOTIFICATIONS" + (root.notificationTotal > root.notifications.length
      ? "  " + root.notifications.length + " of " + root.notificationTotal : "")
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
    font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1
  }

  Repeater {
    model: root.notifications

    delegate: Item {
      id: note
      required property var modelData
      width: parent ? parent.width : 0
      height: noteText.implicitHeight + Style.spacing.xs

      Column {
        id: noteText
        anchors.left: parent.left
        anchors.right: noteActions.left
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: FluxModel.notificationMeta(note.modelData, root.nowSeconds)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }
        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: String(note.modelData.title || "")
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.weight: Font.Medium
        }
        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: String(note.modelData.text || "")
          color: root.dim
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.Wrap
          font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: noteActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        PanelActionButton {
          visible: !!note.modelData.dismissable
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰅖"
          tooltipText: "Dismiss on the phone"
          onClicked: root.dismiss(note.modelData)
        }
      }
    }
  }

  // ---- What the two machines have copied.
  PanelSeparator { visible: root.clips.length > 0; width: parent.width }

  Text {
    textFormat: Text.PlainText
    visible: root.clips.length > 0
    text: "SHARED CLIPBOARD"
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
    font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1
  }

  Repeater {
    model: root.clips

    // An Item, not a Column: a Column refuses anchors from its children, and
    // the whole row has to be one click target.
    delegate: Item {
      id: clip
      required property var modelData
      width: parent ? parent.width : 0
      height: clipText.implicitHeight + Style.spacing.xs

      Column {
        id: clipText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: String(clip.modelData.text || "")
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: FluxModel.clipboardMeta(clip.modelData, root.nowSeconds) + " · click to copy here"
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
          elide: Text.ElideRight
          font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.copyLocally(clip.modelData)
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: root.ready
    text: "Files, notifications, messages and more in the Flux window ›"
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
    font.family: root.fontFamily; font.pixelSize: Style.font.caption
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      // Flux's own window is a better place for the rare, multi-step things
      // than a second implementation of them in here.
      onClicked: { root.run(["open"]); if (root.hub && root.hub.hide) root.hub.hide() }
    }
  }
}
