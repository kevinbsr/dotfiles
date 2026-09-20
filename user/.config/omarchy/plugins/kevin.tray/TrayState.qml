pragma Singleton

import QtQuick
import Quickshell

// Drawer state that has to outlive the widget.
//
// Capturing, reordering or ejecting a widget writes shell.json, and any write
// there makes the shell rebuild the bar: every module slot is destroyed and
// recreated, this tray included. Anything kept in the widget itself — such as
// the pinned-open drawer — dies with it, so organizing the tray kept snapping
// the drawer shut mid-gesture.
//
// A singleton is instantiated once per QML engine and survives those
// rebuilds. State is keyed by screen so pinning the drawer on one monitor
// does not pin it on the others.
Singleton {
  id: state

  property var pinnedScreens: ({})

  function pinned(key) {
    return !!key && state.pinnedScreens[key] === true
  }

  function setPinned(key, value) {
    if (!key) return
    var next = {}
    for (var k in state.pinnedScreens) next[k] = state.pinnedScreens[k]
    if (value) next[key] = true
    else delete next[key]
    state.pinnedScreens = next
  }
}
