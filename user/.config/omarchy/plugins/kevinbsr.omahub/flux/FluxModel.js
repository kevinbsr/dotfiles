// Reading `flux status --json`. Kept out of the QML so it can be tested
// without a shell, the same split the rest of this plugin uses.
//
// The shape, observed from fluxd 0.4.0:
//   devices: [{ id, name, type, ip, paired, online, pairState, pairKey,
//               battery: { charge, charging }, plugins: [...] }]
// Everything here treats every field as optional: this is another project's
// output, and a missing key must degrade to a quieter row rather than throw
// inside a delegate.

function devices(status) {
  var list = (status && status.devices) || []
  if (!Array.isArray(list)) return []
  return list
    .filter(function (device) { return device && device.name })
    // Paired first, then reachable, then by name: the phone someone actually
    // uses should not move around as other devices appear on the network.
    .sort(function (a, b) {
      if (!!a.paired !== !!b.paired) return a.paired ? -1 : 1
      if (!!a.online !== !!b.online) return a.online ? -1 : 1
      return String(a.name).localeCompare(String(b.name))
    })
}

function usable(device) {
  return !!(device && device.paired && device.online)
}

function deviceTitle(device) {
  return device && device.name ? String(device.name) : "Unknown device"
}

function batteryText(device) {
  var battery = device && device.battery
  if (!battery || typeof battery.charge !== "number") return ""
  return battery.charge + "%" + (battery.charging ? " charging" : "")
}

function deviceSubtitle(device) {
  if (!device) return ""
  var parts = []
  if (!device.paired) parts.push(device.pairState === "requested" ? "wants to pair" : "not paired")
  else if (!device.online) parts.push("offline")
  else parts.push("connected")

  var battery = batteryText(device)
  if (battery !== "") parts.push(battery)
  if (device.type && device.type !== "phone") parts.push(String(device.type))
  return parts.join(" · ")
}

// The one device waiting on a decision, if any. Flux reports it through
// pairState, and the key is what the person compares against the phone.
function pendingPairing(list) {
  var pending = (list || []).filter(function (device) {
    return device && !device.paired && device.pairState && device.pairState !== "paired"
      && device.pairState !== "unpaired" && device.pairState !== "none"
  })
  return pending.length > 0 ? pending[0] : null
}

// ---- What the phone is showing and what the two machines have copied.
//      Both come from the pushed state, so they exist only on the backend
//      path; the CLI fallback has devices and actions and nothing else.

// The phone's notifications, newest first. `app` is the Android app label,
// `dismissable` says whether the × can do anything, and `replyId` marks the
// ones a keyboard could answer (15 of 94 here -- WhatsApp and friends).
function notifications(device, limit) {
  var list = (device && device.notifications) || []
  if (!Array.isArray(list)) return []
  return list
    .filter(function (n) { return n && (n.title || n.text) })
    .sort(function (a, b) { return (b.time || 0) - (a.time || 0) })
    .slice(0, limit || 6)
}

function notificationCount(device) {
  var list = (device && device.notifications) || []
  return Array.isArray(list) ? list.length : 0
}

// One line for a notification: the app, then how long ago. The title and text
// are drawn separately, because they are the part worth reading.
function notificationMeta(entry, nowSeconds) {
  if (!entry) return ""
  var parts = []
  if (entry.app) parts.push(String(entry.app))
  var ago = timeAgo(entry.time, nowSeconds)
  if (ago !== "") parts.push(ago)
  return parts.join(" · ")
}

// Shared clipboard, newest first. `dir` is "in" (from the phone) or "out"
// (from here), which is the only way to tell whose copy this was.
function clipboard(state, limit) {
  var list = (state && state.clipboard) || []
  if (!Array.isArray(list)) return []
  return list
    .filter(function (entry) { return entry && typeof entry.text === "string" && entry.text !== "" })
    .slice(0, limit || 3)
}

function clipboardMeta(entry, nowSeconds) {
  if (!entry) return ""
  var who = entry.dir === "in" ? ("from " + (entry.deviceName || "the phone")) : "from this computer"
  var ago = timeAgo(entry.time, nowSeconds)
  return ago === "" ? who : who + " · " + ago
}

// Coarse on purpose: this sits under a title in caption type, where "2m" says
// as much as a timestamp and takes a third of the room.
function timeAgo(seconds, nowSeconds) {
  if (typeof seconds !== "number" || seconds <= 0) return ""
  var now = typeof nowSeconds === "number" ? nowSeconds : Math.floor(Date.now() / 1000)
  var delta = Math.max(0, now - seconds)
  if (delta < 60) return "now"
  if (delta < 3600) return Math.floor(delta / 60) + "m"
  if (delta < 86400) return Math.floor(delta / 3600) + "h"
  return Math.floor(delta / 86400) + "d"
}

// QML reads these as plain functions off the imported namespace; the node
// tests need them as a CommonJS module. Same guard the other models here use.
if (typeof module !== "undefined") {
  module.exports = {
    devices: devices,
    usable: usable,
    deviceTitle: deviceTitle,
    batteryText: batteryText,
    deviceSubtitle: deviceSubtitle,
    pendingPairing: pendingPairing,
    notifications: notifications,
    notificationCount: notificationCount,
    notificationMeta: notificationMeta,
    clipboard: clipboard,
    clipboardMeta: clipboardMeta,
    timeAgo: timeAgo
  }
}
