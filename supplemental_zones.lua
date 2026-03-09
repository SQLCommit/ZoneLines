--[[
    ZoneLines v1.1.0 - Supplemental Zone Transition Data
    Hand-curated entries for zone transitions that use trigger areas or NPC
    interactions instead of standard zone line boundaries in DAT files.

    These transitions don't have RID entries in FFXI's DAT files because they
    are script-driven (trigger areas, guard checks, NPC conversations) rather
    than automatic walk-through zone boundaries.

    Positions and extents sourced from LSB server scripts (Zone.lua trigger
    area definitions and moghouse.lua exit positions).

    Format matches zones_data.lua for seamless merging in data.lua.
    Optional field: shape='circle' forces circle rendering (for portals/pads).
]]--

-- Synthetic rect_ids for supplemental entries (900000+ range, won't collide with DAT IDs)
-- Format: 900000 + zone_id * 100 + entry_index
return {
    [231] = { -- Northern San d'Oria → Chateau d'Oraguille
        -- Bridge entrance at trigger area start (z=110).
        -- Center offset by +half_sz so front edge (dots) lands on z=110.
        -- y raised from -2 to -1: the synth ground formula (y+sy/2-2) gives
        -- ground at the box bottom for shallow boxes. -1 lowers dots 1 yalm.
        { x=0.000, y=-1.000, z=111.500, sx=14.000, sy=2.000, sz=3.000, ry=0.0000,
          rect_id=923101, to_zone=233, to_zone_name='', ident='trig' },
    },
    [239] = { -- Windurst Walls → Heaven's Tower
        -- Tower entrance trigger area: cuboid (-2,-17,140) to (2,-16,142)
        { x=0.000, y=-16.500, z=141.000, sx=4.000, sy=1.000, sz=2.000, ry=0.0000,
          rect_id=923901, to_zone=242, to_zone_name='', ident='trig', shape='circle' },
    },
    [242] = { -- Heaven's Tower → Windurst Walls
        -- Exit portal trigger area: cuboid (-1,-1,-35) to (1,1,-33)
        -- Event 41 → setPos(0, -17, 135, 60, 239)
        { x=0.000, y=0.000, z=-34.000, sx=2.000, sy=2.000, sz=2.000, ry=0.0000,
          rect_id=924201, to_zone=239, to_zone_name='', ident='trig', shape='circle' },
    },
}
