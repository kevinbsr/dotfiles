import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "ClockModel.js" as ClockModel
import "MediaModel.js" as MediaModel

// The hub's face on the bar: the condition glyph, the date/time label, and
// the transport glyph — three separate hit areas in one widget slot.
//
// The two glyphs are here rather than only in the panel because a condition
// and a play state you have to open something to see are ones you never look
// at. They earn the space by being live; the rest of each module stays one
// click away.
//
// Each glyph's click is a toggle onto its own page, never a resume of
// wherever the panel was last left: the clock is about the date, so it opens
// the calendar every time. A second click, with that page already up, closes.
//
// Weather: left the weather page, right sends the conditions as a
// notification, middle refetches.
// Clock: left the calendar, right walks the label formats, middle opens the
// timezone picker.
// Media: the bindings kevin.media had, with "the popup" now meaning the
// media page — left play/pause, right the page, middle next, scroll seeks
// between tracks. The glyph is only there when something can play.
BarWidget {
  id: root
  moduleName: "kevin.hub"

  property date displayDate: clock.date

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")

  readonly property var formatRing: ClockModel.clockFormatRing(configuredFormat, configuredAltFormat, ClockModel.clockFormats(vertical))

  // What the bar shows is what shell.json stores, so a cycled format is the
  // format from then on rather than something that reverts on restart.
  readonly property string activeFormat: configuredFormat
  readonly property string displayText: formatted(displayDate)
  readonly property var verticalLines: displayText.split("\n")

  function refresh() {
    displayDate = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  // ---- Weather, read straight off the panel's always-live source rather
  //      than off the weather page, which may never have been opened.
  readonly property var weather: panelLoader.item ? panelLoader.item.weather : null
  readonly property string weatherLabel: weather ? weather.label : ""

  function refreshWeather() {
    if (weather) weather.refresh()
  }

  // ---- Media. The plugin's own service does the player ranking and the OSD;
  //      the direct Mpris read is only a stand-in for the moment before it
  //      mounts, so the glyph is never blank while something is playing.
  readonly property var mediaService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("kevin.hub")
    : null
  readonly property var directPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var mediaPlayer: mediaService ? mediaService.activePlayer : firstDirectPlayer()

  readonly property bool hasMedia: mediaPlayer !== null && mediaPlayer !== undefined
  readonly property bool mediaPlaying: hasMedia && mediaPlayer.isPlaying === true
  readonly property string mediaIcon: mediaPlaying ? "󰏤" : "󰐊"
  readonly property string mediaTitle: hasMedia ? (mediaPlayer.trackTitle || "") : ""
  readonly property string mediaArtist: hasMedia ? (mediaPlayer.trackArtist || "") : ""
  readonly property string mediaTooltip: mediaTitle
    ? (mediaTitle + (mediaArtist ? " — " + mediaArtist : ""))
    : (hasMedia ? MediaModel.labelFor(mediaPlayer) : "")

  function firstDirectPlayer() {
    for (var i = 0; i < directPlayers.length; i++)
      if (directPlayers[i] && directPlayers[i].isPlaying) return directPlayers[i]
    return directPlayers.length > 0 ? directPlayers[0] : null
  }

  // Feedback on, unlike the media page: nothing is open to show the result,
  // so the OSD is the only thing that says the click landed.
  function runMediaAction(action) {
    if (mediaService) {
      mediaService.runAction(action, true)
      return
    }

    var player = root.mediaPlayer
    if (!player) return
    if (action === "next" && player.canGoNext) player.next()
    else if (action === "previous" && player.canGoPrevious) player.previous()
    else if (action === "playPause") {
      if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
      else if (player.canTogglePlaying) player.togglePlaying()
    }
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var next = ClockModel.nextClockFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, ClockModel.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  // ---- Panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget
  //      root, so these forward to the nested panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // Open the panel straight onto a named tab — what a keybinding wants when
  // it means "show me what is playing" rather than "show me the hub".
  function openTab(name) {
    if (!panelLoader.item) return
    panelLoader.item.selectTab(name)
    panelLoader.item.open()
  }

  // What a click on one of the bar's glyphs means: a toggle *onto* a page.
  // The clock is about the date, so it opens the calendar every time rather
  // than resuming wherever the panel was last left — and only a second click,
  // with that page already up, puts the panel away.
  function toggleTab(name) {
    if (!panelLoader.item) return
    if (!root.opened) {
      openTab(name)
      return
    }
    if (panelLoader.item.currentTabId === name) {
      panelLoader.item.close()
      return
    }
    panelLoader.item.selectTab(name)
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  // The label fills more slot than it paints a mark for, at both
  // orientations: horizontally it is a text label in a padded slot, so the
  // dot takes the label width; vertically it is a stack of icon-sized lines,
  // so the dot takes one line — the same mark every icon widget gets, rather
  // than a rule running the height of the whole stack.
  readonly property real openPanelIndicatorWidth: clockButton.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = clockButton
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "kevin.hub"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function tab(name: string): void { root.openTab(name) }
    function tabToggle(name: string): void { root.toggleTab(name) }
    function refreshWeather(): void { root.refreshWeather() }
  }

  // One row on a horizontal bar, one column on a vertical one. A Grid says
  // that in two bindings instead of two layouts.
  Grid {
    id: layout
    anchors.centerIn: parent
    rows: root.vertical ? 3 : 1
    columns: root.vertical ? 1 : 3
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    WidgetButton {
      id: weatherButton
      bar: root.bar
      text: root.weatherLabel
      // A fixed slot, so the condition changing from a sun to a thunderstorm
      // does not change the widget's width. This widget is the bar's
      // centerAnchor — a glyph one pixel wider would drag the whole center
      // row sideways every time the forecast updated.
      fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
      fixedHeight: root.vertical ? Style.bar.statusSlot : -1
      tooltipText: "Weather"

      onPressed: function(b) {
        if (b === Qt.RightButton) {
          if (root.bar) root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
        } else if (b === Qt.MiddleButton) {
          root.refreshWeather()
        } else {
          root.toggleTab("weather")
        }
      }
    }

    WidgetButton {
      id: clockButton
      bar: root.bar
      text: root.vertical ? "" : root.displayText
      labelVisible: !root.vertical
      hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
      fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
      horizontalMargin: 8.75
      verticalPadding: 8.75

      onPressed: function(b) {
        if (b === Qt.RightButton) root.cycleFormat()
        else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
        else root.toggleTab("calendar")
      }

      Column {
        visible: root.vertical
        anchors.fill: parent

        Repeater {
          model: root.verticalLines

          OpticalGlyph {
            required property string modelData
            width: clockButton.width
            height: Style.bar.iconSlot
            text: modelData
            fontFamily: clockButton.fontFamily
            fontSize: modelData.length > 3
              ? clockButton.fontSize * 0.9
              : clockButton.fontSize
            color: clockButton.foreground
          }
        }
      }
    }

    WidgetButton {
      id: mediaButton
      bar: root.bar
      // Blank collapses the button, which is what should happen: with no
      // player there is nothing to press, and the bar goes back to being a
      // clock. Fixed slot for the same reason as the weather glyph — a pause
      // bar and a play triangle are not the same width.
      text: root.hasMedia ? root.mediaIcon : ""
      fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
      fixedHeight: root.vertical ? Style.bar.statusSlot : -1
      // Paused reads as the quieter state without vanishing, the way the
      // dimmed glyph did before the merge.
      dimmed: !root.mediaPlaying
      tooltipText: root.mediaTooltip

      onPressed: function(b) {
        if (!root.hasMedia) return
        if (b === Qt.RightButton) root.toggleTab("media")
        else if (b === Qt.MiddleButton) root.runMediaAction("next")
        else root.runMediaAction("playPause")
      }

      onWheelMoved: function(delta) {
        if (!root.hasMedia || delta === 0) return
        root.runMediaAction(delta > 0 ? "previous" : "next")
      }
    }
  }
}
