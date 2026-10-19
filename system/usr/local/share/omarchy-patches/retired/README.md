# Retired patches

Not applied: the reapply hook only globs `*.patch` in the parent directory.
Kept for reference after the move from omarchy-dev r1832 to the omarchy 4.0.5
package (stable channel) on 2026-10-19.

- `qt612-qualify-color-stable` -- qualified `Color` as `Commons.Color` for
  Qt 6.12 on r1832. Omarchy 4.0.5 ships the same qualification.
- `indicators-one-orientation` -- built only the bar orientation in use. 4.0.5
  loads the horizontal or vertical tree through a Loader, which does the same.
- `bar-click-targets` -- collapsed the per-registration PluginBarApi resync.
  4.0.5 coalesces it upstream (`schedulePluginBarApiSync`).
- `menu-multiselect-r1832` -- the r1832 version. The 4.0.5 version is
  `../menu-multiselect-stable.patch`; one hunk changed because 4.0.5 dropped
  `disabled: false` from the dmenu rows.
