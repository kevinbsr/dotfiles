-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- Listar monitores e modos: hyprctl monitors all
--
-- ATENCAO: no Quattro o hyprctl keyword NAO aceita mais sintaxe legada
-- ("keyword can't work with non-legacy parsers"). Para testar ao vivo use:
--   hyprctl eval 'hl.monitor({ output = "DP-1", mode = "3440x1440@180", ... })'
--
-- O nwg-displays regrava este arquivo e apaga todo o resto -- nao usar.

-- Layout fisico (2026-09-02), da esquerda para a direita:
--
--   [LG vertical]  [    ASUS ultrawide    ]  [notebook]
--     900x1600            3440x1440             1536x864
--       0x0                  900x80              4340x368
--
-- Os tres ficam CENTRALIZADOS na vertical (dai os offsets y): assim o mouse
-- atravessa pelo meio das telas em vez de escapar pelos cantos.
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1.25

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Catch-all: painel interno e qualquer tela nova.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Notebook (LG Display, 143 DPI). Escala 1.25 -> 115 DPI efetivo.
hl.monitor({ output = "eDP-1", mode = "1920x1080@165", position = "4340x368", scale = 1.25 })

-- ASUS VG34WQML5A ultrawide, tela principal. 3440x1440.
-- Escala 1: 109 DPI fisico, proximo dos 115 efetivos do notebook, entao o
-- tamanho aparente casa entre as duas. Em 1.25 caia para 87 DPI e tudo ficava
-- grande demais.
--
-- 180Hz e o TETO REAL deste painel -- nao e conservadorismo. O EDID nao tem
-- nenhum modo de 240Hz. Conferido em 2026-09-02 com edid-decode:
--   Display Range Limits ...: 48-180 Hz V, max dotclock 1100 MHz
--   FreeSync VSDB (AMD) .....: 48-180 Hz
--   DisplayID, timing maior .: 3440x1440 @ 179.98 Hz, 1017.25 MHz
-- e `hyprctl monitors all` so lista 59.97 / 119.99 / 179.98 para 3440x1440.
--
-- Historico, para nao repetir: em 2026-09-02 gravei @240 aqui a partir de um
-- conselho errado, SEM antes olhar a lista de modos. O Hyprland tentou forcar
-- um modo inexistente, o driver montou um timing acima do dotclock do painel e
-- a maquina travou inteira (monitor sem imagem, reset no botao) -- e como ja
-- estava gravado, o boot seguinte caiu direto no mesmo modo:
--   [nvidia-drm] Flip event timeout on head 0
--   Failed to apply atomic modeset.  Error code: -22
-- Regra: validar em runtime com `hyprctl eval` primeiro, gravar depois.
--
-- Manter em 8 bpc. O enlace e DisplayPort 1.4 (25,9 Gbps uteis) e em 180Hz:
--   1017.25 MHz x 24 bits = 24,4 Gbps -> cabe, 6% de margem
--   1017.25 MHz x 30 bits = 30,5 Gbps -> NAO cabe (isto e o flicker em 10-bit)
hl.monitor({ output = "DP-1", mode = "3440x1440@180", position = "900x80", scale = 1 })

-- LG E2011 antigo, agora na VERTICAL. transform = 1 e 90 graus anti-horario
-- (se um dia girar para o outro lado, o valor e 3). Rotacionado, 1600x900
-- vira 900x1600 logico.
hl.monitor({ output = "HDMI-A-1", mode = "1600x900@60", position = "0x0", scale = 1, transform = 1 })

-- Workspaces por monitor. O ASUS e o principal, entao fica com 1-5.
for _, ws in ipairs({ 1, 2, 3, 4, 5 }) do
  hl.workspace_rule({ workspace = tostring(ws), monitor = "DP-1", default = ws == 1 })
end

for _, ws in ipairs({ 6, 7, 8, 9, 10 }) do
  hl.workspace_rule({ workspace = tostring(ws), monitor = "eDP-1", default = ws == 6 })
end

for _, ws in ipairs({ 11, 12, 13, 14, 15 }) do
  hl.workspace_rule({ workspace = tostring(ws), monitor = "HDMI-A-1", default = ws == 11 })
end
