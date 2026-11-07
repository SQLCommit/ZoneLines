# Changelog

[Back to ZoneLines](README.md)

## v1.4.1

### Fixed

- Effects flickered or vanished when the game's background resolution matched the window size.
- Markers from the city drawn inside the Mog House.

## v1.4.0

### Added

- Ship-time signs at every dock and in the Port Jeuno arches, with times over the schedule NPCs.
- Markers for Windurst teleporters, Delkfutt's Tower telepads, Outpost Warp NPCs, and Aht Urhgan warp NPCs.
- One build for Phoenix, HorizonXI, and retail-style servers; ship times, conquest regions, and NPCs follow the server.
- Conquest crests beside destination names.
- Exits, portals, docks, and ship times on the native `/map`.
- Line effects: pulse, wave, reveal, and rising motes.
- Fixed labels that stand in the world like signs.
- Portal and NPC marker switches that keep the labels.
- Fonts load from the `fonts/` folder with no install.

### Improved

- Settings regrouped into five tabs, with per-tab Reset buttons.
- Per-marker adjustments for portals, NPCs, and signs.
- Less work and garbage per frame.

### Fixed

- Wide zone lines stay visible at their ends.
- `/zl hide` and `/zl show` no longer revert.
- Built-in line adjustments can be cleared; your own changes are kept.
- Pulse brightness settings now apply.
- Font changes apply at once after a reset.
- Errors go to `logs\zonelines.log` with one line in chat; a failing part retries, then stops.
- Old unused settings are removed.

## v1.3.1

### Fixed

- Fixed crashes after repeated addon reloads by releasing the native font manager on unload.
- Font cleanup now runs even if saving settings fails.
- A drawing or settings-window error stops only the affected part and reports it in chat. Reload the addon to retry.

## v1.3.0

### Added

- GdiFonts destination labels with adjustable font, bold text, and outline thickness.
- Optional Grammara, Mystic Gate, and Oswald fonts. Install them in Windows and restart FFXI to use them.

### Improved

- Cached terrain-following marker positions instead of rebuilding them every frame.
- Separated font controls from label sizing settings.
- Reset to Defaults preserves individual zone-line adjustments; reload refreshes addon modules.
- Removed the obsolete text-outline toggle from saved settings. Other old keys stayed until the next release.

### Fixed

- Zone fog tinting labels, white fringes around text, and leaked graphics state affecting foliage and other transparent surfaces.
- A texture-reference leak during drawing.
- Invalid override values and unhandled settings-save errors.
- Mixed-case commands such as `/ZL`.

## v1.2.3

### Improved

- Reorganized settings into six categories with clearer sections, tooltips, and a persistent footer.
- Reused marker-position tables to reduce allocations and removed a redundant render call.
- Added data-loading warnings, clearer font errors, and throttled repeated error messages.
- Reset to Defaults immediately updates markers without changing the defaults table.
- Revised defaults: render distance 90, dot glow 1.0, outlines on, pulse speed 4, intensity 2.0, minimum brightness 0.69, and distance fade on over the outer 60%.

### Fixed

- Smoothed distance fade and measured visibility from the nearest boundary edge, preventing markers from disappearing too early. Thanks to West Ronfaure.
- Missing-coordinate errors, inconsistent chat formatting, and mismatched fallback settings.
- Added a trim, flattening, and height adjustment for zone line 846737530.

## v1.2.2

### Fixed

- Labels from the previous zone lingering during rapid zoning. Markers now pause during transitions and refresh on zone entry.

## v1.2.1

### Fixed

- Text outlines ignoring world occlusion.

### Changed

- Simplified distance-fade clamping.

## v1.2.0

### Added

- Optional black text outlines for readability.
- Configurable distance fade near the render-distance limit, suggested by West Ronfaure.

## v1.1.0

### Added

- Pulsating dots with adjustable speed, intensity, and brightness range.
- Label spacing and distance placement above, below, left, or right of the destination name.
- Separators for side-by-side labels and upward-growing text to avoid overlapping markers.

### Improved

- Cached settings and colors, reused camera data, and skipped rendering setup when no markers are visible.
- Updated marker color, glow, and label sizing defaults.

### Fixed

- Sky flickering caused by restoring stale camera transforms.

## v1.0.0

Initial release.
