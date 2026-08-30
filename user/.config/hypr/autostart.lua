-- Extra autostart processes.

-- NOTA: libinput-gestures ficou de fora de propósito. Ele já sobe pelo XDG
-- autostart (~/.config/autostart/libinput-gestures.desktop ->
-- app-libinput-gestures@autostart.service); repetir aqui daria duas instâncias.

-- Periféricos Logitech.
o.launch_on_start("solaar --window=hide")

-- Night light. O `omarchy toggle nightlight` conversa com um hyprsunset já em
-- execução, então ele precisa subir junto com a sessão.
o.launch_on_start("hyprsunset")

-- Serviço do Nautilus, para abrir pastas sem esperar o app inteiro.
o.exec_on_start('bash -c "sleep 5 && nautilus --gapplication-service"')

-- Monitor de microfone (script pessoal em ~/.local/bin).
o.exec_on_start("/home/kevin/.local/bin/omarchy-mic-monitor")

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
