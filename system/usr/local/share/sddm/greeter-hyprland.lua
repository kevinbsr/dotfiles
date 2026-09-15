-- Config for the SDDM greeter's Hyprland: the stock greeter config plus no
-- Xwayland. Used by /usr/local/bin/sddm-greeter-compositor.
--
-- The greeter runs no X11 client, yet its Xwayland started anyway and aborted
-- with a core dump at every login, when SDDM kills the greeter compositor
-- ("wayland compositor finished 9 QProcess::CrashExit"; 10 Xwayland dumps owned
-- by the sddm user, 2026-09-14/15).
dofile("/usr/share/sddm/hyprland.lua")

hl.config({
  xwayland = {
    enabled = false,
  },
})
