# aquamarine with the #383 exit-crash fix

The official package plus one patch. hyprwm/aquamarine#383 is still open and is
not in 0.15.1: `~CDRMBackend` disconnects each connector and resets its slot in
the same loop, while `disconnect()` walks `connectors` through
`flushAsyncCommitEvents()`, so the already-reset slots are dereferenced as
null. Hyprland segfaults on every exit with more than one output.

Built from the Arch packaging repo with `pkgrel=1.1`:

    cd ~/.local/src/aquamarine-383/repo && makepkg -sf
    pkexec pacman -U aquamarine-0.15.1-1.1-x86_64.pkg.tar.zst

`hyprwayland-scanner` is a make dependency and was installed with `--asdeps`.

The previous rebuild also carried a patch for #386 (the approach of the
unmerged PR #395). That one is gone: 0.15.1 ships the upstream fix, PR #410.

`/etc/pacman.d/hooks/96-aquamarine-383-watch.hook` shouts when a repo upgrade
replaces this build. Drop all of it once #383 is fixed upstream.
