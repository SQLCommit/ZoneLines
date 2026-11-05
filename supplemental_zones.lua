-- Extra zone transitions.

-- Synthetic ids, 900000+ range.
return {
    [231] = { -- San d'Oria to Chateau
        { x=0.000, y=-1.000, z=111.500, sx=14.000, sy=2.000, sz=3.000, ry=0.0000,
          rect_id=923101, to_zone=233, to_zone_name='', ident='trig' },
    },
    [239] = { -- Walls to Heaven's Tower
        { x=0.000, y=-16.500, z=141.000, sx=4.000, sy=1.000, sz=2.000, ry=0.0000,
          rect_id=923901, to_zone=242, to_zone_name='', ident='trig', shape='circle' },
    },
    [242] = { -- Tower to Walls
        { x=0.000, y=0.000, z=-34.000, sx=2.000, sy=2.000, sz=2.000, ry=0.0000,
          rect_id=924201, to_zone=239, to_zone_name='', ident='trig', shape='circle' },
    },
    -- Pad model centres.
    [184] = { -- Lower Delkfutt telepads
        -- 3F G-6 to Middle
        { x=406.658, y=-33.500, z=86.671, sx=6.000, sy=1.000, sz=6.000, ry=0.0000,
          rect_id=918451, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='Middle Delkfutt\'s Tower - 4F' },
        -- 3F F-10 to Middle "1"
        { x=393.342, y=-33.500, z=-46.671, sx=7.000, sy=1.000, sz=6.000, ry=0.0000,
          rect_id=918452, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='Middle Delkfutt\'s Tower - 4F' },
    },
    [157] = { -- Middle Delkfutt telepads
        -- 4F G-6 to Lower
        { x=-33.342, y=-49.500, z=86.671, sx=6.000, sy=1.000, sz=6.000, ry=0.0000,
          rect_id=915751, to_zone=184, to_zone_name='', ident='trig', shape='circle',
          floor_label='Lower Delkfutt\'s Tower - 3F' },
        -- 4F G-6 to Lower "1"
        { x=-46.658, y=-49.500, z=-46.671, sx=6.000, sy=1.000, sz=7.000, ry=0.0000,
          rect_id=915752, to_zone=184, to_zone_name='', ident='trig', shape='circle',
          floor_label='Lower Delkfutt\'s Tower - 3F' },
        -- 4F J-6 to Lower "2"
        { x=106.671, y=-49.500, z=13.342, sx=6.000, sy=1.000, sz=6.000, ry=0.0000,
          rect_id=915753, to_zone=184, to_zone_name='', ident='trig', shape='circle',
          floor_label='Lower Delkfutt\'s Tower - 3F' },
        -- 6F F-10 to 7F "G"
        { x=-46.658, y=-81.500, z=-46.671, sx=6.000, sy=1.000, sz=5.000, ry=0.0000,
          rect_id=915754, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='7th Floor (G)' },
        -- 7F F-10 to 6F "G"
        { x=-486.658, y=-97.500, z=-46.671, sx=6.000, sy=1.000, sz=5.000, ry=0.0000,
          rect_id=915755, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='6th Floor (G)' },
        -- 6F J-10 to 7F "H"
        { x=86.671, y=-81.500, z=-46.658, sx=6.000, sy=1.000, sz=5.000, ry=0.0000,
          rect_id=915756, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='7th Floor (H)' },
        -- 7F J-10 to 6F "H"
        { x=-353.329, y=-97.500, z=-46.658, sx=5.000, sy=1.000, sz=5.000, ry=0.0000,
          rect_id=915757, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='6th Floor (H)' },
        -- 6F J-6 to 7F "I"
        { x=86.658, y=-81.500, z=86.671, sx=5.000, sy=1.000, sz=6.000, ry=0.0000,
          rect_id=915758, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='7th Floor (I)' },
        -- 7F J-6 to 6F "I"
        { x=-353.342, y=-97.500, z=86.671, sx=5.000, sy=1.000, sz=4.000, ry=0.0000,
          rect_id=915759, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='6th Floor (I)' },
        -- 7F H-6 to 6F "J"
        { x=-413.342, y=-97.500, z=106.671, sx=4.000, sy=1.000, sz=4.000, ry=0.0000,
          rect_id=915760, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='6th Floor (J)' },
        -- 9F F-6 to Upper
        { x=-486.671, y=-129.500, z=86.658, sx=5.000, sy=1.000, sz=4.000, ry=0.0000,
          rect_id=915761, to_zone=158, to_zone_name='', ident='trig', shape='circle',
          floor_label='Upper Delkfutt\'s Tower - 10F' },
    },
    [158] = { -- Upper Delkfutt telepads
        -- 10F F-6 to Middle
        { x=-366.671, y=-145.500, z=86.658, sx=4.000, sy=1.000, sz=6.000, ry=0.0000,
          rect_id=915851, to_zone=157, to_zone_name='', ident='trig', shape='circle',
          floor_label='Middle Delkfutt\'s Tower - 9F' },
        -- 12F F-10 to Stellar Fulcrum
        { x=-366.658, y=-177.500, z=-46.671, sx=4.000, sy=1.000, sz=6.000, ry=0.0000,
          rect_id=915852, to_zone=179, to_zone_name='', ident='trig', shape='circle',
          floor_label='Stellar Fulcrum' },
    },
}
