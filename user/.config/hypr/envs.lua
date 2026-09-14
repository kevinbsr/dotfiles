-- Variáveis de ambiente pessoais, carregadas depois dos defaults do Omarchy.
-- Substitui o antigo envs.conf, que o Quattro não lê mais.

-- OCR (omarchy capture text) reconhecendo inglês e português.
hl.env("OMARCHY_OCR_LANGS", "eng+por")

-- O bloco de GPU abaixo é gerado por ~/.local/bin/omarchy-gpu-env-sync.
-- Rodar de novo após trocar o modo gráfico na BIOS ou via supergfxctl.


-- Desfaz o default do Omarchy que joga a sessão inteira na dGPU.
-- /usr/share/omarchy/default/hypr/nvidia.lua seta LIBVA_DRIVER_NAME=nvidia e
-- __GLX_VENDOR_LIBRARY_NAME=nvidia sempre que detecta uma NVIDIA. Isso é correto
-- num desktop só-NVIDIA, mas ERRADO num híbrido: aqui o compositor roda na AMD
-- (o painel eDP-1 é dela) e essas duas variáveis arrastam todo cliente GL e todo
-- decode de vídeo para a dGPU. Medido em 2026-08-29: o quickshell carregava
-- libGLX_nvidia, nvidia_drv_video e libvdpau_nvidia por causa delas, mapeava
-- /dev/nvidia0 e segurava a placa acordada -- ~10 W a mais, 100% do tempo.
-- Este arquivo é carregado DEPOIS dos defaults, então estas linhas vencem.
--
-- EGL fica de fora de propósito: o Aquamarine precisa do EGL da NVIDIA para
-- dirigir HDMI-A-1 e DP-1, que ficam NA dGPU. Restringir o EGL da sessão
-- arriscaria o boot gráfico e o monitor externo.
--
-- Apps que realmente precisam da dGPU continuam indo por `nvidia-offload`, que
-- sobrescreve todas estas variáveis explicitamente.
hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
hl.env("VDPAU_DRIVER", "radeonsi")
-- VK_DRIVER_FILES REMOVIDO em 2026-09-01. Restringir o ICD do Vulkan à AMD
-- tornava a RTX 3060 invisivel para qualquer app Vulkan -- e jogos da Steam
-- sao Vulkan, entao passaram a rodar na iGPU sem aviso nenhum.
-- Nao valia o custo: o nvidia.lua do Omarchy nao seta VK_DRIVER_FILES (so
-- LIBVA_DRIVER_NAME e __GLX_VENDOR_LIBRARY_NAME), entao isto nao desfazia bug
-- nenhum, e a medicao de 2026-08-31 mostrou que NENHUMA das quatro variaveis
-- era necessaria para a dGPU chegar a D3cold -- ela dormiu 100% do tempo com
-- todas restauradas para nvidia.
-- Vulkan voltando a enxergar as duas placas e "acorda no uso", que e o
-- comportamento desejado: jogo pesado usa a dGPU, o resto fica na integrada.

