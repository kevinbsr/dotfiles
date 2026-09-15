import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Display panel with a monitor picker (no contrast control and scales up to 2x,
// by choice; the backend still accepts `set <connector> contrast`).
// Every control below the picker acts on
// the picked monitor, not on the focused one: with no bar on the LG monitor
// (shell.json bar.hideOnMonitors), clicking a bar always focuses another
// monitor, so a focus-bound panel could never reach it.
//
// State and actions go through ~/.local/bin/omarchy-display-control: backlight
// or DDC/CI brightness, DDC color preset / input source / power,
// and scale / refresh rate / enable written into the hyprmoncfg profile so the
// daemon does not undo them.
Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  manageIpc: false

  property var displays: []
  property string focusedName: ""
  // The monitor the controls act on. Empty until the first read, then the
  // focused monitor at each open; kept across refreshes while the panel is open.
  property string selectedName: ""
  // Set at open: the first state read after it picks the focused monitor, since
  // focusedName is from the previous read until then.
  property bool selectFocusedOnRead: true
  readonly property var sel: {
    for (var i = 0; i < displays.length; i++)
      if (displays[i] && displays[i].name === selectedName) return displays[i]
    return null
  }
  readonly property int enabledDisplayCount: {
    var n = 0
    for (var i = 0; i < displays.length; i++) if (displays[i] && displays[i].enabled) n++
    return n
  }

  // Slider values shown while a DDC/backlight write is on its way; -1 = follow sel.
  property int brightnessPreview: -1
  property var pendingSet: null
  property real wheelAccumulator: 0

  readonly property var scalePresets: ["1", "1.25", "1.6", "2"]
  readonly property var scaleValues: sel ? Model.availableScales(scalePresets, sel.width, sel.height) : []

  readonly property var powerOptions: {
    var list = []
    if (!sel) return list
    if (sel.powerControl && sel.enabled) list.push({ id: "screen", label: sel.powerOn ? "Screen off" : "Screen on" })
    list.push({ id: "enabled", label: sel.enabled ? "Disable" : "Enable" })
    return list
  }

  // Cursor model shared by keyboard and pointer. Row sections are horizontal
  // pill rows (h/l walks them); slider sections use the -1 sentinel.
  property string focusSection: "monitors"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var sliderSections: ["brightness", "textsize"]

  readonly property var visibleSections: {
    var list = []
    if (displays.length > 1) list.push("monitors")
    if (sel && sel.brightness !== null && sel.brightness !== undefined) list.push("brightness")
    if (sel && sel.enabled) list.push("scale")
    if (sel && sel.enabled && sel.rates && sel.rates.length > 1) list.push("refreshrate")
    if (sel && sel.presets && sel.presets.length > 0) list.push("preset")
    if (sel && sel.inputs && sel.inputs.length > 1) list.push("input")
    if (sel) list.push("power")
    list.push("textsize")
    return list
  }

  function sectionCount(section) {
    if (section === "monitors") return displays.length
    if (section === "scale") return scaleValues.length
    if (section === "refreshrate") return sel && sel.rates ? sel.rates.length : 0
    if (section === "preset") return sel && sel.presets ? sel.presets.length : 0
    if (section === "input") return sel && sel.inputs ? sel.inputs.length : 0
    if (section === "power") return powerOptions.length
    return 0
  }

  function isSlider(section) { return sliderSections.indexOf(section) !== -1 }
  function firstIndex(section) { return isSlider(section) ? -1 : 0 }

  function moveCursor(delta) {
    var sections = visibleSections
    // Bindings can still be undefined while the panel is being built.
    if (!sections || !sections.length) return
    var i = sections.indexOf(focusSection)
    if (i < 0) { focusSection = sections[0]; selectedIndex = firstIndex(focusSection); return }
    var next = i + (delta > 0 ? 1 : -1)
    if (next < 0 || next >= sections.length) return
    var keepColumn = !isSlider(focusSection) && !isSlider(sections[next])
    focusSection = sections[next]
    selectedIndex = keepColumn ? Math.min(selectedIndex, sectionCount(focusSection) - 1) : firstIndex(focusSection)
  }

  function moveCursorH(delta) {
    if (focusSection === "brightness") { adjustSlider("brightness", delta * 5); return }
    if (focusSection === "textsize") { adjustTextSize(delta); return }
    var last = sectionCount(focusSection) - 1
    selectedIndex = Math.max(0, Math.min(last, selectedIndex + delta))
  }

  function activateCursor() {
    var i = selectedIndex
    if (focusSection === "monitors" && i >= 0 && i < displays.length) selectDisplay(displays[i].name)
    else if (focusSection === "scale" && i >= 0 && i < scaleValues.length) setScale(scaleValues[i])
    else if (focusSection === "refreshrate" && sel && i >= 0 && i < sel.rates.length) runAction("rate", String(sel.rates[i]))
    else if (focusSection === "preset" && sel && i >= 0 && i < sel.presets.length) runAction("preset", sel.presets[i].value)
    else if (focusSection === "input" && sel && i >= 0 && i < sel.inputs.length) runAction("input", sel.inputs[i].value)
    else if (focusSection === "power" && i >= 0 && i < powerOptions.length) activatePower(powerOptions[i].id)
  }

  function clampCursor() {
    var sections = visibleSections
    // Bindings can still be undefined while the panel is being built.
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) { focusSection = sections[0]; selectedIndex = firstIndex(focusSection); return }
    if (isSlider(focusSection)) { selectedIndex = -1; return }
    var count = sectionCount(focusSection)
    if (selectedIndex >= count) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var margin = 6
    if (top < flick.contentY + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > flick.contentY + flick.height - margin) flick.contentY = bottom + margin - flick.height
  }

  function hoverCursor(section, index) {
    if (root.reflowingText) return
    root.cursorActive = true
    root.focusSection = section
    root.selectedIndex = index
  }

  // ---- state and actions ----
  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function selectDisplay(name) {
    if (!name || name === selectedName) return
    selectedName = name
    brightnessPreview = -1
  }

  function displayLabel(d) {
    if (!d) return ""
    return d.internal ? "Laptop" : (d.model || d.name)
  }

  function runAction(what, value) {
    if (!sel) return
    actionProc.command = ["omarchy-display-control", "set", sel.name, what, String(value)]
    if (!actionProc.running) actionProc.running = true
  }

  function setScale(scale) {
    runAction("scale", Model.cleanScale(scale, sel.width, sel.height) || scale)
  }

  function activatePower(id) {
    if (!sel) return
    if (id === "screen") runAction("power", sel.powerOn ? "0" : "1")
    else if (id === "enabled") {
      if (sel.enabled && enabledDisplayCount <= 1) return
      runAction("enabled", sel.enabled ? "0" : "1")
    }
  }

  // Sliders: one write at a time per the DDC bus; a newer value replaces a
  // queued one instead of stacking writes behind a slow monitor.
  function queueSet(name, what, value) {
    pendingSet = { name: name, what: what, value: value }
    if (!setProc.running) flushSet()
  }

  function flushSet() {
    if (!pendingSet) return
    var p = pendingSet
    pendingSet = null
    setProc.command = ["omarchy-display-control", "set", p.name, p.what, String(p.value)]
    setProc.running = true
  }

  function sliderValue(what) {
    if (!sel) return 0
    return brightnessPreview >= 0 ? brightnessPreview : (sel.brightness || 0)
  }

  function setSlider(what, value) {
    if (!sel) return
    var v = Math.round(value)
    v = Model.clampBrightness(v)
    brightnessPreview = v
    queueSet(sel.name, what, v)
  }

  function adjustSlider(what, delta) {
    setSlider(what, sliderValue(what) + delta)
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({ icon: "brightness", value: percent }))
  }

  function focusedDisplay() {
    for (var i = 0; i < displays.length; i++) if (displays[i].name === focusedName) return displays[i]
    return null
  }

  IpcHandler {
    target: "omarchy.monitor"

    // Brightness of the focused monitor, as the stock panel's IPC did.
    function brightness(percent: string): string {
      var d = root.focusedDisplay()
      if (!d) return "no display"
      var v = Model.clampBrightness(Number(percent))
      root.queueSet(d.name, "brightness", v)
      return "got " + v
    }
    function state(): string { return JSON.stringify({ focused: root.focusedName, selected: root.selectedName, displays: root.displays }) }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1
  property bool reflowingText: false
  function markReflowing() { root.reflowingText = true; reflowSettle.restart() }

  function nearestTextStop(px) {
    var best = 0, bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }
  function currentTextIndex() { return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize) }
  function displayedTextPx() { return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize }
  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }
  function adjustTextSize(deltaSteps) {
    var idx = Math.max(0, Math.min(textSizeStops.length - 1, currentTextIndex() + deltaSteps))
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      selectedName = focusedName
      selectFocusedOnRead = true
      brightnessPreview = -1
      refresh()
      focusSection = displays.length > 1 ? "monitors" : "brightness"
      selectedIndex = firstIndex(focusSection)
      cursorActive = false
    }
  }

  onVisibleSectionsChanged: clampCursor()
  onSelChanged: clampCursor()

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["omarchy-display-control", "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed
        try { parsed = JSON.parse(String(text || "{}")) } catch (e) { return }
        root.displays = Array.isArray(parsed.displays) ? parsed.displays : []
        root.focusedName = parsed.focused || ""
        var known = false
        for (var i = 0; i < root.displays.length; i++) if (root.displays[i].name === root.selectedName) known = true
        if (!known || root.selectFocusedOnRead) root.selectedName = root.focusedName
        root.selectFocusedOnRead = false
        // A settled write: drop the previews once the monitor reports the value.
        if (!setProc.running && !root.pendingSet) {
          root.brightnessPreview = -1
        }
      }
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.flushSet()
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg && root.bar && root.bar.shell)
          root.bar.shell.summon("omarchy.osd", JSON.stringify({ icon: "monitor", text: msg.split("\n").pop() }))
      }
    }
    onRunningChanged: if (!running) root.refresh()
  }

  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0 && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    // The wheel keeps acting on the focused monitor, like the stock widget.
    onWheelMoved: function(delta) {
      var d = root.focusedDisplay()
      if (!d || d.brightness === null || d.brightness === undefined) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var v = Model.clampBrightness((d.brightness || 0) + wheel.steps * 5)
      d.brightness = v
      root.queueSet(d.name, "brightness", v)
      root.showBrightnessOsd(v)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: root.sel && root.sel.internal ? "󰌢" : "󰍹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: root.sel ? root.displayLabel(root.sel) : "Display"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: {
                  if (!root.sel) return "READING DISPLAYS…"
                  var parts = []
                  if (!root.sel.enabled) parts.push("DISABLED")
                  else {
                    parts.push(root.sel.width + "×" + root.sel.height + " @ " + root.sel.refreshRate + " HZ")
                    if (!root.sel.powerOn) parts.push("SCREEN OFF")
                  }
                  if (root.sel.name === root.focusedName) parts.push("FOCUSED")
                  return root.sel.name + " · " + parts.join(" · ")
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Monitor picker ----------
          PanelSeparator { visible: root.displays.length > 1; foreground: root.bar.foreground }

          Grid {
            id: monitorRow
            visible: root.displays.length > 1
            width: parent.width
            columns: Math.max(1, root.displays.length)
            spacing: Style.spacing.xs
            readonly property real cellWidth: root.displays.length > 0 ? (width - spacing * (columns - 1)) / columns : 0

            Repeater {
              model: root.displays

              OptionPill {
                required property var modelData
                required property int index
                width: monitorRow.cellWidth
                section: "monitors"
                optionIndex: index
                text: (modelData.name === root.focusedName ? "● " : "") + root.displayLabel(modelData)
                active: modelData.name === root.selectedName
                dimmed: !modelData.enabled
                onClicked: root.selectDisplay(modelData.name)
              }
            }
          }

          // ---------- Brightness ----------
          PanelSeparator {
            visible: root.visibleSections.indexOf("brightness") !== -1
            foreground: root.bar.foreground
          }

          SliderRow {
            visible: root.visibleSections.indexOf("brightness") !== -1
            section: "brightness"
            title: "BRIGHTNESS"
            minimum: 1
            value: root.sliderValue("brightness")
            suffix: root.sel && !root.sel.internal ? "% · DDC" : "%"
          }

          // ---------- Scale ----------
          PanelSeparator { visible: root.visibleSections.indexOf("scale") !== -1; foreground: root.bar.foreground }

          PillSection {
            visible: root.visibleSections.indexOf("scale") !== -1
            title: "SCALE"
            section: "scale"
            options: root.scaleValues.map(function(s) {
              return { label: (root.sel ? Model.cleanScale(s, root.sel.width, root.sel.height) : s) + "x", value: s }
            })
            activeIndex: root.sel ? Model.matchingScaleIndex(root.scaleValues, root.sel.scale, root.sel.width, root.sel.height) : -1
            onChosen: function(i) { root.setScale(root.scaleValues[i]) }
          }

          // ---------- Refresh rate ----------
          PanelSeparator { visible: root.visibleSections.indexOf("refreshrate") !== -1; foreground: root.bar.foreground }

          PillSection {
            visible: root.visibleSections.indexOf("refreshrate") !== -1
            title: "REFRESH RATE"
            section: "refreshrate"
            options: root.sel && root.sel.rates ? root.sel.rates.map(function(r) { return { label: r + " Hz", value: r } }) : []
            activeIndex: root.sel && root.sel.rates ? root.sel.rates.indexOf(root.sel.refreshRate) : -1
            onChosen: function(i) { root.runAction("rate", String(root.sel.rates[i])) }
          }

          // ---------- Color preset ----------
          PanelSeparator { visible: root.visibleSections.indexOf("preset") !== -1; foreground: root.bar.foreground }

          PillSection {
            visible: root.visibleSections.indexOf("preset") !== -1
            title: "COLOR PRESET"
            section: "preset"
            options: root.sel && root.sel.presets ? root.sel.presets.map(function(p) { return { label: p.label, value: p.value } }) : []
            activeIndex: {
              if (!root.sel || !root.sel.presets) return -1
              for (var i = 0; i < root.sel.presets.length; i++) if (root.sel.presets[i].value === root.sel.preset) return i
              return -1
            }
            onChosen: function(i) { root.runAction("preset", root.sel.presets[i].value) }
          }

          // ---------- Input source ----------
          PanelSeparator { visible: root.visibleSections.indexOf("input") !== -1; foreground: root.bar.foreground }

          PillSection {
            visible: root.visibleSections.indexOf("input") !== -1
            title: "INPUT"
            section: "input"
            columns: 2
            options: root.sel && root.sel.inputs ? root.sel.inputs.map(function(p) { return { label: p.label, value: p.value } }) : []
            activeIndex: {
              if (!root.sel || !root.sel.inputs) return -1
              for (var i = 0; i < root.sel.inputs.length; i++) if (root.sel.inputs[i].value === root.sel.input) return i
              return -1
            }
            onChosen: function(i) { root.runAction("input", root.sel.inputs[i].value) }
          }

          // ---------- Power ----------
          PanelSeparator { visible: root.visibleSections.indexOf("power") !== -1; foreground: root.bar.foreground }

          PillSection {
            visible: root.visibleSections.indexOf("power") !== -1
            title: "POWER"
            section: "power"
            options: root.powerOptions.map(function(p) { return { label: p.label, value: p.id } })
            activeIndex: -1
            disabledIndex: {
              // The last enabled monitor cannot be disabled.
              for (var i = 0; i < root.powerOptions.length; i++)
                if (root.powerOptions[i].id === "enabled" && root.sel && root.sel.enabled && root.enabledDisplayCount <= 1) return i
              return -1
            }
            onChosen: function(i) { root.activatePower(root.powerOptions[i].id) }
          }

          // ---------- Text size (global) ----------
          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TEXT SIZE · ALL DISPLAYS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                text: (textSizeSlider.dragging ? root.textSizeStops[Math.round(textSizeSlider.liveValue)] : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler { onHoveredChanged: if (hovered) root.hoverCursor("textsize", -1) }
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }

  component OptionPill: Button {
    id: pill
    required property string section
    required property int optionIndex
    property bool dimmed: false
    property bool blocked: false

    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    opacity: blocked ? 0.35 : (dimmed ? 0.6 : 1.0)
    hasCursor: root.cursorActive && root.focusSection === section && root.selectedIndex === optionIndex
    onHovered: function(isHovered) { if (isHovered) root.hoverCursor(pill.section, pill.optionIndex) }
  }

  component PillSection: Column {
    id: pillSection
    property string title: ""
    property string section: ""
    property var options: []
    property int activeIndex: -1
    property int disabledIndex: -1
    property int columns: Math.max(1, Math.min(options.length, 4))
    signal chosen(int index)

    width: parent ? parent.width : 0
    spacing: Style.space(10)

    PanelSectionHeader {
      text: pillSection.title
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Grid {
      id: pillGrid
      width: parent.width
      columns: pillSection.columns
      spacing: Style.spacing.xs
      readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

      Repeater {
        model: pillSection.options

        OptionPill {
          required property var modelData
          required property int index
          width: pillGrid.cellWidth
          section: pillSection.section
          optionIndex: index
          text: modelData.label
          active: index === pillSection.activeIndex
          blocked: index === pillSection.disabledIndex
          onClicked: if (!blocked) pillSection.chosen(index)
        }
      }
    }
  }

  component SliderRow: Column {
    id: sliderRow
    property string section: ""
    property string title: ""
    property int minimum: 0
    property int value: 0
    property string suffix: "%"

    width: parent ? parent.width : 0
    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(sliderHeader.implicitHeight, sliderValue.implicitHeight)

      PanelSectionHeader {
        id: sliderHeader
        text: sliderRow.title
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: sliderValue
        text: Math.round(slider.dragging ? slider.liveValue : sliderRow.value) + sliderRow.suffix
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    CursorSurface {
      id: sliderSurface
      width: parent.width
      height: slider.implicitHeight + Style.spacing.controlGap
      hasCursor: root.cursorActive && root.focusSection === sliderRow.section
      onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sliderSurface)
      foreground: root.bar.foreground
      outline: true

      PanelSlider {
        id: slider
        bar: root.bar
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        minimum: sliderRow.minimum
        maximum: 100
        step: 1
        integer: true
        value: sliderRow.value
        onReleased: function(v) { root.setSlider(sliderRow.section, v) }
      }

      HoverHandler { onHoveredChanged: if (hovered) root.hoverCursor(sliderRow.section, -1) }
    }
  }
}
