# kevin.hub

One bar widget that holds what used to be `omarchy.clock`, `kevin.media` and
`omarchy.weather`: a condition glyph and a date/time label on the bar, and a
tabbed panel behind them.

```
BarWidget.qml      weather glyph + clock label + media glyph; IPC `kevin.hub`
Panel.qml          the popup: tab strip, keyboard routing, settings writes
CalendarTab.qml    calendar page (was omarchy.clock's Panel.qml)
MediaTab.qml       media page    (redesigned; was kevin.media's PopupCard)
WeatherTab.qml     weather page  (was omarchy.weather's Panel.qml, view half)
WeatherSource.qml  weather data  (was omarchy.weather's Panel.qml, model half)
ScreenTimeTab.qml  screen time   (was agx.screen-time's Panel.qml)
KdeConnectTab.qml  phone         (omaconnect's Panel.qml state machine)
kdeconnect/        omaconnect's four sections, vendored — see VENDORED.md
NearbyTab.qml      nearby page   (oma.nearby's Panel.qml, view half)
NearbyModel.js     transfer formatting, from oma.nearby
Service.qml        MPRIS service; owns the IPC target `media`
ClockModel.js      date maths, from omarchy.clock
MediaModel.js      player ranking helpers, from omarchy.media
WeatherModel.js    wttr/open-meteo parsing, from omarchy.weather
ScreenTimeModel.js formatting and grouping, from agx.screen-time
```

The media page splits its controls in two on purpose. Transport — play,
pause, next, previous — goes through `Service.qml`, so a click there and a
media key are the same action against the same player ranking. Seeking,
shuffle and loop have no media key and no service route, so they are set on
the active MPRIS player directly.

Volume is the exception to the exception: it goes to **PipeWire**, not MPRIS.
Chromium advertises the MPRIS `Volume` property and silently discards writes
to it — measured, not assumed: setting 0.35 leaves it reading 1.0 with the
audio untouched. The stream volume always works, and using it means this
slider and the active source's row in the list are the same number rather
than two that disagree. MPRIS volume survives only as a fallback for a player
with no live stream to point at.

Every control on the page is drawn only where the player reports it works, so
nothing appears as dead decoration — a browser gets no shuffle or loop button,
where Spotify gets both.

Position is polled, not bound — MPRIS does not push it — and the poll runs
only while the page is the one on screen, which is what `tabShown`/`tabHidden`
buy. Nerd-font codepoints for its glyphs were confirmed by rendering them,
not from memory: `F049C`, plausibly "shuffle_disabled", is a printer.

Its sources list reaches past MPRIS into PipeWire. One player can own several
playback streams — Chromium opens one per tab that makes sound — so each
source row carries an app-level volume that moves all of its streams
together, and unfolds (chevron, or `e`) into one slider and mute per stream.

The selected source is the exception: its app-level slider is hidden, because
the one under the timeline is already that same control over those same
streams. Unfolding it still works — the per-stream rows are the part the
slider above cannot reach.

Those per-stream rows are numbered, not named, and that is a limit of the
browser rather than a shortcut here: every Chromium stream is called
`media.name = "Playback"`, with only `client.id` / `object.id` /
`object.serial` telling them apart. Nothing anywhere maps a stream to a tab.
They are ordered by `object.serial`, which only counts up, so the numbering
is the order they started in — and the mute button is how you find out which
is which.

The chevron carries `z: 1` on the row's content for a reason: the MouseArea
that selects the whole source is declared after it, and a later sibling sits
on top in QML, so without the lift it swallowed every click aimed at the
chevron. Hover told the story — the tooltip never appeared either.

`Service.qml` carries one deliberate divergence from the `omarchy.media` it
was cloned from: in `selectActivePlayer`, an explicit pick from the sources
list now outranks the heuristics instead of sitting behind them. Upstream put
it after "whoever holds a PipeWire playback stream", and Spotify keeps its
stream open while paused where a browser drops its own — so clicking a paused
browser source stored the preference and changed nothing on screen. Keep this
in mind on any resync.

