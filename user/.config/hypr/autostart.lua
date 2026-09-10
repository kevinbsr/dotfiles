-- Extra autostart processes.

-- NOTA: libinput-gestures ficou de fora de propósito. Ele já sobe pelo XDG
-- autostart (~/.config/autostart/libinput-gestures.desktop ->
-- app-libinput-gestures@autostart.service); repetir aqui daria duas instâncias.

-- Periféricos Logitech.
o.launch_on_start("solaar --window=hide")

-- Night light. O `omarchy toggle nightlight` conversa com um hyprsunset já em
-- execução, então ele precisa subir junto com a sessão.
o.launch_on_start("hyprsunset")

-- O Flea virou o gerenciador de arquivos padrao em 2026-09-08 (via
-- `flea --default`), no lugar do servico do Nautilus, que ficava residente
-- desde o login.
--
-- AQUI EXISTIA um pre-aquecimento de page cache (um `cat` das libs de GL e do
-- binario do Flea, 8s apos o login). REMOVIDO em 2026-09-09 depois de medir
-- direito. As medicoes antigas que o justificavam estavam erradas: diziam
-- "quente ~48 ms", medindo o retorno do comando e nao a janela aparecer.
--
-- Medido do exec ate o evento `openwindow` do Hyprland:
--     Flea quente ................. ~700 ms
--     Flea frio, sem pre-aquecer .. 1077 ms
--     Flea frio, pre-aquecido ....   856 ms
--     Nautilus frio, sem residente   810 ms
--
-- Ou seja: o pre-aquecimento comprava 221 ms, UMA vez por boot, lendo 70 MB a
-- cada login. E o grosso do custo -- ~700 ms -- nao e paginacao, e a
-- inicializacao do proprio Flea, que cache nenhum resolve. Nao readicionar
-- sem medir de novo pelo openwindow.
--
-- (O Flea tambem deixa 2 processos orfaos por abertura, um `qs` e um
-- `flea --backend`, e NAO os reaproveita: a 3a abertura custa o mesmo que a
-- 1a. Reportado ao projeto.)

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
