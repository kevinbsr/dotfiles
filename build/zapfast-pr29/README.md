# zapfast with the idle-repaint fix

`zapfast` 0.13.1 and 0.14.0 keep one CPU core near 100% while idle, which cost
about 10 W on battery here (measured 2026-09-16: ~26 W with it running, ~15 W
with it stopped; iGPU 34% vs 8%).

Upstream tracks this as crmne/zapfast#20. The fix is PR #29 by @MrVoicer, still
unmerged, and it predates the v0.14.0 tag (19 commits behind), so it does not
apply to the release. `pr29-adapted.diff` is that PR rebased onto v0.14.0:
v0.14.0 had meanwhile grown its own visibility check with a different
signature, `frame(ui, path, rect)`, so the merged version keeps it and adds the
PR's `animate` flag, `frame(ui, path, rect, animate)`.

Measured after installing this package: 0.1% of a core idle, iGPU 4%.

Behaviour change from the PR: animated stickers and GIFs play only while
hovered with the window focused; other animated stickers show a still icon.

Rebase work tree: `~/.local/src/zapfast-git` (v0.14.0 + two cherry-picked
commits). Build: `cd ~/.local/src/zapfast-aur && makepkg -sf`.

Drop this once upstream ships the fix: install the plain `zapfast-bin` again.
