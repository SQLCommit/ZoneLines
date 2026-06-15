# ZoneLines v1.3.0 - Zone Line Visualizer for Ashita v4.3

Zone line visualizer for Ashita v4.3. Draws 3D ground markers at zone transition boundaries so you can see where zone lines are before walking into them. All zone line data is pre-extracted from FFXI DAT files.

## Features

- **846 Zone Lines** across 198 zones, pre-extracted from FFXI DAT files
- **3D Depth-Tested Markers** - Dots render in world space and hide behind walls/terrain
- **Terrain-Following** - Dots follow pre-computed navmesh ground heights with cliff flattening
- **Pulsating Glow** - Configurable dot pulse with adjustable speed, intensity, and min/max brightness
- **Distance Color Coding** - Optional green/yellow/red coloring based on proximity
- **Clean Destination Labels** - Zone name and distance rendered above each zone line via GdiFonts (sharp at any distance, still occluded behind walls)
- **Custom Label Fonts** - Choose from a set of common Windows fonts, or add your own to `fonts/`; with a Bold toggle and adjustable outline thickness; optional fonts (Grammara, Mystic Gate, Oswald) bundled in `fonts/`
- **Flexible Label Layout** - Distance position (top/bottom/left/right), configurable spacing and separators
- **Distance Fade** - Optional dot size fade near the render distance edge
- **Circle Markers** - Portals and trigger-area transitions shown as ground circles with vertical poles
- **Per-Zone-Line Overrides** - Adjust height, trim, flatten, hide, and pole height per entry
- **Supplemental Triggers** - Hand-added entries for script-driven transitions (palace gates, tower portals)
- **Settings Window** - Sidebar + detail panel UI with 6 categories and tooltips on every control
- **Per-Character Settings** - Saved automatically via Ashita's settings system

## Requirements

- Ashita v4.3.0.2 or newer
	- Developed and tested on Ashita v4.3.1.2
- Labels are rendered via the bundled GdiFonts library (Windows GDI+); custom fonts must be installed in Windows (see **Fonts** below)

## Installation

1. Copy the `zonelines` folder to your Ashita `addons` directory
2. Load with `/addon load zonelines`

## Commands

| Command | Description |
|---------|-------------|
| `/zl` | Toggle the settings window |
| `/zl show` / `hide` | Show or hide zone line markers |
| `/zl list` | Print zone lines for current zone to chat |
| `/zl resetui` | Reset window size and position |
| `/zl help` | Show command help |

## How It Works

### Data Sources

1. **zones_data.lua** - 846 zone line bounding boxes extracted from FFXI DAT files
2. **supplemental_zones.lua** - Hand-added trigger-area transitions
3. **terrain_heights.lua** - Pre-computed ground heights from navmesh data

### Data Extraction

The addon's data files are pre-generated offline — no extraction happens at runtime.

**Zone Lines (zones_data.lua)** - Extracted from FFXI's DAT files using a Python script. Each zone has a DAT containing RID (Room ID) entries with a `z` prefix identifier (e.g., `z020`, `z05a`). The script scans the VTABLE/FTABLE to locate each zone's DAT, parses the RID entries to find zone line bounding boxes (position, size, rotation), and decodes the 4-character FourCC identifier using base-36 encoding to determine the destination zone ID. Mog House entrances also exist in the DATs using `zm` prefix identifiers (e.g., `zmrw`, `zms0`) with `to_zone=0`. The result is 846 oriented bounding boxes across 198 zones with positions, dimensions, rotation angles, and destination zone IDs.

**Terrain Heights (terrain_heights.lua)** - Extracted from LandSandBoat's Detour navmesh `.nav` files. A Python script reads the navmesh polygon data for each zone, then for each zone line bounding box, samples ground heights at evenly-spaced dot positions along the line. It uses point-in-polygon ray casting to find which navmesh triangle each point falls on, then barycentric interpolation to compute the exact ground height. Edge-first sampling with cross-fill fallback handles cases where dot positions fall slightly outside the navmesh. Post-processing applies slope outlier clamping and edge extension to smooth out gaps.

**Supplemental Triggers (supplemental_zones.lua)** - Hand-added from LandSandBoat server scripts. A few zone transitions use trigger areas instead of standard walk-through boundaries, so they don't have RID entries in the DAT files. Currently covers the Northern San d'Oria bridge entrance to Chateau d'Oraguille and the Heaven's Tower portal in Windurst Walls. Positions and extents are sourced from LSB's `Zone.lua` trigger area definitions.

### Rendering

Zone lines are rendered as 3D primitives using D3D8 `DrawPrimitiveUP` in the `d3d_beginscene` event (pass 2, before game world geometry). The game's depth buffer naturally occludes markers behind walls and terrain. Text labels are rendered to per-string textures via GdiFonts (GDI+) and drawn as depth-tested billboard quads in the same pass, so they render cleanly at any zoom while remaining occluded by world geometry.

Marker drawing keys off the *second* `BeginScene` of each frame; if the client ever issued a single `BeginScene` for a frame, markers simply wouldn't draw that frame (it fails safe rather than misdrawing).

For passage-type zone lines, hovering dots are drawn along the wider dimension of the oriented bounding box, interpolating pre-computed terrain heights. Circle markers are used for portals and area triggers, with a vertical pole connecting the ground circle to the label above.

### Ashita SDK API

