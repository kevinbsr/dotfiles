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
-- Pre-aquecimento do Flea, que virou o gerenciador de arquivos padrao em
-- 2026-09-08 (via `flea --default`). Substitui o servico do Nautilus, que
-- ficava residente desde o login e agora seria peso morto.
--
-- POR QUE ISTO EXISTE, com numeros medidos: quente, Flea e Nautilus abrem
-- igual (~48 ms). Frio, o Flea leva 2238 ms contra 713 ms do Nautilus -- e o
-- Nautilus so ganhava porque o servico dele mantinha as bibliotecas em cache
-- desde o login. Nao era o Flea ser lento, era ser frio.
--
-- Das 201 libs que o Flea mapeia, 189 ja estao quentes por causa do shell do
-- Omarchy (tambem Quickshell). O que sobra e a pilha grafica da NVIDIA, que o
-- carregador Vulkan enumera mesmo sem usar: libnvidia-glcore (39,8 MB),
-- libvulkan_radeon (18,3 MB), libnvidia-glvkspirv (9,9 MB) e libGLX_nvidia.
--
-- Por isso aqui so LEMOS os arquivos para o cache de pagina, em vez de deixar
-- processo rodando: cada `flea --gui` deixa um `flea --backend` orfao que nao
-- e recolhido ao fechar a janela (bug do 0.1.3), entao um daemon residente
-- somaria lixo em vez de resolver.
o.exec_on_start('bash -c "sleep 8 && cat /usr/lib/libnvidia-glcore.so.* /usr/lib/libvulkan_radeon.so /usr/lib/libnvidia-glvkspirv.so.* /usr/lib/libGLX_nvidia.so.* /usr/bin/flea > /dev/null 2>&1"')

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
