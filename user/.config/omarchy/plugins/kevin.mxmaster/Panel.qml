import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "kevin.mxmaster"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool connected: hostWidget ? hostWidget.connected === true : false

  // Mirrors the slider while dragging so the label tracks the knob; the write
  // only fires on release.
  property int dpiPreview: -1

  function open() {
    if (hostWidget) hostWidget.refresh()
    root.controller.show()
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function value(name, fallback) {
    return hostWidget ? hostWidget.settingValue(name, fallback) : fallback
  }
  function meta(name) {
    return hostWidget ? hostWidget.settingMeta(name) : null
  }
  function apply(name, v) {
    if (hostWidget) hostWidget.applySetting(name, v)
  }

  function faded(alpha) {
    return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, alpha)
  }

  onOpenedChanged: if (!opened) root.dpiPreview = -1

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        // ── Header ────────────────────────────────────────────────
        Item {
          width: parent.width
          height: titleText.implicitHeight

          Text {
            id: titleText
            anchors.left: parent.left
            text: root.hostWidget && root.hostWidget.status.name ? root.hostWidget.status.name : "MX Master"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: titleText.verticalCenter
            visible: root.connected && root.hostWidget.battery
            text: {
              if (!root.hostWidget || !root.hostWidget.battery) return ""
              var b = root.hostWidget.battery
              var glyph = b.charging ? "󰂄" : "󰁽"
              return glyph + "  " + (b.level !== null && b.level !== undefined ? b.level + "%" : "—")
            }
            color: root.faded(0.75)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: !root.connected
          width: parent.width
          text: "No MX Master detected. Check that the Bolt receiver is plugged in and the mouse is powered on."
          color: root.faded(0.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ── Pointer ───────────────────────────────────────────────
        PanelSeparator { width: parent.width; foreground: root.fg; visible: root.connected }

        Item {
          width: parent.width
          height: dpiLabel.implicitHeight
          visible: root.connected

          PanelSectionHeader {
            id: dpiLabel
            anchors.left: parent.left
            text: "SENSITIVITY"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: dpiLabel.verticalCenter
            // Reads as "— DPI" until the first probe lands, so the panel never
            // shows a placeholder zero as if it were the mouse's real setting.
            text: {
              if (root.dpiPreview > 0) return root.dpiPreview + " DPI"
              var current = root.value("dpi", 0)
              return current > 0 ? current + " DPI" : "— DPI"
            }
            color: root.faded(0.75)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSlider {
          width: parent.width
          visible: root.connected
          bar: root.bar
          integer: true
          minimum: root.meta("dpi") ? root.meta("dpi").min : 200
          maximum: root.meta("dpi") ? root.meta("dpi").max : 8000
          step: root.meta("dpi") ? root.meta("dpi").step : 50
          value: root.value("dpi", 1000)
          onMoved: function(v) { root.dpiPreview = Math.round(v) }
          onReleased: function(v) {
            root.dpiPreview = -1
            root.apply("dpi", Math.round(v))
          }
        }

        // ── Scrolling ─────────────────────────────────────────────
        PanelSeparator { width: parent.width; foreground: root.fg; visible: root.connected }

        PanelSectionHeader {
          text: "SCROLLING"
          foreground: root.fg
          fontFamily: root.fontFamily
          visible: root.connected
        }

        Toggle {
          width: parent.width
          visible: root.connected
          label: "Ratcheted wheel"
          description: "Click-by-click steps instead of free spinning"
          checked: root.value("scroll-ratchet", "Ratcheted") === "Ratcheted"
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: root.apply("scroll-ratchet", checked ? "Freespinning" : "Ratcheted")
        }

        Item {
          width: parent.width
          height: shiftLabel.implicitHeight
          visible: root.connected && root.value("scroll-ratchet", "") === "Ratcheted"

          PanelSectionHeader {
            id: shiftLabel
            anchors.left: parent.left
            text: "SMARTSHIFT THRESHOLD"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: shiftLabel.verticalCenter
            text: root.value("smart-shift", 0) >= 50 ? "never free-spin" : String(root.value("smart-shift", 0))
            color: root.faded(0.75)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSlider {
          width: parent.width
          visible: root.connected && root.value("scroll-ratchet", "") === "Ratcheted"
          bar: root.bar
          integer: true
          minimum: root.meta("smart-shift") ? root.meta("smart-shift").min : 1
          maximum: root.meta("smart-shift") ? root.meta("smart-shift").max : 50
          step: 1
          value: root.value("smart-shift", 12)
          onReleased: function(v) { root.apply("smart-shift", Math.round(v)) }
        }

        Text {
          visible: root.connected && root.value("scroll-ratchet", "") === "Ratcheted"
          width: parent.width
          text: "Lower spins free with a gentler flick; 50 keeps it always ratcheted."
          color: root.faded(0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Toggle {
          width: parent.width
          visible: root.connected
          label: "High-resolution scroll"
          description: "Smooth pixel-level scrolling"
          checked: root.value("hires-smooth-resolution", true) === true
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: root.apply("hires-smooth-resolution", checked ? "false" : "true")
        }

        Toggle {
          width: parent.width
          visible: root.connected
          label: "Invert wheel direction"
          description: "Flip vertical scrolling"
          checked: root.value("hires-smooth-invert", false) === true
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: root.apply("hires-smooth-invert", checked ? "false" : "true")
        }

        Toggle {
          width: parent.width
          visible: root.connected
          label: "Invert thumb wheel"
          description: "Flip horizontal scrolling"
          checked: root.value("thumb-scroll-invert", false) === true
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: root.apply("thumb-scroll-invert", checked ? "false" : "true")
        }

        // ── Hosts ─────────────────────────────────────────────────
        PanelSeparator {
          width: parent.width
          foreground: root.fg
          visible: root.connected && hostRepeater.count > 1
        }

        PanelSectionHeader {
          text: "SWITCH TO HOST"
          foreground: root.fg
          fontFamily: root.fontFamily
          visible: root.connected && hostRepeater.count > 1
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.connected && hostRepeater.count > 1

          Repeater {
            id: hostRepeater
            model: {
              var m = root.meta("change-host")
              return m && m.choices ? m.choices : []
            }

            Rectangle {
              required property var modelData
              required property int index

              readonly property bool current: {
                var m = root.meta("change-host")
                return m ? m.index === index : false
              }

              width: parent.width
              height: Style.space(34)
              radius: Style.cornerRadius
              color: current ? root.faded(0.16)
                : (hostMouse.containsMouse ? root.faded(0.10) : root.faded(0.05))

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: parent.current
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: parent.current ? "󰄬" : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: hostMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.current ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                  if (parent.current) return
                  root.apply("change-host", modelData)
                  root.close()
                }
              }
            }
          }
        }

        Text {
          visible: root.connected && hostRepeater.count > 1
          width: parent.width
          text: "Switching hosts disconnects the mouse here. Use the button underneath the mouse to come back."
          color: root.faded(0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
