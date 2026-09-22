# aquamarine with the #383 exit-crash fix and the secondary-EGL release fix

The official package plus two patches.

## egl-terminate-secondary-display.patch (pkgrel 1.2, 2026-09-22)

Since #373 (in 0.15.1), `~CDRMRenderer` only calls `eglTerminate` when the
driver exposes `EGL_KHR_display_reference`; neither NVIDIA nor Mesa does here
(`eglinfo | grep -c display_reference` → 0). The secondary renderer on the
NVIDIA card is created when an output on it connects and destroyed when the
last one goes (`drm: Deinitializing secondary renderer on /dev/dri/card0`),
but its EGL display stays initialized, so after undocking the dGPU sits in D0
at ~10 W (`/proc/driver/nvidia/gpus/*/power`: `Video Memory: Active`) until the
compositor restarts. The patch terminates the display for secondary-backend
renderers only, the one case where nothing else in the process shares that
device's display. Check after an undock: the dGPU's `power/runtime_status`
should reach `suspended` within seconds.

## issue383-exit-null-connector.patch

hyprwm/aquamarine#383 is still open and is
not in 0.15.1: `~CDRMBackend` disconnects each connector and resets its slot in
the same loop, while `disconnect()` walks `connectors` through
`flushAsyncCommitEvents()`, so the already-reset slots are dereferenced as
null. Hyprland segfaults on every exit with more than one output.

Built from the Arch packaging repo with `pkgrel=1.2`:

    cd ~/.local/src/aquamarine-383/repo && makepkg -sf
    pkexec pacman -U aquamarine-0.15.1-1.2-x86_64.pkg.tar.zst

`hyprwayland-scanner` is a make dependency and was installed with `--asdeps`.

The previous rebuild also carried a patch for #386 (the approach of the
unmerged PR #395). That one is gone: 0.15.1 ships the upstream fix, PR #410.

`/etc/pacman.d/hooks/96-aquamarine-383-watch.hook` shouts when a repo upgrade
replaces this build. Drop all of it once #383 is fixed upstream and the
secondary display is released again (a release that terminates it, or one that
no longer relies on EGL_KHR_display_reference).