`Service.qml` is the same service the media keys land on — it is why this
plugin declares `"service"` alongside `"bar-widget"`, and why `kevin.media`
has to stay out of the bar: two plugins cannot both own the `media` target.

`ScreenTimeTab.qml` is the one page whose data is **not** this plugin's.
`agx.screen-time` stays installed and enabled as a service — listed in
`plugins[]` in `shell.json` rather than in the bar layout, which is what
keeps its component loaded while it shows nothing of its own — and the page
reads it through `shell.serviceFor("agx.screen-time")`. Only the drawing was
copied, because upstream's panel is already a read-only mirror of that
service. The collector, its state file and `resolve_app.py` stay upstream, so
`omarchy plugin update` still maintains them; what can drift is the copied
view. If that plugin is removed, the page says so and the rest of the hub is
unaffected.

`KdeConnectTab.qml` splits the same way, but its view is **vendored** rather
than read live. `omaconnect` stays installed as a service, and its four
section components sit copied under `kdeconnect/` — see
`kdeconnect/VENDORED.md` for the revision and the resync recipe. Those
sections take a `panel` object and read their whole state off it, so this tab
is that object: upstream's `Panel.qml` state machine at the same revision.

They were briefly imported straight out of the other plugin's directory
instead. That is the version of this that does not survive: `panel.*` is
omaconnect's internal contract, free to change in any release, and a single
`omarchy plugin update` could have moved it under us. Vendoring freezes the
pair — sections and state machine — at one known revision, and a resync is a
deliberate step rather than an ambush.

What stays live is `serviceFor("omaconnect")`. That one is a published
wrapper of aliases, used by the plugin's own bar widget, and its changes so
far have been purely additive.

`NearbyTab.qml` is the third of these. `oma.nearby` stays installed as a
service — that service *is* the engine, owning the Rust helper, the transfer
state and the `oma.nearby` IPC target — and upstream's `Panel.qml` was
already only a view onto it, built once per monitor. This page is that view.
The three `Process` helpers came across with it, for upstream's own reason: a
file chooser and a clipboard belong to the screen the user acted on.

It is pinned to the **installed** revision rather than the newest one. v1.1.0
adds an incoming PIN that also rewrites the Rust helper, and `bin/` is
gitignored — updating the tree without rebuilding would leave new QML driving
an old binary. Resync only alongside a rebuilt helper; `NearbyModel.js` says
which revision it is at.

Its `receiverEnabled` setting rides along in `plugins[]`. The service reads
its own `shell.json` entry rather than any widget's copy, and both that read
(`Model.barEntry`) and the write (`shell.updateEntryInline`) fall back to
`plugins[]` when the id is not in the bar — which is why the receiver still
toggles and persists with nothing on the bar.

`WeatherSource.qml` is split out of the page for the same kind of reason.
Pages load on first visit, but the bar glyph has to show a condition from
startup, so `Panel.qml` owns one `WeatherSource` and hands it to both the
page and (through the panel) the bar widget. **A module whose bar presence
outlives its page needs this split**; a module that only exists inside its
page does not.

## Adding a module

1. Write `<Name>Tab.qml`. It is a plain `Item` that lays itself out and
   reports an honest `implicitHeight`; `Panel.qml` gives it the popup, the
   scrolling and the chrome.
2. Add one line to `tabs` in `Panel.qml`:

```qml
{ id: "timers", label: "Timers", icon: "󰔛", source: "TimersTab.qml", minWidth: Style.space(420) }
```

That is the whole change. The strip, the digit shortcut, the lazy loading
and the persisted last-used tab all follow from the list.

### What a tab may declare

All optional — declare what you need and ignore the rest.

| Member | Purpose |
|---|---|
| `property var hub` | this panel: `setting()`, `persistSettings()`, `close()` |
| `property QtObject bar` | the bar host (`bar.shell`, `bar.run`, …) |
| `property color foreground` | theme foreground, injected |
| `property string fontFamily` | theme font, injected |
| `property bool keysBlocked` | true while an inline editor owns the keyboard |
| `function handleMove(dx, dy)` | arrow keys / hjkl |
| `function handleActivate()` | Enter / Space |
| `function handleTextKey(t)` | one printable key |
| `function refresh()` | panel opened, or `refresh` came over IPC |
| `function handleClose()` | Escape; return true to keep the panel open |
| `function tabShown()` | became the visible page of an open panel |
| `function tabHidden()` | stopped being it — tab switch or panel close |
| `function panelClosed()` | panel dismissed; drop transient state |

