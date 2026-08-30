-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all
--
-- FORMATO PADRÃO DO OMARCHY -- não trocar por blocos explícitos por monitor.
-- É a linha `local omarchy_monitor_scale` que mantém painel e sistema de acordo:
--   * omarchy-hyprland-monitor-scaling (painel Display) persiste a escala nela;
--   * omarchy-hyprland-monitor-clamshell lê dela a escala do monitor interno e
--     a reimpõe a cada 2s enquanto houver monitor externo.
-- Com blocos explícitos por monitor o painel deixa de persistir e o clamshell
-- desfaz qualquer mudança no ciclo seguinte.
--
-- O nwg-displays regrava este arquivo em blocos explícitos multi-linha e apaga
-- todo o resto. Usá-lo quebra os dois mecanismos acima -- prefira editar aqui.

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1.25

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Catch-all: vale para o painel interno (e para qualquer tela nova).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Override só do externo: fica à esquerda, em 0x0, na escala nativa.
-- Vem depois do catch-all de propósito -- a regra mais específica ganha.
hl.monitor({ output = "HDMI-A-1", mode = "1600x900@60.0", position = "0x0", scale = 1 })

-- Workspaces fixos por monitor (era workspaces.conf, gerado pelo nwg-displays).
for _, ws in ipairs({ 1, 2, 3, 4, 5 }) do
  hl.workspace_rule({ workspace = tostring(ws), monitor = "eDP-1", default = ws == 1 })
end

for _, ws in ipairs({ 6, 7, 8, 9, 10 }) do
  hl.workspace_rule({ workspace = tostring(ws), monitor = "HDMI-A-1", default = ws == 6 })
end
