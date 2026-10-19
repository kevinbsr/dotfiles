# Inactive patches

Written against omarchy-dev and kept for a return to that branch. The reapply
hook only globs `*.patch` in the parent directory, so nothing here is applied.

Moved here on 2026-10-15, after the switch to the stable branch (r1832):

- `qt612-qualify-color` — qualifies `Color` for Qt 6.12, whose new global
  `Color` shadows the shell singleton. Stable runs Qt 6.11; not needed.
- `tray-trusted-fork`, `bar-click-targets` — both work around the PluginBarApi
  facade, which the stable bar does not have. kevin.tray gets the full host
  bar natively on stable.
- `bar-center-hover`, `menu-multiselect` — the dev versions. Stable versions
  with the same fixes live in the parent directory as `*-stable.patch`.

On 2026-10-19, with the move to the omarchy 4.0.5 package, `tray-trusted-fork`
went back to the parent directory (4.0.5 has the PluginBarApi facade again) and
`bar-click-targets` moved to `../retired/` (fixed upstream). The other dev
patches stay here.
