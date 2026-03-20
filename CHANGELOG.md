# Changelog

## v1.2.3

### UI Rewrite
- **Sidebar + Detail Panel** - Settings window replaced with category-based layout matching MobHUD pattern. Left sidebar with 6 categories (Markers, Labels, Colors, Fade, Zone Lines, Overrides), right detail panel with focused settings per category
- **Consolidated widget buffers** - All ImGui buffers packed into single `B` table to avoid LuaJIT upvalue pressure
- **Color theme** - Orange sub-headers, green sidebar selection, cyan info text, grey dimmed text
- **Tooltips on all controls** - Every interactive widget including Reset to Defaults has a hover tooltip
- **Persistent footer** - `/zl help` and right-aligned Reset to Defaults button always visible below the panel

### Performance
- **Curtain position pooling** - Dot position tables for curtain zone lines are now pooled and reused each frame instead of allocated fresh. Eliminates ~15,000-31,000 short-lived table allocations per second in zones with many visible zone lines (cities, hubs)
- **Removed dead `renderer.render()` call** - Font atlas init was already handled in `d3d_present`; removed redundant code path

### Improvements
- **Throttled error logging** - All error messages use a 30-second cooldown per error type to avoid chat spam during persistent failures
- **User-friendly font atlas errors** - Every font atlas failure path now prints a clear message explaining the issue and what to do (e.g. "Ashita v4.3.0.2+ is required")
- **Data load warnings** - Missing supplemental zone data or terrain height files now print informational messages instead of failing silently
- **Reset to Defaults** - Deep copies defaults to prevent mutation of the defaults table; syncs renderer fields immediately so all visual changes take effect without toggling each setting
- **Nil guards on position data** - Zone line table position formatting guards against nil coordinates

### Fixes
- **Distance fade smoothing** *(suggestion by West Ronfaure)* - Replaced linear fade ramp with smoothstep curve so dots ease into shrinking and ease into disappearing instead of snapping
- **Distance fade culling** - Pre-check was killing zone lines before the fade math could run on them. Per-zone-line culling now uses edge distance (nearest box edge) instead of center distance, padded conservatively to avoid false early-outs
- **Chat output consistency** - Fixed renderer error logging to use `:append()` pattern instead of `..` concatenation
- **Settings fallback defaults** - Aligned all three default value locations (default_settings, sync_renderer fallbacks, renderer module declarations) to prevent drift

## v1.2.2

### Bug Fixes
- **Stale Zone Labels During Fast Zoning** - Fixed labels from previous zones persisting when zoning quickly (e.g. with packetflow through multiple zones). Added zone transition detection via 0x00B/0x00A packets that suppresses all marker rendering during zone transitions and immediately invalidates the data cache on zone exit.

## v1.2.1

### Bug Fixes
- **Text Outline** - Fixed outline rendering to preserve depth testing

### Improvements
- Replaced manual fade clamping with `math.clamp`

## v1.2.0

### New Features
- **Text Outline** - Optional black outline on zone name and distance labels for improved readability (default off)
- **Distance Fade** *(suggestion by West Ronfaure)* - Optional dot size fade near the render distance edge with configurable fade zone

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
