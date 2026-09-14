-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- No compositor animation on the shell's click-outside-to-close layers.
--
-- Omarchy already sets no_anim on its panel layer, but the pattern ends in `$`:
-- ^(...|omarchy-keyboard-panel)$ -- so it misses omarchy-keyboard-panel-dismiss,
-- the fully transparent, full-screen layer the shell maps on every OTHER monitor
-- each time a panel opens. Those fell through to the default layersIn fade
-- (400 ms, easeOutQuint): nothing visible fades, but Hyprland still redraws
-- those whole outputs for the length of the animation -- here DP-1 at 3440x1440
-- and HDMI-A-1, both on the NVIDIA card, so every frame also crosses GPUs.
-- Measured 2026-09-13 as ~17% of the compositor's work per panel open
-- (~116 -> ~96 ms), with no visual difference. Worth an upstream fix to the
-- pattern in default/hypr/apps/omarchy-shell.lua.
hl.layer_rule({
  match = { namespace = "^omarchy-keyboard-panel-dismiss$" },
  no_anim = true,
  animation = "none",
})
