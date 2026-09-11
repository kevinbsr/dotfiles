-- Extra autostart processes.

-- NOTA: libinput-gestures ficou de fora de propósito. Ele já sobe pelo XDG
-- autostart (~/.config/autostart/libinput-gestures.desktop ->
-- app-libinput-gestures@autostart.service); repetir aqui daria duas instâncias.

-- Periféricos Logitech.
o.launch_on_start("solaar --window=hide")

-- Night light. O `omarchy toggle nightlight` conversa com um hyprsunset já em
-- execução, então ele precisa subir junto com a sessão.
o.launch_on_start("hyprsunset")

-- Flea became the default file manager on 2026-09-08 (via `flea --default`),
-- replacing the Nautilus service that used to stay resident from login.
--
-- A page-cache pre-warm USED TO LIVE HERE (a `cat` of the GL libraries and the
-- Flea binary, 8s after login). Removed on 2026-09-09 after measuring it
-- properly. The older numbers that justified it were wrong: they claimed
-- "~48 ms warm", which is what you get timing the command's return rather than
-- the window appearing.
--
-- Measured from exec to Hyprland's `openwindow` event:
--     Flea warm .................. ~700 ms
--     Flea cold, no pre-warm ..... 1077 ms
--     Flea cold, pre-warmed ......  856 ms
--     Nautilus cold, nothing resident 810 ms
--
-- So the pre-warm bought 221 ms, ONCE per boot, at the cost of reading 70 MB on
-- every login. And the bulk of the cost -- ~700 ms -- is not paging, it is
-- Flea's own startup, which no cache fixes. Do not add it back without
-- measuring through openwindow again.
--
-- (Flea also leaks 2 processes per launch, a `qs` and a `flea --backend`, and
-- does NOT reuse them: the 3rd launch costs the same as the 1st. Reported
-- upstream as thisisgm/flea#102.)

-- Monitor de microfone (script pessoal em ~/.local/bin).
-- omarchy-mic-monitor REMOVIDO em 2026-09-02: era codigo morto desde o Quattro.
-- Ele fazia apenas `pactl subscribe | ... pkill -RTMIN+9 waybar`, ou seja,
-- sinalizava o Waybar para redesenhar o icone do microfone. O Waybar nao roda
-- mais (segue instalado so como dependencia do waybar-module-pacman-updates-git,
-- e ~/.config/waybar nem existe), entao o pkill nunca acertava nada -- ficavam
-- dois processos vivos desde o boot assinando eventos do PulseAudio a toa.
-- Quem mostra o microfone hoje e o plugin nativo omarchy.microphone.

-- Cor e brilho do backlight do teclado. Variantes Dell explícitas: os wrappers
-- genéricos do Quattro não conhecem o G15. Ver ~/.config/omarchy/hooks/theme-set.d/.
o.exec_on_start("omarchy-theme-set-keyboard-dell-g15 && omarchy-brightness-keyboard-dell-g15 restore")

-- KDE Connect.
o.exec_on_start("/usr/bin/kdeconnectd")
-- o.exec_on_start("kdeconnect-indicator")

-- libinput-gestures: estava no autostart.conf do Omarchy 3 e NAO foi migrado
-- pelo upgrade -- auditoria de 2026-08-30. Sem ele os 6 gestos de
-- ~/.config/libinput-gestures.conf ficaram mortos: 3 dedos cima/baixo
-- (fullscreen, flutuante) e 4 dedos (mover entre workspaces e o especial).
-- Nao conflita com o hl.gesture do input.lua: aquele e 3 dedos HORIZONTAL,
-- estes sao 3 dedos vertical e 4 dedos.
-- TODO: migrar para hl.gesture nativo (o campo `action` aceita funcao), o que
-- dispensaria o daemon. Nao feito porque o enum de direcoes nao esta nos stubs.
o.exec_on_start("libinput-gestures")
