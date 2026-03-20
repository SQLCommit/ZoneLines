# ZoneLines v1.2.3 - Zone Line Visualizer for Ashita v4.3

Zone line visualizer for Ashita v4.3. Draws 3D ground markers at zone transition boundaries so you can see where zone lines are before walking into them. All zone line data is pre-extracted from FFXI DAT files.

## Features

- **846 Zone Lines** across 198 zones, pre-extracted from FFXI DAT files
- **3D Depth-Tested Markers** - Dots render in world space and hide behind walls/terrain
- **Terrain-Following** - Dots follow pre-computed navmesh ground heights with cliff flattening
- **Pulsating Glow** - Configurable dot pulse with adjustable speed, intensity, and min/max brightness
- **Distance Color Coding** - Optional green/yellow/red coloring based on proximity
- **Destination Labels** - Zone name and distance displayed above each zone line
- **Flexible Label Layout** - Distance position (top/bottom/left/right), configurable spacing and separators
- **Distance Fade** - Optional dot size fade near the render distance edge
- **Text Outline** - Optional black outline on labels for improved readability
- **Circle Markers** - Portals and trigger-area transitions shown as ground circles with vertical poles
- **Per-Zone-Line Overrides** - Adjust height, trim, flatten, hide, and pole height per entry
- **Supplemental Triggers** - Hand-curated entries for script-driven transitions (palace gates, tower portals)
- **Settings Window** - Sidebar + detail panel UI with 6 categories and tooltips on every control
- **Per-Character Settings** - Saved automatically via Ashita's settings system

## Requirements

- Ashita v4.3.0.2
	- This release has only been tested with Ashita v4.3.0.2

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
2. **supplemental_zones.lua** - Hand-curated trigger-area transitions
3. **terrain_heights.lua** - Pre-computed ground heights from navmesh data

### Data Extraction

The addon's data files are pre-generated offline — no extraction happens at runtime.

**Zone Lines (zones_data.lua)** - Extracted from FFXI's DAT files using a Python script. Each zone has a DAT containing RID (Room ID) entries with a `z` prefix identifier (e.g., `z020`, `z05a`). The script scans the VTABLE/FTABLE to locate each zone's DAT, parses the RID entries to find zone line bounding boxes (position, size, rotation), and decodes the 4-character FourCC identifier using base-36 encoding to determine the destination zone ID. Mog House entrances also exist in the DATs using `zm` prefix identifiers (e.g., `zmrw`, `zms0`) with `to_zone=0`. The result is 846 oriented bounding boxes across 198 zones with positions, dimensions, rotation angles, and destination zone IDs.

**Terrain Heights (terrain_heights.lua)** - Extracted from LandSandBoat's Detour navmesh `.nav` files. A Python script reads the navmesh polygon data for each zone, then for each zone line bounding box, samples ground heights at evenly-spaced dot positions along the line. It uses point-in-polygon ray casting to find which navmesh triangle each point falls on, then barycentric interpolation to compute the exact ground height. Edge-first sampling with cross-fill fallback handles cases where dot positions fall slightly outside the navmesh. Post-processing applies slope outlier clamping and edge extension to smooth out gaps.

**Supplemental Triggers (supplemental_zones.lua)** - Hand-curated from LandSandBoat server scripts. A few zone transitions use trigger areas instead of standard walk-through boundaries, so they don't have RID entries in the DAT files. Currently covers the Northern San d'Oria bridge entrance to Chateau d'Oraguille and the Heaven's Tower portal in Windurst Walls. Positions and extents are sourced from LSB's `Zone.lua` trigger area definitions.

### Rendering

Zone lines are rendered as 3D primitives using D3D8 `DrawPrimitiveUP` in the `d3d_beginscene` event (pass 2, before game world geometry). The game's depth buffer naturally occludes markers behind walls and terrain. Text labels use a screen-space ortho projection with the font atlas texture for pixel-perfect rendering while preserving depth testing.

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
| **ImGui** | `GetFont()`, `GetFontSize()`, `GetFontBaked()` | Font atlas texture for D3D text rendering |

## Settings

Settings are saved per-character via Ashita's settings library. The settings window uses a sidebar + detail panel layout with 6 categories. A visibility toggle and zone info header are always visible at the top.

### Markers
- **Dot Size / Spacing / Hover Height / Cliff Flatten** - Shape controls for dot geometry
- **Glow Pulse** - Enable pulsating dot halos with speed, min/max brightness, and intensity
- **Edge Glow** - Dot edge softness (0 = sharp, 1 = solid fill)

### Labels
- **Labels / Distance** - Show/hide destination names and distance in yalms
- **Text Outline** - Black outline on label text for readability
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

## File Structure

```
zonelines/
  zonelines.lua          -- Main addon: metadata, events, commands, settings
  renderer.lua           -- D3D8 rendering: depth-tested dots, circles, text labels
  ui.lua                 -- ImGui settings window with per-zone-line overrides
  data.lua               -- Data loading: zone lines, supplemental triggers, terrain heights
  zones_data.lua         -- 846 pre-extracted zone line bounding boxes (auto-generated)
  supplemental_zones.lua -- Hand-curated trigger-area transitions
  terrain_heights.lua    -- Pre-computed ground heights from navmesh data
```

## Technical Notes

### Performance
- **Pre-computed data**: All zone line positions and terrain heights are loaded once at startup, not computed per-frame
- **Zone caching**: Zone line data is cached per zone with a dirty flag, only recomputed on zone change or settings mutation
- **Pre-allocated D3D matrices**: Identity and ortho matrices are allocated once at module level, not per-frame
- **Reusable label table**: Label collection uses a counter pattern with table reuse to avoid per-frame allocations
- **Pooled curtain positions**: Dot position tables for curtain zone lines are pooled and reused each frame, eliminating per-frame table allocations from the heaviest rendering path
- **Settings gating**: Color rebuilds and setting syncs only run when settings change, not every frame
- **D3D state skip**: Render state save/restore cycle is skipped entirely when no zone lines are within render distance (pre-check padded by box size to avoid false culls)
- **Edge-based culling**: Per-zone-line visibility uses nearest box edge distance, matching the fade math so wide zone lines fade correctly at the boundary
- **Transform safety**: D3D transform matrices are saved as Lua table copies to prevent cdata staleness when restoring
- **Throttled error logging**: Error messages are rate-limited (30s per error type) to avoid chat spam while ensuring issues are always reported

## Version History

See [CHANGELOG.md](CHANGELOG.md) for full version history.

## Thanks

- **Ashita Team** - atom0s, thorny, and the [Ashita Discord](https://discord.gg/Ashita) community
- **West Ronfaure** - Distance/Smoothstep fade suggestion

## License

MIT License - See LICENSE file
