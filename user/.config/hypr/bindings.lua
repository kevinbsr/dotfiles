-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Scratchpad genérico separado do Quake console do Omarchy. O console
-- continua usando special:scratchpad; o scratchpad pessoal usa special:stash.
hl.unbind("SUPER + S")
hl.unbind("SUPER + ALT + S")
hl.unbind("SUPER + grave")
hl.unbind("SUPER + SHIFT + grave")

o.bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("stash"))
o.bind(
	"SUPER + ALT + S",
	"Move window to scratchpad",
	hl.dsp.window.move({ workspace = "special:stash", follow = false })
)
o.bind("SUPER + grave", "Toggle Quake console", hl.dsp.workspace.toggle_special("scratchpad"))
o.bind(
	"SUPER + SHIFT + grave",
	"Move window to Quake console",
	hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })
)

-- Apps que substituem os defaults do Omarchy.

-- Typora no lugar do Omawrite.
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "Typora", { launch = "typora --enable-wayland-ime" })

-- Bitwarden no lugar do 1Password.
hl.unbind("SUPER + SHIFT + SLASH")
o.bind("SUPER + SHIFT + SLASH", "Passwords", { launch = "bitwarden-desktop %u" })

-- IA: Gemini no lugar do ChatGPT, Claude num atalho próprio.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Gemini", { webapp = "https://gemini.google.com" })
o.bind("SUPER + SHIFT + CTRL + A", "Claude", { webapp = "https://claude.ai/new" })

-- Google Workspace no lugar do HEY.
hl.unbind("SUPER + SHIFT + C")
o.bind("SUPER + SHIFT + C", "Calendar", { webapp = "https://calendar.google.com/calendar/u/0/r" })

hl.unbind("SUPER + SHIFT + E")
o.bind("SUPER + SHIFT + E", "Email", { webapp = "https://mail.google.com/mail/u/0/#inbox" })

-- Mensageiros: WhatsApp assume o atalho do Signal, Telegram assume o do WhatsApp.
hl.unbind("SUPER + SHIFT + G")
o.bind("SUPER + SHIFT + G", "WhatsApp", { webapp = "https://web.whatsapp.com/", focus = true })

hl.unbind("SUPER + SHIFT + ALT + G")
o.bind("SUPER + SHIFT + ALT + G", "Telegram", { launch = "Telegram", focus = "Telegram" })

-- FIAP no lugar do Google Maps.
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "FIAP", { webapp = "https://on.fiap.com.br/" })

-- Áudio. Caminhos absolutos: scripts em ~/.local/bin não são resolvidos de
-- forma confiável pelo dispatcher de keybinds.
o.bind("SUPER + M", "Mute microphone", "/home/kevin/.local/bin/omarchy-audio-input-mute")
o.bind("SUPER + XF86AudioMicMute", "Switch audio input", "/home/kevin/.local/bin/omarchy-audio-input-switch")
o.bind("SUPER + CTRL + ALT + M", "Switch audio input", "/home/kevin/.local/bin/omarchy-audio-input-switch")

-- Brilho: o script pessoal espelha o brilho do painel interno nos monitores
-- externos via DDC/CI, coisa que o omarchy-brightness-display não faz.
hl.unbind("XF86MonBrightnessUp")
o.bind(
	"XF86MonBrightnessUp",
	"Brightness up",
	"/home/kevin/.local/bin/brigthness_control.sh +5%",
	{ locked = true, repeating = true }
)

hl.unbind("XF86MonBrightnessDown")
o.bind(
	"XF86MonBrightnessDown",
	"Brightness down",
	"/home/kevin/.local/bin/brigthness_control.sh 5%-",
	{ locked = true, repeating = true }
)

