import QtQuick
import QtQuick.Controls
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
  // hold several, but the clipboard and the actions belong to whichever is
  // actually connected, and a picker for a list of one would be furniture.
  readonly property var activeDevice: {
    for (var i = 0; i < devices.length; i++)
      if (FluxModel.usable(devices[i])) return devices[i]
    return null
  }
  // The shared clipboard, from the pushed state, so it exists on the backend
  // path only.
  //
  // Deliberately NOT the phone's notifications: fluxd already forwards those
  // to the desktop's own notification daemon (org.freedesktop.Notifications,
  // with settings.notifications on), so a list of them in here would be the
  // same information a second time, in a place nobody is looking when they
  // arrive. Kevin's call, and the right one.
  //
  // The clipboard earns its place for the opposite reason: autoClipboard puts
  // the newest copy on this machine by itself, and nothing on this desktop
  // keeps the ones before it -- there is no clipboard history here, only
  // `wl-clip-persist`. These rows are that history, and the click is the only
  // way back to an entry the automatic sync has already replaced.
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

  // ---- The composer. One inline field for the three actions that need typed
  //      input, instead of three panels: the Phone page is one column and a
  //      person is doing one of these at a time.
  //
  //      The payload names are Flux's own, captured from what its CLI sends
  //      rather than guessed: ping { message }, share.url { url },
  //      sms.send { addresses: [..], body }, share.files { paths: [..] },
  //      clipboard.send { text } (omitted = this machine's current clipboard).
  property string composer: ""
  property string draftTo: ""
  property string draftBody: ""
  readonly property bool composerActive: composer !== ""

  function openComposer(mode) {
    if (composer === mode) { closeComposer(); return }
    composer = mode
    draftBody = ""
    if (mode !== "sms") draftTo = ""
    Qt.callLater(function () { bodyField.forceActiveFocus() })
  }

  function closeComposer() {
    composer = ""
    draftTo = ""
    draftBody = ""
  }

  function submitComposer() {
    var device = activeDevice
    if (!device) return
    var body = String(draftBody).trim()
    if (body === "") return

    if (composer === "ping") {
      if (live) backend.call("ping", FluxModel.pingParams(device, body), function () {})
      else run(["ping", "--device", device.name, body])
    } else if (composer === "url") {
      var method = FluxModel.shareMethod(body)
      if (live) {
        backend.call(method, method === "share.url"
          ? FluxModel.urlParams(device, body)
          : FluxModel.textParams(device, body), function () {})
      } else {
        // The CLI has no verb for share.text; its `clip` is the closest, and
        // it lands in the phone's clipboard, which is where shared text goes
        // anyway.
        run(method === "share.url" ? ["url", "--device", device.name, body]
          : ["clip", "--device", device.name, body])
      }
    } else if (composer === "sms") {
      var to = String(draftTo).trim()
      if (to === "") return
      if (live) backend.call("sms.send", FluxModel.smsParams(device, to, body), function () {})
      else run(["sms", "--device", device.name, to, body])
    }
    closeComposer()
  }

  // Omarchy's own chooser, which is what Flux's picker runs too. Sending is a
  // separate step from choosing, so a cancelled dialog sends nothing.
  // No transport for the phone's own playback, and not for lack of trying:
  // Flux's media flow is one-directional by design. docs/features.md is
  // explicit -- "The phone controls the media players on the desktop" and
  // "The desktop does not show or control the players on the phone" -- which
  // is why the phone advertises no `mpris` plugin and device.media stays null.
  // A transport bar here could never light up. Read the docs before building
  // the screen next time.
  readonly property bool ringing: !!backend && !!backend.ringing

  // Unpairing is the one action here that throws something away, so it asks
  // first -- the same two-step the KDE Connect page uses for the same reason.
  property string unpairConfirmingId: ""

  function stopRinging() {
    if (live) backend.call("ring.stop", {}, function () {})
    else run(["ring", "--stop"])
  }

  function unpair(device) {
    if (!device) return
    if (unpairConfirmingId !== device.id) { unpairConfirmingId = device.id; return }
    unpairConfirmingId = ""
    if (live) backend.call("pair.unpair", FluxModel.unpairParams(device), function () {})
    else run(["unpair", device.name])
  }

  function pickAndSend() {
    if (!activeDevice) return
    pickProc.command = ["omarchy", "file", "select", "--title",
      "Send to " + activeDevice.name, "--multiple"]
    pickProc.running = true
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
      backend.call(method, method === "clipboard.send"
        ? FluxModel.clipboardParams(device) : { device: device.id }, function () {})
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

  Process {
    id: pickProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var paths = String(text || "").split("\n").filter(function (p) { return p.length > 0 })
        if (paths.length === 0 || !root.activeDevice) return
        if (root.live) root.backend.call("share.files", FluxModel.filesParams(root.activeDevice, paths), function () {})
        else root.run(["send", "--device", root.activeDevice.name].concat(paths))
      }
    }
  }

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

  // Ringing is loud and in another room; stopping it is the only thing that
  // matters while it lasts, so it gets the top of the page.
  Rectangle {
    visible: root.ringing
    width: parent.width
    height: ringRow.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15)

    Row {
      id: ringRow
      x: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(24)
      spacing: Style.spacing.sm

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: "The phone is ringing"
        color: root.foreground
        font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.weight: Font.Medium
      }
      Button {
        text: "Stop"
        bordered: true
        foreground: root.foreground; fontFamily: root.fontFamily
        onClicked: root.stopRinging()
      }
    }
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
        PanelActionButton {
          visible: FluxModel.usable(row.modelData)
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰈔"
          tooltipText: "Send files"
          onClicked: root.pickAndSend()
        }
        PanelActionButton {
          visible: FluxModel.usable(row.modelData)
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰍡"
          tooltipText: "Send a text message through the phone"
          onClicked: root.openComposer("sms")
        }
        PanelActionButton {
          visible: FluxModel.usable(row.modelData)
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰌷"
          tooltipText: "Send a link or a piece of text"
          onClicked: root.openComposer("url")
        }
        PanelActionButton {
          visible: FluxModel.usable(row.modelData)
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰀃"
          tooltipText: "Send a ping"
          onClicked: root.openComposer("ping")
        }
        Button {
          visible: !!row.modelData.paired
          text: root.unpairConfirmingId === row.modelData.id ? "Sure?" : "Unpair"
          bordered: true
          foreground: root.unpairConfirmingId === row.modelData.id ? Color.urgent : root.dim
          fontFamily: root.fontFamily
          onClicked: root.unpair(row.modelData)
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

  // The composer appears under the rows it belongs to, and takes the keyboard
  // whole while it is open -- the tab reports that through keysBlocked, or
  // typing an address would trigger the panel's own single-key shortcuts.
  Column {
    visible: root.composerActive
    width: parent.width
    spacing: Style.spacing.xs

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.composer === "sms" ? "Text message through the phone"
        : root.composer === "url" ? "A link opens on the phone; anything else arrives as text"
        : "Ping the phone"
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }

    TextField {
      id: toField
      visible: root.composer === "sms"
      width: parent.width
      placeholderText: "Number"
      text: root.draftTo
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      onTextChanged: root.draftTo = text
      Keys.onEscapePressed: root.closeComposer()
      onAccepted: bodyField.forceActiveFocus()
    }

    TextField {
      id: bodyField
      width: parent.width
      placeholderText: root.composer === "url" ? "https://… or any text"
        : root.composer === "sms" ? "Message" : "Message"
      text: root.draftBody
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      onTextChanged: root.draftBody = text
      Keys.onEscapePressed: root.closeComposer()
      onAccepted: root.submitComposer()
    }

    Row {
      spacing: Style.spacing.xs
      Button {
        text: "Send"
        bordered: true
        foreground: root.foreground; fontFamily: root.fontFamily
        onClicked: root.submitComposer()
      }
      Button {
        text: "Cancel"
        bordered: true
        foreground: root.foreground; fontFamily: root.fontFamily
        onClicked: root.closeComposer()
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
