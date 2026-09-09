-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
  input = {
    -- US international: dead keys para acentuação (á, ã, ç...).
    -- O default do Omarchy lê /etc/vconsole.conf, que não tem XKBVARIANT.
    kb_layout = "us",
    kb_variant = "intl",
    kb_options = "compose:caps",

    -- Change speed of keyboard repeat.
    repeat_rate = 40,
    repeat_delay = 600,

    -- Start with numlock on by default.
    numlock_by_default = true,

    -- Apply natural scrolling at the compositor level so it also covers the
    -- virtual mouse created by input-remapper after reconnects or wake-ups.
    natural_scroll = true,

    touchpad = {
      -- Use natural (inverse) scrolling.
      natural_scroll = true,

      -- Use two-finger clicks for right-click instead of lower-right corner.
      clickfinger_behavior = true,

      -- Control the speed of your scrolling.
      -- 1.0 (o padrao do Hyprland), nao os 0.4 que o Omarchy usa
      -- (/usr/share/omarchy/default/hypr/input.lua:67). O padrao do Hyprland e
      -- 1.0, e mesmo ele ficou lento demais para o Kevin neste touchpad.
      -- Lembrar que os multiplicadores por app abaixo se aplicam POR CIMA deste
      -- valor: ghostty em 0.2 fica 5x mais lento que o resto.
      scroll_factor = 1.0,

      -- Enable tap to click.
      tap_to_click = true,
    },
  },
})

-- App-specific touchpad scroll speeds já vêm nos defaults do Omarchy
-- (Alacritty|kitty|foot = 1.5, ghostty = 0.2).

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })

-- Multiplicador de scroll do touchpad por app. Vinha do input.conf do Omarchy 3
-- ("windowrule = match:class (Alacritty|kitty|foot), scroll_touchpad 1.5") e NAO
-- foi migrado pelo upgrade para o Quattro -- auditoria de 2026-08-30.
-- Terminais rolam poucas linhas por gesto, dai o 1.5; o ghostty ja rola demais
-- por conta propria, dai o 0.2.
o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
-- Flea (gerenciador de arquivos padrao desde 2026-09-08): mesmo multiplicador
-- dos terminais. Aplica-se POR CIMA do scroll_factor global acima, entao aqui
-- o efetivo e 1.0 x 1.5 -- listas longas de arquivo pedem mais que o resto.
o.window("com.thisisgm.flea", { scroll_touchpad = 1.5 })