-- Backlight RGB do teclado do G15. O omarchy-brightness-keyboard empacotado
-- procura /sys/class/leds/*kbd_backlight*, que não existe nesta máquina (o RGB
-- fica atrás de ioctl no hidraw), então os atalhos vão direto na variante Dell.
-- No Omarchy 3 esse desvio era um patch dentro do próprio wrapper, que agora é
-- do pacman e não pode ser editado.
hl.unbind("XF86KbdBrightnessUp")
o.bind(
	"XF86KbdBrightnessUp",
	"Keyboard brightness up",
	"omarchy-brightness-keyboard-dell-g15 up",
	{ locked = true, repeating = true }
)

hl.unbind("XF86KbdBrightnessDown")
o.bind(
	"XF86KbdBrightnessDown",
	"Keyboard brightness down",
	"omarchy-brightness-keyboard-dell-g15 down",
	{ locked = true, repeating = true }
)

hl.unbind("XF86KbdLightOnOff")
o.bind("XF86KbdLightOnOff", "Keyboard backlight cycle", "omarchy-brightness-keyboard-dell-g15 cycle", { locked = true })

-- A tecla de backlight do TECLADO INTERNO precisa de bind por CODIGO, nao por
-- nome. Ela emite KEY_F18 (evdev 188 -> keycode X11 196), mas nao ha mapeamento
-- xkb para o keysym F18: medido em 2026-09-04, o bind "F18" nunca dispara e o
-- "code:196" dispara sempre.
--
-- Isto substitui o g15-backlight-key-listener.py, que lia /dev/input direto e
-- parou de funcionar em 2026-08-30, quando a migracao 1787865477.sh do Omarchy
-- removeu o usuario do grupo `input` ("Drop the default input group grant,
-- which allowed unprivileged keylogging"). O compositor le o teclado via
-- logind, com privilegio, entao nao precisa daquele grupo -- ou seja, esta
-- solucao NAO desfaz o endurecimento do Omarchy. Nao reverter para o listener.
--
-- O wrapper existe pelo anti-repique: a tecla repete enquanto pressionada
-- (19 eventos em 7 s, medido), e sem filtro cada toque pula varios niveis.
o.bind("code:196", "Keyboard backlight cycle", "/home/kevin/.local/bin/kbd-backlight-cycle cycle", { locked = true })

-- Tecla G do G15 (F9 / Fn+F9 / Keycodes 148, 194, 187, 202): alterna o perfil de alta performance e ventoinhas a 100%.
-- NAO vincular a tecla G por "code:N". O Hyprland usa keycode X11, que e o
-- codigo evdev + 8, e as quatro linhas que existiam aqui capturavam teclas
-- erradas (medido em 2026-08-31):
--   code:148 -> evdev 140 = KEY_CALC        <- a tecla de CALCULADORA
--   code:187 -> evdev 179 = KEY_KPLEFTPAREN <- o "(" do numpad
--   code:194 -> evdev 186 = KEY_F16
--   code:202 -> evdev 194 = KEY_F24         (ja vinculado por nome abaixo)
-- Sintoma: apertar a calculadora mostrava a notificacao de G-Mode sem as
-- ventoinhas subirem -- porque quem respondia era o omarchy-gmode-dell-g15
-- (que fala com a EC), nao o daemon (que e quem aplica boost 0xff).
--
-- A tecla G de verdade emite evdev 701 (KEY_PERFORMANCE), que nem caberia num
-- keycode X11 (701+8 = 709 > 255). Ela e tratada pelo listener evdev do
-- g15_fan_control.py, que e o caminho correto e ja funciona.
o.bind("F24", "G-Mode toggle", "omarchy-gmode-dell-g15 toggle", { locked = true })
o.bind("XF86Launch1", "G-Mode toggle", "omarchy-gmode-dell-g15 toggle", { locked = true })
o.bind("XF86Launch3", "G-Mode toggle", "omarchy-gmode-dell-g15 toggle", { locked = true })

-- Seletor de modo gráfico do supergfxd. Antes era um menu do walker
-- (menus:gpuswitcher); agora é uma rota no menu do Quickshell, definida em
-- ~/.config/omarchy/extensions/omarchy-menu.jsonc.
o.bind("SUPER + CTRL + G", "GPU mode (supergfxd)", "omarchy-menu summon trigger.hardware.gpu-mode")

-- super-w-wait:start
super_w_wait = { timeout = 1500 }
require("super-w-wait")
-- super-w-wait:end

-- Workspaces 11-15 (monitor LG vertical). O Omarchy so vincula 1-10, em
-- SUPER + code:(N+9) -- ou seja, as teclas de digito. Para 11-15 nao sobrou
-- combinacao com digito: SUPER+ALT+1..5 ja e "trocar de janela em grupo"
-- (tiling.lua:93) e SUPER+CTRL+1..9 e "abrir painel N" (utilities.lua:109).
-- SUPER + F1..F12 estava inteiramente livre, e e um acorde de duas teclas em
-- vez das quatro que sobrariam (SUPER+CTRL+ALT+digito).
for i = 1, 5 do
	local ws = tostring(i + 10)
	o.bind("SUPER + F" .. i, "Switch to workspace " .. ws, hl.dsp.focus({ workspace = ws }))
	o.bind("SUPER + SHIFT + F" .. i, "Move window to workspace " .. ws, hl.dsp.window.move({ workspace = ws }))
end

-- Fake fullscreen: faz o aplicativo achar que está em tela cheia sem mudar sua geometria no tiling.
o.bind("SUPER + CTRL + SHIFT + F", "Fake full screen", hl.dsp.window.fullscreen_state({ internal = 0, client = 2 }))

