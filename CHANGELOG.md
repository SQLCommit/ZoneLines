# Changelog

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
