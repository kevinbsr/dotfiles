-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- Listar monitores e modos: hyprctl monitors all
--
-- ATENCAO: no Quattro o hyprctl keyword NAO aceita mais sintaxe legada
-- ("keyword can't work with non-legacy parsers"). Para testar ao vivo use:
--   hyprctl eval 'hl.monitor({ output = "DP-1", mode = "3440x1440@240", ... })'
--
-- Omitir um campo em hl.monitor() NAO reseta esse campo -- o valor anterior
-- continua valendo. Notavelmente `vrr = 0` tambem nao apaga a regra: o wrapper
-- parece tratar 0 como "nao definido". Para zerar de verdade: hyprctl reload.
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

-- ============================================================================
-- ASUS TUF VG34WQML5A ultrawide, tela principal. 3440x1440, escala 1.
-- Escala 1: 109 DPI fisico, proximo dos 115 efetivos do notebook, entao o
-- tamanho aparente casa entre as duas. Em 1.25 caia para 87 DPI, grande demais.
--
-- O MODO DEPENDE DO "Over Clocking" NO MENU DO MONITOR.
--
-- O painel e de 250Hz, mas so anuncia isso com o OC ligado -- o OC reescreve o
-- EDID. Comparando os Display Range Limits:
--
--   OC desligado : 48-180 Hz, dotclock max 1100 MHz  -> nada passa de 180
--   OC ligado    : 48-250 Hz, dotclock max 1340 MHz  -> surgem 240 e 250 Hz
--
-- Com OC ligado o enlace so fecha via DSC. A conta, no DisplayPort 1.4 (25,9
-- Gbps uteis):
--
--   240 Hz  8-bit = 1279,58 MHz x 24 = 30,7 Gbps  -> so cabe comprimido
--   180 Hz  8-bit = 1017,25 MHz x 24 = 24,4 Gbps  -> cabe sem DSC
--   180 Hz 10-bit = 1017,25 MHz x 30 = 30,5 Gbps  -> NAO cabe sem DSC
--
-- Como 240 Hz funciona, o DSC esta ativo, e ai a banda deixa de ser o limite
-- (o DSC comprime para ~8-12 bpp): 10 bpc passa a caber junto. Por isso
-- 240 Hz anda com bitdepth 10, e o fallback de 180 Hz anda com 8.
--
-- POR QUE A GUARDA ABAIXO EXISTE: em 2026-09-02 este arquivo pedia 240 Hz com
-- o OC desligado, ou seja, um modo que o EDID nao anunciava. O driver montou
-- um timing acima do dotclock do painel e a maquina travou inteira, exigindo
-- reset no botao -- e como estava gravado, o boot seguinte caiu no mesmo modo:
--   [nvidia-drm] Flip event timeout on head 0
--   Failed to apply atomic modeset.  Error code: -22
-- Resetar o monitor pelo painel dele desliga o OC. A guarda le a taxa maxima
-- que o EDID anuncia AGORA e escolhe o modo compativel, para que isso nunca
-- mais possa acontecer sozinho.
-- ============================================================================

-- Le a taxa vertical maxima do descritor Display Range Limits (tag 0xFD) do
-- EDID. Devolve nil se nao conseguir ler -- e ai caimos no modo conservador.
local function dp1_max_hz()
  local f = io.open("/sys/class/drm/card0-DP-1/edid", "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  if not d or #d < 128 then return nil end
  -- Os quatro descritores do bloco 0 comecam em 54/72/90/108 (base 0),
  -- que em Lua (base 1) sao 55/73/91/109.
  for _, off in ipairs({ 55, 73, 91, 109 }) do
    if d:sub(off, off + 4) == "\0\0\0\253\0" then
      return d:byte(off + 6)
    end
  end
  return nil
end

local dp1_mode, dp1_depth = "3440x1440@180", 8
local max_hz = dp1_max_hz()
if max_hz and max_hz >= 240 then
  dp1_mode, dp1_depth = "3440x1440@240", 10
end

hl.monitor({
  output = "DP-1",
  mode = dp1_mode,
  position = "900x80",
  scale = 1,
  bitdepth = dp1_depth,
})

-- LG E2011 antigo, agora na VERTICAL. transform = 1 e 90 graus anti-horario
-- (se um dia girar para o outro lado, o valor e 3). Rotacionado, 1600x900
-- vira 900x1600 logico.
hl.monitor({ output = "HDMI-A-1", mode = "1600x900@60", position = "0x0", scale = 1, transform = 1 })

-- VRR fica DESLIGADO de proposito. O painel e VA e "respira": muda de brilho
-- quando a taxa cai com a tela parada. Testado em 2026-09-03 -- com vrr = 1 a
-- imagem pisca no desktop, e com vrr = 2 (so tela cheia) tambem nao agradou.

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
