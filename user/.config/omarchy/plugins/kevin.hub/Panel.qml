import QtQuick
import qs.Commons
import qs.Ui

// The hub's panel: a tab strip over one page at a time.
//
// The panel itself knows nothing about calendars or media. It owns the
// chrome every module shares — the popup, the tab strip, keyboard routing,
// and writing settings back to shell.json — and each module is a QML file
// listed in `tabs` below. Adding a module is a file plus a line.
//
// ---- Tab contract -------------------------------------------------------
// An entry in `tabs` is:
//   { id, label, icon, source, minWidth }
// `id` is what selectTab() and the IPC `tab` route take, and what gets
// persisted as the last-used tab.
//
// A tab component may declare any of these; all are optional:
//   property var hub            - set to this panel (settings, persist, close)
//   property QtObject bar       - the bar host
//   property color foreground   - theme foreground, already resolved
//   property string fontFamily  - theme font, already resolved
//   property bool keysBlocked   - true while it owns the keyboard (inline edit)
//   function handleMove(dx, dy) - return true if the arrow key was consumed
//   function handleActivate()   - Enter / Space
//   function handleTextKey(t)   - a single printable key
//   function handleClose()      - Escape; return true to keep the panel open
//   function tabShown()         - became the visible page of an open panel
//   function tabHidden()        - stopped being it (tab switch or close)
//   function refresh()          - panel opened, or a refresh came over IPC
//   function panelClosed()      - panel dismissed; drop transient state
// Everything else is the tab's own business, including its layout: the page
// scrolls for it, so a tab only has to report an honest implicitHeight.
Panel {
  id: root
  moduleName: "kevin.hub"
  ipcTarget: "kevin.hub"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- The modules. Order here is the order in the strip, and index 0 is
  //      what a fresh install opens on.
  readonly property var tabs: [
    { id: "calendar", label: "Calendar", icon: "󰃭", source: "CalendarTab.qml", minWidth: Style.space(560) },
    { id: "media", label: "Media", icon: "󰝚", source: "MediaTab.qml", minWidth: Style.space(420) },
    { id: "weather", label: "Weather", icon: "󰖐", source: "WeatherTab.qml", minWidth: Style.space(480) },
    { id: "screentime", label: "Screen", icon: "󰔟", source: "ScreenTimeTab.qml", minWidth: Style.space(400) },
    { id: "phone", label: "Phone", icon: "󰄜", source: "KdeConnectTab.qml", minWidth: Style.space(400) },
    { id: "nearby", label: "Nearby", icon: "󰀂", source: "NearbyTab.qml", minWidth: Style.space(400) }
  ]

  // Weather's data layer sits out here rather than inside WeatherTab.qml
  // because the bar icon shows the condition whether or not the page has
  // ever been opened, and pages load on first visit. BarWidget.qml reads it
  // back through this panel.
  readonly property alias weather: weatherSource

  WeatherSource {
    id: weatherSource
    hub: root
  }

  // One width for every tab, taken from the widest, so switching pages moves
  // the content and not the popup around it.
  readonly property real panelWidth: {
    var widest = 0
    for (var i = 0; i < tabs.length; i++) widest = Math.max(widest, tabs[i].minWidth || 0)
    return widest
  }

  // Which tab is up. Persisted, so the hub reopens where it was left rather
  // than snapping back to the calendar every time.
  //
  // Followed from settings rather than read once at construction, for two
  // reasons: BarWidget.qml loads this panel and hands it `settings`
  // afterwards, so reading up front would only ever see an empty object; and
  // there is one bar surface — so one of these panels — per monitor, so the
  // stored value is also how the other screens learn the tab changed.
  property int currentIndex: 0
  readonly property var currentTab: tabs[Math.max(0, Math.min(currentIndex, tabs.length - 1))]
  readonly property string currentTabId: currentTab ? String(currentTab.id) : ""
  property var activeTabItem: null

  // Guarded so the panel renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function indexOfTab(id) {
    var name = String(id || "")
    for (var i = 0; i < tabs.length; i++) if (String(tabs[i].id) === name) return i
    return 0
  }

  function syncTab() {
    // The bare default before injection is an empty object; acting on it
    // would snap every panel to tab 0 on the way up.
    if (!settings || Object.keys(settings).length === 0) return
    var next = indexOfTab(setting("tab", tabs[0].id))
    if (next !== currentIndex) currentIndex = next
  }

  function selectTab(id) {
    var next = indexOfTab(id)
    if (next === currentIndex) return
    currentIndex = next
    // The write comes back through the bar as the same value, which is what
    // moves the panels on the other monitors; here it lands as a no-op.
    persistSettings({ tab: String(tabs[next].id) })
  }

  function cycleTab(direction) {
    var count = tabs.length
    if (count < 2) return
    selectTab(tabs[(currentIndex + direction + count) % count].id)
  }

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave a tab's inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (activeTabItem && typeof activeTabItem.panelClosed === "function") activeTabItem.panelClosed()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (activeTabItem && typeof activeTabItem.refresh === "function") activeTabItem.refresh()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    // O shell passou a entregar aos plugins um PluginBarApi, e nele
    // centerHoverRevealSuppressed e readonly (Ui/PluginBarApi.qml:26): a
    // atribuicao direta lanca TypeError. Como close() chamava isto ANTES de
    // controller.hide(), a excecao abortava a funcao e o painel nunca fechava,
    // deixando a layer omarchy-keyboard-panel presa na tela em 1536x864.
    // Corrigido em 2026-09-09 copiando o padrao dos paineis do proprio Omarchy
    // (plugins/panels/clock/Panel.qml): preferir o setter da API e manter a
    // atribuicao apenas como fallback para o Bar real.
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write these keys straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Kept on the panel rather than the calendar because the bar widget's IPC
  // route reaches for it by name and should not have to know which tab owns
  // it. Delegates to whichever tab does.
  function toggleWeekStart() {
    var page = pageAt(indexOfTab("calendar"))
    if (page && typeof page.toggleWeekStart === "function") page.toggleWeekStart()
  }

  // ---- Which page is actually on screen. A module that costs something to
  //      show — a discovery sweep, a poll — needs to be told when it stops
  //      being looked at, which is a different moment from the panel closing:
  //      switching tabs hides one page and shows another with the panel still
  //      open. Panels that cost nothing simply never define the hooks.
  property var shownTabItem: null

  function updateShownTab() {
    var next = (root.opened && root.activeTabItem) ? root.activeTabItem : null
    if (next === shownTabItem) return
    if (shownTabItem && typeof shownTabItem.tabHidden === "function") shownTabItem.tabHidden()
    shownTabItem = next
    if (shownTabItem && typeof shownTabItem.tabShown === "function") shownTabItem.tabShown()
  }

  onOpenedChanged: updateShownTab()
  onActiveTabItemChanged: updateShownTab()

  // Hand the keyboard back to the panel after a tab's inline editor closes.
  function focusKeyCatcher() {
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function pageAt(index) {
    var entry = pages.itemAt(index)
    return entry && entry.tabItem ? entry.tabItem : null
  }

  // ---- Scrolling the current page. A tall module should not have to own a
  //      Flickable to be reachable by keyboard, so the panel drives the one
  //      it already wraps every page in.
  function scrollActivePage(delta) {
    var page = pages.itemAt(currentIndex)
    if (!page || page.contentHeight <= page.height) return
    page.contentY = Math.max(0, Math.min(page.contentHeight - page.height, page.contentY + delta))
  }

  function scrollActivePageToEnd() {
    var page = pages.itemAt(currentIndex)
    if (!page || page.contentHeight <= page.height) return
    page.contentY = page.contentHeight - page.height
  }

  onSettingsChanged: syncTab()

  onCurrentIndexChanged: Qt.callLater(function() {
    root.activeTabItem = root.pageAt(root.currentIndex)
    if (root.opened) root.refresh()
  })

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    // Measured from where the pages actually start rather than by adding the
    // chrome back up: stack.y already carries the strip, the separator and
    // both margins, so nothing above the pages can be left out of the total.
    contentHeight: panel.fittedContentHeight(stack.y + stack.contentHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.activeTabItem ? root.activeTabItem.keysBlocked === true : false

      // Arrows, Enter and printable keys belong to whatever is on screen;
      // the panel only keeps the keys that move between pages. A tab that
      // does not consume a key returns falsy and the panel lets it go.
      // A page that does not claim the key gets the panel's default, which
      // is to scroll it — the sane fallback for a module too tall to fit.
      onMoveRequested: function(dx, dy) {
        var item = root.activeTabItem
        if (item && typeof item.handleMove === "function" && item.handleMove(dx, dy) === true) return
        if (dy !== 0) root.scrollActivePage(dy * Style.space(24))
      }
      onActivateRequested: {
        if (root.activeTabItem && typeof root.activeTabItem.handleActivate === "function")
          root.activeTabItem.handleActivate()
      }
      // A page may back out of its own layer first — a confirmation, an
      // open composer — and only fall through to closing once it has none
      // left. Pages without that state never define handleClose.
      onCloseRequested: {
        var item = root.activeTabItem
        if (item && typeof item.handleClose === "function" && item.handleClose() === true) return
        root.close()
      }
      // Tab walks the hub's own pages first — with the modules folded into
      // one panel, that is what "next" means from inside it. Only from the
      // last page does it hand off to the next panel on the bar.
      onTabRequested: function(direction) {
        var next = root.currentIndex + direction
        if (next < 0 || next >= root.tabs.length) {
          if (root.switchPanel(direction)) return
          root.cycleTab(direction)
          return
        }
        root.selectTab(root.tabs[next].id)
      }
      onTextKey: function(t) {
        // Digits jump straight to a page, so a hub with five modules is
        // still one keystroke deep.
        var digit = parseInt(t, 10)
        if (!isNaN(digit) && digit >= 1 && digit <= root.tabs.length) {
          root.selectTab(root.tabs[digit - 1].id)
          return
        }
        if (root.activeTabItem && typeof root.activeTabItem.handleTextKey === "function")
          root.activeTabItem.handleTextKey(t)
      }

      // ---- Tab strip. Centered over the page it switches, and the one
      //      piece of chrome that is always in the same place no matter
      //      which module is up.
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: tabStrip.implicitHeight

        ButtonGroup {
          id: tabStrip
          anchors.horizontalCenter: parent.horizontalCenter
          options: {
            var out = []
            for (var i = 0; i < root.tabs.length; i++) {
              out.push({
                value: String(root.tabs[i].id),
                label: String(root.tabs[i].label),
                icon: String(root.tabs[i].icon || ""),
                tooltip: String(root.tabs[i].label) + "  ·  " + (i + 1)
              })
            }
            return out
          }
          value: root.currentTabId
          foreground: root.contentForeground
          background: root.bar ? root.bar.background : Color.background
          accent: Color.accent
          fontFamily: root.contentFontFamily
          fontSize: Style.font.bodySmall
          // The panel drives the keyboard itself; letting the strip take
          // Tab focus would swallow h/l before the page ever sees them.
          focusable: false
          onChanged: function(value) { root.selectTab(value) }
        }
      }

      PanelSeparator {
        id: headerRule
        anchors.top: header.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        foreground: root.contentForeground
      }

      // ---- Pages. One Flickable per tab so a module only has to report an
      //      honest implicitHeight and the panel handles a screen too short
      //      to show it. Loaded on first visit and kept after, so stepping
      //      back to the calendar lands on the month you left it on.
      Item {
        id: stack
        anchors.top: headerRule.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        readonly property real contentHeight: {
          var item = root.activeTabItem
          return item ? item.implicitHeight : 0
        }

        Repeater {
          id: pages
          model: root.tabs

          Flickable {
            id: page
            required property var modelData
            required property int index

            // Loaded on first visit, kept afterwards: a module that has to
            // rebuild its state on every tab switch is a module that loses
            // it, and none of them are expensive enough to be worth that.
            property bool everShown: index === root.currentIndex
            readonly property var tabItem: tabLoader.item

            anchors.fill: parent
            visible: index === root.currentIndex
            enabled: visible
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: tabLoader.width
            contentHeight: tabLoader.height
            interactive: contentHeight > height || contentWidth > width

            onVisibleChanged: if (visible) everShown = true

            Loader {
              id: tabLoader
              active: page.everShown
              source: page.everShown ? Qt.resolvedUrl(String(page.modelData.source)) : ""
              // Never narrower than the module asked for. The popup width is
              // capped to what the screen allows, and a fixed-width grid
              // would otherwise lose its last column off the edge instead of
              // scrolling.
              width: Math.max(page.width, page.modelData.minWidth || 0)
              height: item ? item.implicitHeight : 0

              onLoaded: {
                if ("hub" in item) item.hub = root
                if ("bar" in item) item.bar = root.bar
                if ("foreground" in item) item.foreground = Qt.binding(function() { return root.contentForeground })
                if ("fontFamily" in item) item.fontFamily = Qt.binding(function() { return root.contentFontFamily })
                if (page.index === root.currentIndex) {
                  root.activeTabItem = item
                  if (root.opened) root.refresh()
                }
              }
            }
          }
        }
      }
    }
  }

  Component.onCompleted: Qt.callLater(function() { root.activeTabItem = root.pageAt(root.currentIndex) })
}
