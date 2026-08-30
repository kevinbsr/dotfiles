-- Variáveis de ambiente pessoais, carregadas depois dos defaults do Omarchy.
-- Substitui o antigo envs.conf, que o Quattro não lê mais.

-- OCR (omarchy capture text) reconhecendo inglês e português.
hl.env("OMARCHY_OCR_LANGS", "eng+por")

-- O bloco de GPU abaixo é gerado por ~/.local/bin/omarchy-gpu-env-sync.
-- Rodar de novo após trocar o modo gráfico na BIOS ou via supergfxctl.

-- >>> omarchy-gpu-env-sync -- auto-generated, do not edit by hand >>>
-- GPU mode detected: hybrid
-- Hybrid: AQ_DRM_DEVICES is deliberately NOT set. Aquamarine autodetects both
-- GPUs, renders on the AMD (the internal panel hangs off it) and still sees
-- the NVIDIA connectors, which is where the external HDMI and DisplayPort
-- ports are wired on this G15.
--
-- Do NOT reintroduce it with /dev/dri/by-path/... names. Aquamarine splits
-- AQ_DRM_DEVICES on ":" and by-path names contain colons, so
-- "/dev/dri/by-path/pci-0000:06:00.0-card" is shredded into three nonexistent
-- paths. The log says it plainly:
--   drm: Failed to canonicalize path /dev/dri/by-path/pci-0000
--   drm: Found no gpus to use, cannot continue
-- and Hyprland then dies with "CBackend::create() failed!", looping SDDM with
-- a TTY as the only way back in. That is what happened on 2026-08-09, with
-- both the two-card and the iGPU-only list -- the colons broke both.
--
-- If pinning is ever genuinely needed, use colon-free node names
-- (/dev/dri/card0, /dev/dri/card1) and be aware their numbering is not stable
-- across boots, which is the reason by-path was reached for in the first place.
--
-- No global LIBVA/GLX override either: forcing those to nvidia moves the whole
-- compositor onto the dGPU, which is what actually burned power here. Per-app
-- offload goes through nvidia-offload.
-- <<< omarchy-gpu-env-sync <<<

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
hl.env("VK_DRIVER_FILES", "/usr/share/vulkan/icd.d/radeon_icd.json")
