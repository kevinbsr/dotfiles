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
// WHY THE CLI AND NOT THE PLUGIN: Flux ships its own omarchy-shell plugin with
// a Backend.qml that speaks JSON-RPC to fluxd over a socket. The Hub does not
// load or copy it. Flux's repository carries no license yet -- its own Arch
// package records `license=('LicenseRef-unknown')` -- so redistributing its
// source inside this plugin is not something to do on a hunch. `flux` the
// command is a documented, stable surface (`flux --help`), it is what any
// third party is meant to drive, and reading it costs one process every few
// seconds while this page is on screen.
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

  property var devices: []
  property bool ready: false
  // Whether Flux is on this machine at all. One probe decides it: `flux
  // status` either answers or the command is not there, and the tab shows the
  // KDE Connect setup instead. Checked once at load, not polled -- a plugin
  // appearing mid-session is not worth a timer.
  property bool available: false
  property string errorText: ""
  readonly property var pairing: FluxModel.pendingPairing(devices)

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function run(args) {
    actionProc.command = ["flux"].concat(args)
    actionProc.running = true
  }

  onActiveChanged: {
    if (active) refresh()
    poll.running = active && available
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
          root.devices = FluxModel.devices(JSON.parse(String(text || "")))
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
        root.devices = []
        root.ready = true
      }
    }
  }

  Process {
    id: actionProc
    onExited: Qt.callLater(root.refresh)
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
          onClicked: if (root.pairing) root.run(["accept", root.pairing.name])
        }
        Button {
          text: "Reject"
          bordered: true
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: if (root.pairing) root.run(["reject", root.pairing.name])
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
          onClicked: root.run(["ring", "--device", row.modelData.name])
        }
        PanelActionButton {
          visible: FluxModel.usable(row.modelData)
          foreground: root.foreground; fontFamily: root.fontFamily
          iconText: "󰅇"
          tooltipText: "Send this computer's clipboard"
          onClicked: root.run(["clip", "--device", row.modelData.name])
        }
        Button {
          visible: !row.modelData.paired
          text: "Pair"
          bordered: true
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: root.run(["pair", row.modelData.name])
        }
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
