# ZoneLines v1.3.1 - Zone Line Visualizer for Ashita v4.3

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

1. Download `ZoneLines-vX.Y.Z.zip` from the [Releases](https://github.com/SQLCommit/ZoneLines/releases/latest) page
2. Extract it into your Ashita folder - it adds `addons\zonelines\`
3. Load with `/addon load zonelines`

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

### Rendering

Zone lines are rendered as 3D primitives using D3D8 `DrawPrimitiveUP` in the `d3d_beginscene` event (pass 2, before game world geometry). The game's depth buffer naturally occludes markers behind walls and terrain. Text labels are rendered to per-string textures via GdiFonts (GDI+) and drawn as depth-tested billboard quads in the same pass, so they render cleanly at any zoom while remaining occluded by world geometry.

Marker drawing keys off the *second* `BeginScene` of each frame; if the client ever issued a single `BeginScene` for a frame, markers simply wouldn't draw that frame (it fails safe rather than misdrawing).

For passage-type zone lines, hovering dots are drawn along the wider dimension of the oriented bounding box, interpolating pre-computed terrain heights. Circle markers are used for portals and area triggers, with a vertical pole connecting the ground circle to the label above.

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

## Version History

See [CHANGELOG.md](CHANGELOG.md) for full version history.

## Thanks

- **Ashita Team** - atom0s, thorny, and the [Ashita Discord](https://discord.gg/Ashita) community
- **thorny** - GdiFonts library, used for clean label text rendering
- **West Ronfaure** - Distance fade suggestion, smoothstep fade curve and pre-check culling fix

## License

MIT License - See LICENSE file
