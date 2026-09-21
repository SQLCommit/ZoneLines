-- Supplemental trigger/NPC transitions missing from DAT boundaries.
-- Coordinates originate from LandSandBoat trigger-area and Mog House definitions.
-- Use the zone-data entry format; shape=circle selects a portal marker.

-- Synthetic rect_ids for supplemental entries (900000+ range, won't collide with DAT IDs)
-- Format: 900000 + zone_id * 100 + entry_index
return {
    [231] = { -- Northern San d'Oria → Chateau d'Oraguille
        -- Place the front edge at z=110 by offsetting the center by half_sz.
        -- y=-1 compensates for the shallow-box ground-height formula.
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