Settings are shared: every tab reads and writes the one `kevin.hub` entry in
`shell.json`, so prefix keys that could collide.

There is one bar surface — so one `Panel.qml` — **per monitor**. Anything a
module wants the other screens to agree on has to go through
`persistSettings()`; the write comes back to every instance as a settings
change. That is how the active tab stays in step, and why `currentIndex`
follows `settings` instead of being set once.

## Keys

| Key | Does |
|---|---|
| `Tab` / `Shift+Tab` | next / previous page, then off to the next bar panel |
| `1`…`9` | jump to a page |
| `Esc` | close |

Calendar: `←`/`→` month, `↑`/`↓` year, `[`/`]`/`{`/`}` the same, `t` today,
`w` week start, double-tap the year bar for memento mori.
Media: `←`/`→` seek ∓5s (skip tracks instead on a player that cannot seek),
`↑`/`↓` walk sources, `Enter` play/pause or pick the cursored source,
`p` play-pause, `n`/`b` next / back, `m` mute, `s` shuffle, `r` repeat,
`e` unfold the cursored source's individual streams.
Weather: `Enter` edits the location, then `↑`/`↓` walk the suggestions.
Screen: `p` toggles the patterns section.
Phone: arrows walk devices / actions / commands, `Enter` activates, `r`
refreshes, `p` pairs, `u` unpairs, then `y` / `c` confirm or cancel. Escape
backs out of a confirmation or a composer before it closes the panel.
Nearby: `↑`/`↓` walk the receiver toggle, the devices and the rescan row,
`Enter` activates. Escape backs out of a PIN prompt or a chosen target first.

`tabShown` / `tabHidden` exist for modules that cost something while looked
at. Nearby is the reason: its discovery sweep starts when the page becomes
visible and is cancelled the moment you switch tabs, not just when the panel
closes.

A page that does not claim `↑`/`↓` gets the panel's default for them, which
is to scroll itself — so a tall module needs no Flickable of its own.

## The bar

Three hit areas in one slot: `󰖐  Monday 01:39  󰏤`

| | Weather glyph | Clock label | Media glyph |
|---|---|---|---|
| left | the weather page | **the calendar** | play / pause |
| right | conditions as a notification | cycle the label format | the media page |
| middle | refetch the forecast | timezone picker | next track |
| scroll | — | — | previous / next |

Each of those page clicks is a toggle *onto* a page, never a resume of
wherever the panel was last left. The clock is about the date, so it opens
the calendar every time, whatever tab the panel closed on; a second click
with that page already up is what closes the panel, and clicking a different
glyph switches pages instead of closing.

The persisted last-used tab still governs `omarchy-shell kevin.hub toggle`
and a fresh session — it is only the bar's glyphs that override it, because
each one is a question with a specific answer.

Media keeps the bindings `kevin.media` had, with "the popup" now meaning the
media page. Its glyph collapses when no player is around and dims when one
is paused, so the bar is just a clock when there is nothing to press.

Both glyphs sit in fixed-width slots on purpose. This widget is the bar's
`centerAnchor`, so a sun becoming a thunderstorm — or a play triangle
becoming a pause bar — would otherwise drag the whole center row sideways.

## IPC

```bash
omarchy-shell kevin.hub toggle
omarchy-shell kevin.hub tab weather    # open straight onto a page
omarchy-shell kevin.hub tabToggle calendar  # what the clock glyph does
omarchy-shell kevin.hub cycleFormat    # same as right-clicking the label
omarchy-shell kevin.hub refreshWeather
omarchy-shell media playPause          # from Service.qml, what media keys use
```

## Gotcha

Saving a file here usually hot-reloads, but the watcher does go stale. If an
edit does not seem to apply — settings arriving empty is the tell — run
`omarchy restart shell` before debugging the code.