-- >>> omarchy-gpu-env-sync -- auto-generated, do not edit by hand >>>
-- GPU mode detected: hybrid
-- Hybrid. By default AQ_DRM_DEVICES is NOT set: Aquamarine autodetects both
-- GPUs, renders on the AMD (the internal panel hangs off it) and drives the
-- NVIDIA connectors -- HDMI-A-1 and DP-1 on this G15 -- as a secondary backend.
--
-- Do NOT reintroduce it with /dev/dri/by-path/... names. Aquamarine splits
-- AQ_DRM_DEVICES on ":" and by-path names contain colons; on 2026-08-09 that
-- produced "Failed to canonicalize path" -> "CBackend::create() failed!" and a
-- login loop. /dev/dri/cardN is colon-free but not stable across boots. The
-- colon-free, stable names come from /etc/udev/rules.d/61-dri-stable-names.rules.
--
-- ---- Optional NVIDIA-primary render mode --------------------------------
-- Chosen with `omarchy-gpu-switch nvidia` (applies at next login) and stored
-- in ~/.config/omarchy/gpu-render. Hyprland then composites on the RTX 3060,
-- so the external monitors are scanned out by the card that renders them and
-- every frame stops crossing GPUs; eDP-1 becomes the one that crosses.
--
-- It only engages when ALL of these hold, else the session starts hybrid:
--   * /dev/dri/gpu-nvidia and /dev/dri/gpu-amd exist (the udev rule above);
--   * an external monitor is connected to the NVIDIA card -- undocked there is
--     nothing for it to drive, and rendering there would keep ~9 W awake for
--     nothing. The preference is kept; the next docked login uses it;
--   * the previous attempt was not left unconfirmed (dead-man switch below).
--
-- DEAD-MAN SWITCH. This machine has no visible TTY, so a failed login must fix
-- itself. Before trying, a "pending" marker is written;
-- omarchy-gpu-render-confirm (autostart) removes it once the session is up. If
-- Hyprland dies before that, the marker survives to the next login, and this
-- block switches the preference back to hybrid instead of trying again.
-- A config reload re-runs this file inside the SAME Hyprland process, so both
-- markers carry the PID of the Hyprland that wrote them ($PPID of an io.popen
-- shell is Hyprland itself). A marker owned by this very process is a reload,
-- never a failed login. The first version keyed this on the instance signature,
-- which the confirmer only records ~10 s in -- and hyprmoncfgd applies the
-- monitor profile, reloading the config, ~6 s in. On 2026-09-14 that reload
-- found this login's own pending marker, took it for a failed login, and
-- flipped the preference to hybrid under a session that was running fine.
--
-- Everything shells out through io.popen and reads OUTPUT only: inside
-- Hyprland os.execute and pclose return nil ("No child processes") whatever the
-- exit status, because Hyprland reaps its own children. A `test -e` read from
-- an exit code would always say "missing", silently.
do
  local home = os.getenv("HOME") or ""
  local dev = os.getenv("OMARCHY_GPU_RENDER_DEV_DIR") or "/dev/dri"
  local sysfs = os.getenv("OMARCHY_GPU_RENDER_SYSFS") or "/sys/class/drm"
  local state_dir = home .. "/.local/state/omarchy"
  local state_file = home .. "/.config/omarchy/gpu-render"
  local pending = state_dir .. "/gpu-render-pending"
  local confirmed = state_dir .. "/gpu-render-confirmed"
  local reverted = state_dir .. "/gpu-render-reverted"
  local active = state_dir .. "/gpu-render-active"

  local function sh(cmd)
    local p = io.popen(cmd)
    if not p then return "" end
    local out = p:read("*a") or ""
    p:close()
    return out
  end
  local function exists(path)
    return sh("[ -e '" .. path .. "' ] && echo yes") == "yes\n"
  end
  local function read_line(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
  end
  local function write(path, text)
    sh("mkdir -p '" .. state_dir .. "' '" .. home .. "/.config/omarchy'")
    local f = io.open(path, "w")
    if f then f:write(text) f:close() end
  end
  local function nvidia_has_external()
    local out = sh("n=$(basename \"$(readlink -f '" .. dev .. "/gpu-nvidia')\"); cat '" .. sysfs .. "'/\"$n\"-*/status 2>/dev/null")
    for line in out:gmatch("[^\n]+") do
      if line == "connected" then return true end
    end
    return false
  end

  local now = os.date("%Y-%m-%d %H:%M:%S")
  local want = ((read_line(state_file) or "hybrid"):match("^%s*(%S+)")) or "hybrid"
  local hypr_pid = os.getenv("OMARCHY_GPU_RENDER_TEST_PID") or (sh("echo $PPID"):match("%d+") or "")
  local reloading = hypr_pid ~= "" and read_line(confirmed) == hypr_pid     -- confirmed session
  local same_session = hypr_pid ~= "" and read_line(pending) == hypr_pid    -- not yet confirmed

  -- `active` is a report and is always rewritten; only the pending marker
  -- depends on whether this is a fresh login or a reload.
  -- BIOS "Enable Hybrid Graphics/Advanced Optimus" OFF: the AMD iGPU is gone
  -- from the bus and the MUX hands the panel to the NVIDIA card, so every
  -- output hangs off it and nothing crosses GPUs. Aquamarine must be pinned to
  -- that card: with no amdgpu to take over the boot framebuffer, simpledrm
  -- stays registered and shows up as a second "GPU" with a phantom Unknown-1
  -- monitor. Autodetection picked it up as a secondary renderer, EGL on it
  -- failed (EGL_NOT_INITIALIZED) and Hyprland aborted in renderTexture on
  -- 2026-09-14, relaunching in safe mode. The render-mode preference and the
  -- dead-man switch do not apply: there is only one GPU to render on.
  if exists(dev .. "/gpu-nvidia") and not exists(dev .. "/gpu-amd")
     and sh("ls /sys/bus/pci/drivers/amdgpu 2>/dev/null | grep -c '^0000:'"):match("^0") then
    write(active, "discrete (BIOS hybrid graphics off: NVIDIA drives every output)\n")
    hl.env("AQ_DRM_DEVICES", dev .. "/gpu-nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("VDPAU_DRIVER", "nvidia")
    hl.env("NVD_BACKEND", "direct")
  elseif want ~= "nvidia" then
    write(active, "hybrid (preference)\n")
  elseif not reloading and not same_session and exists(pending) then
    write(state_file, "hybrid\n")
    os.remove(pending)
    write(reverted, now .. "\n")
    write(active, "hybrid (reverted: previous nvidia login never confirmed)\n")
  elseif not (exists(dev .. "/gpu-nvidia") and exists(dev .. "/gpu-amd")) then
    write(active, "hybrid (nvidia preferred, but /dev/dri/gpu-* missing: udev rule not installed?)\n")
  elseif not nvidia_has_external() then
    write(active, "hybrid (nvidia preferred, but no external monitor on the NVIDIA card)\n")
  else
    if not reloading and not same_session then write(pending, hypr_pid .. "\n") end
    write(active, "nvidia\n")
    hl.env("AQ_DRM_DEVICES", dev .. "/gpu-nvidia:" .. dev .. "/gpu-amd")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("VDPAU_DRIVER", "nvidia")
    hl.env("NVD_BACKEND", "direct")
  end
end
-- <<< omarchy-gpu-env-sync <<<