| Interface | Methods Used | Purpose |
|-----------|-------------|---------|
| **IEntity** | `GetLocalPositionX/Y/Z(idx)` | Player position for distance calculation and camera reference |
| **IParty** | `GetMemberZone(0)` | Zone detection, character login gate |
| **IResourceManager** | `GetString('zones.names', id)` | Destination zone name resolution |
| **GetPlayerEntity()** | `.ServerId` | Character identity for per-character settings |
| **AshitaCore** | `GetInstallPath()`, `GetMemoryManager()`, `GetResourceManager()` | File paths, access to memory interfaces |
| **D3D8 Device** | `DrawPrimitiveUP`, `SetRenderState`, `SetTransform` | World-space 3D marker rendering with depth testing |
| **ImGui** | window / widgets | Settings window UI |
| **GdiFonts** (by thorny) | `create_object`, `get_texture` | Clean label text rendered to D3D textures |

## Settings

Settings are saved per-character via Ashita's settings library. The settings window uses a sidebar + detail panel layout with 6 categories. A visibility toggle and zone info header are always visible at the top.

### Markers
- **Dot Size / Spacing / Hover Height / Cliff Flatten** - Shape controls for dot geometry
- **Glow Pulse** - Enable pulsating dot halos with speed, min/max brightness, and intensity
- **Edge Glow** - Dot edge softness (0 = sharp, 1 = solid fill)

### Labels
- **Labels / Distance** - Show/hide destination names and distance in yalms
- **Font / Bold** - Label font family (common Windows fonts + any you add to `fonts/`) with a bold toggle
- **Outline** - Black outline thickness around label text for readability
- **Distance Position** - Place distance text top/bottom/left/right of zone name
- **Label Gap** - Spacing between zone name and distance text
- **Font Size / Label Height / Min Zoom / Max Zoom** - Text sizing controls

### Colors
- **Dot Color** - Base color for all dots
- **Distance Colors** - Toggle proximity-based coloring with far/mid/close pickers

### Fade
- **Render Distance** - Max distance to render zone line markers
- **Distance Fade** - Shrink dots near the render distance edge with configurable fade zone

### Zone Lines
- Table of all zone lines in the current zone with destination, position, size, and source

### Overrides
- **Per-zone-line adjustments** - Hide, height, trim, cliff flatten, and pole height per entry

## Fonts

Labels are rendered with **GdiFonts**, which uses the Windows GDI+ font system, so it can only use fonts **installed in Windows**. The **Labels → Font** picker lists a set of common Windows fonts (Arial, Calibri, Segoe UI, Consolas, Verdana, Tahoma, Trebuchet MS, Times New Roman), plus any font you place in the addon's `fonts/` folder that is also installed. It does not enumerate every font on your system.

To add your own font (or use a bundled one):

1. Put the `.ttf` / `.otf` in the addon's `fonts/` folder (so the addon can read its family name).
2. Install it in Windows (right-click → **Install**, or drop it in your user Fonts folder).
3. **Restart the game** - GDI+ only sees installed fonts at process start; `/addon reload` is not enough.
4. Pick it in **Labels → Font**.

The addon bundles a few optional fonts in `fonts/` (Grammara, Mystic Gate, Oswald) but **does not install them for you** - it never writes to your system. See `fonts/INSTALL FONTS - READ ME FIRST.txt`. A font shows up only once it's both in `fonts/` and installed, so you'll never see one that renders as blank labels.

## File Structure

```
zonelines/
  zonelines.lua          -- Main addon: metadata, events, commands, settings
  renderer.lua           -- D3D8 rendering: depth-tested dots, circles, text labels
  ui.lua                 -- ImGui settings window with per-zone-line overrides
  data.lua               -- Data loading: zone lines, supplemental triggers, terrain heights
  zones_data.lua         -- 846 pre-extracted zone line bounding boxes (auto-generated)
  supplemental_zones.lua -- Hand-added trigger-area transitions
  terrain_heights.lua    -- Pre-computed ground heights from navmesh data
  gdifonts/              -- GdiFonts library (clean label text via GDI+; by thorny)
  fonts/                 -- Optional bundled label fonts + install instructions
```

## Technical Notes

### Performance
- **Pre-computed data**: All zone line positions and terrain heights are loaded once at startup, not computed per-frame
- **Zone caching**: Zone line data is cached per zone with a dirty flag, only recomputed on zone change or settings mutation
- **Pre-allocated D3D matrices**: Identity and ortho matrices are allocated once at module level, not per-frame
- **Reusable label table**: Label collection uses a counter pattern with table reuse to avoid per-frame allocations
- **Cached curtain positions**: Per-zone-line dot positions (terrain interpolation, smoothing, gradient flattening) are cached and reused across frames, recomputing only when settings change or the player crosses a zone line - eliminating per-frame recomputation and table allocations from the heaviest rendering path
- **Settings gating**: Color rebuilds and setting syncs only run when settings change, not every frame
- **D3D state skip**: Render state save/restore cycle is skipped entirely when no zone lines are within render distance (pre-check padded by box size to avoid false culls)
- **Edge-based culling**: Per-zone-line visibility uses nearest box edge distance, matching the fade math so wide zone lines fade correctly at the boundary
- **Transform safety**: D3D transform matrices are saved as Lua table copies to prevent cdata staleness when restoring
- **Throttled error logging**: Error messages are rate-limited (30s per error type) to avoid chat spam while ensuring issues are always reported

## Version History

See [CHANGELOG.md](CHANGELOG.md) for full version history.

## Thanks

- **Ashita Team** - atom0s, thorny, and the [Ashita Discord](https://discord.gg/Ashita) community
- **thorny** - GdiFonts library, used for clean label text rendering
- **West Ronfaure** - Distance fade suggestion, smoothstep fade curve and pre-check culling fix

## License

MIT License - See LICENSE file
