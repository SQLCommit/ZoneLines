# Changelog

## v1.1.0

### New Features
- **Pulsating Glow** - Dots pulse with configurable speed (0.5-20), intensity, and min/max brightness
- **Label Gap** - Adjustable spacing between zone name and distance text
- **Distance Position** - Place distance text above, below, left, or right of zone name
- **Separator** - Automatic dash separator when distance is positioned left or right
- **Bottom-Anchored Text** - Labels grow upward from dots instead of downward, avoiding collision at close range

### Bug Fixes
- **Sky blinking fix** - D3D transform matrices saved as Lua table copies instead of raw cdata pointers; prevents corrupted view/projection restore that caused sky flickering in open areas
- **Render state skip** - Skip entire D3D state save/restore cycle when no zone lines are within render distance, eliminating unnecessary device state manipulation

### Performance
- Settings and color rebuilds gated behind dirty flag (no longer recalculated every frame)
- Removed redundant per-label pcall in text rendering (outer pcall is sufficient)
- Removed redundant GetTransform + copy_matrix in text pass (reuses view matrix from draw_d3d)
- Extracted duplicate settings-to-renderer sync into shared `sync_renderer()` function

### Settings Changes
- Updated defaults: dot glow 0.8, dot color cyan-green, label offset 0.5, text min scale 0.7, text max scale 2.3, label spacing 8

## v1.0.0

Initial release.

### Features
- 846 pre-extracted zone lines across 198 zones from FFXI DAT files
- D3D8 depth-tested 3D markers (hide behind walls/terrain via beginscene pass 2)
- Terrain-following dots using pre-computed navmesh ground heights
- Auto-flatten for flat zones; gradient-based cliff flattening for slopes
- Destination labels and distance overlay with screen-space ortho text rendering
- Per-zone-line overrides: height, trim, flatten, hide, pole height
- Distance color coding (green/yellow/red proximity bands)
- Full ImGui settings window with tooltips on all controls
- Per-character settings saved via Ashita settings system

### Commands
- `/zl` -- toggle settings window
- `/zl show` / `hide` -- toggle marker visibility
- `/zl list` -- print zone lines for current zone
- `/zl resetui` -- reset window position/size
- `/zl help` -- show command help
