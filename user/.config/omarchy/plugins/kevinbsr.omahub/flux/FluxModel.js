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

// ---- The shared clipboard, from the pushed state: backend path only.

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

// ---- The payloads fluxd expects.
//
// These are not guesses. They were captured by pointing Flux's own CLI at a
// stand-in socket that logged the request and answered with an empty result,
// so nothing reached the phone: `flux ping`, `flux url`, `flux clip`,
// `flux sms` and `flux send` each showed their exact JSON. The tests below
// pin those shapes, which is the only way this file can be wrong without
// somebody's phone being the one to find out.

function pingParams(device, message) {
  return { device: deviceId(device), message: String(message || "") }
}

// A link opens in the browser on the phone; anything else lands as text to
// copy or read. Flux has a method for each, and asking the person to pick
// which one they meant would be a question with an obvious answer.
function shareMethod(text) {
  return /^(https?|ftp|magnet|mailto):/i.test(String(text || "").trim()) ? "share.url" : "share.text"
}

function textParams(device, text) {
  return { device: deviceId(device), text: String(text || "") }
}

function urlParams(device, url) {
  return { device: deviceId(device), url: String(url || "") }
}

// clipboard.send with no text means "this machine's current clipboard", which
// is what the toolbar button sends; the composer path passes text.
function clipboardParams(device, text) {
  var params = { device: deviceId(device) }
  if (typeof text === "string" && text !== "") params.text = text
  return params
}

// Note the plural, and that addresses is a list: one message can go to several
// numbers even though the page only offers one field.
function smsParams(device, to, body) {
  return { device: deviceId(device), addresses: [String(to || "")], body: String(body || "") }
}

function filesParams(device, paths) {
  return { device: deviceId(device), paths: (paths || []).filter(function (p) { return !!p }) }
}

function unpairParams(device) {
  return { device: deviceId(device) }
}

// What the phone says it can do. A device advertises its capabilities when it
// pairs, and Flux passes that list through as `plugins`. An action whose
// capability is missing would fail silently on the wire, so the button for it
// is not drawn -- the same rule the Android Mirror section follows for
// notifications that cannot be dismissed.
//
// Observed on a Galaxy S23 Ultra running Flux for Android 0.4.0: battery,
// clipboard, findmyphone, notifications, runcommand and share, with no `sms`,
// `sftp` or `connectivity_report`, which is why the SMS button can be absent
// on a perfectly healthy pairing.
var CAPABILITY = {
  ring: "findmyphone",
  clipboard: "clipboard",
  share: "share",
  sms: "sms"
}

function supports(device, action) {
  var needed = CAPABILITY[action]
  if (!needed) return true            // ping has no plugin of its own
  var plugins = (device && device.plugins) || []
  if (!Array.isArray(plugins) || plugins.length === 0) return true  // says nothing: assume yes
  return plugins.indexOf(needed) >= 0
}

function deviceId(device) {
  return device && device.id ? String(device.id) : ""
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
    clipboard: clipboard,
    clipboardMeta: clipboardMeta,
    timeAgo: timeAgo,
    pingParams: pingParams,
    urlParams: urlParams,
    textParams: textParams,
    shareMethod: shareMethod,
    clipboardParams: clipboardParams,
    smsParams: smsParams,
    filesParams: filesParams,
    unpairParams: unpairParams,
    supports: supports
  }
}
