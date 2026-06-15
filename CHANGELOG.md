# Changelog

## v1.3.0

### Clean Label Text (GdiFonts)
- **Rewrote label rendering** - Zone-line labels now render via GdiFonts (GDI+) to per-string textures drawn as depth-tested billboards, replacing the borrowed ImGui font atlas. Text is sharp at any distance with no bleed or softening, and is still occluded correctly behind walls and terrain
- **Fixed fog tint on labels** - Zone fog no longer tints label text or outlines (`D3DRS_FOGENABLE` is now saved and restored around the marker pass)
- **Fixed white edge fringe** - Raised the alpha-test reference so the transparent label border no longer bleeds a faint white edge

### Custom Font System
- **Font picker** - New Font selector in Labels offers a set of common Windows fonts plus any TTF/OTF you place in `fonts/` (and have installed), with a **Bold** toggle alongside it
- **Outline thickness slider** - Label outline is now an adjustable slider instead of an on/off toggle
- **Bundled optional fonts** - Ships Grammara, Mystic Gate, and Oswald in `fonts/` with an install readme. The addon never installs fonts itself (read-only by design); the picker only lists fonts you have actually installed, so there are no blank labels

### Performance
- **Curtain position cache** - Per-zone-line dot positions (terrain interpolation, 3-pass smoothing, gradient flattening, and table allocations) are now cached and reused across frames, recomputing only when settings change or the player crosses a zone line. In busy areas with many visible zone lines this removes nearly all of the per-frame work from the heaviest rendering path

### Bug Fixes
- **Fixed COM texture reference leak** - The D3D8 state save called `GetTexture` without releasing the returned (AddRef'd) reference, slowly accumulating VRAM across zone changes over a long session. The reference is now released each frame
- **Fixed alpha-test state leak** - `ALPHAREF` / `ALPHAFUNC` set during the label pass are now saved and restored, so they no longer leak into the game's world rendering (foliage, fence, and hair alpha cutouts)
- **Hardened override reads** - Per-zone-line override keys (`trim` / `hide` / `height`) are now type-guarded against LuaJIT `T{}` sugar-method collisions, matching the existing `flatten` / `pole_height` guards
- **Case-insensitive commands** - `/ZL` and other mixed-case spellings now work

### Internals
- **Single source of truth for defaults** - Collapsed several divergent copies of the default values into one `default_settings` table that every sync path and UI buffer reads from
- **Reliable `/addon reload`** - The entry script clears the `package.loaded` cache for its submodules so reloads pick up edits to them
- **Removed dead "Text Outline" setting** - Replaced by the outline-thickness slider; the orphaned key is stripped from saved settings on load
- **Reset to Defaults preserves overrides** - Resetting no longer wipes your per-zone-line tweaks
- **Safer saves** - All `settings.save()` calls are wrapped in `pcall`

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

### Defaults Updated
- Render distance: 300 -> 90
- Dot glow (edge): 0.8 -> 1.0
- Text outline: off -> on
- Glow pulse speed: 2 -> 4
- Glow intensity: 0.5 -> 2.0
- Pulse min brightness: 0.4 -> 0.69
- Distance fade: off -> on
- Distance fade zone: 30% -> 60%
- Added override for zone line 846737530 (trim, flatten, height)

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
