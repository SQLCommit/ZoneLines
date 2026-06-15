--[[
    ZoneLines v1.3.0 - Zone Line Rendering via D3D8

    Zone line bounding boxes have a thin dimension (depth you walk through)
    and a wide dimension (spanning the passage). The dotted line is drawn
    along the wider dimension, hovering above the terrain surface.
]]--

require 'common';

local ffi   = require 'ffi';
local d3d8  = require 'd3d8';
local imgui = require 'imgui';
local chat  = require 'chat';

local renderer = {};


-------------------------------------------------------------------------------
-- D3D8 FFI: vertex structs and render constants
-------------------------------------------------------------------------------

ffi.cdef[[
    typedef struct {
        float x, y, z;
        unsigned int color;
    } zl_d3d_vertex_t;

    typedef struct {
        float x, y, z;
        unsigned int color;
        float tu, tv;
    } zl_d3d_textured_vertex_t;
]];

-- Primitive types
local D3DPT_TRIANGLELIST = 4;

-- Vertex formats
local D3DFVF_XYZ_DIFFUSE      = 0x042;  -- D3DFVF_XYZ | D3DFVF_DIFFUSE
local D3DFVF_XYZ_DIFFUSE_TEX1 = 0x142;  -- D3DFVF_XYZ | D3DFVF_DIFFUSE | D3DFVF_TEX1
local VERTEX_SIZE              = 16;     -- sizeof(zl_d3d_vertex_t)
local TEXTURED_VERTEX_SIZE     = 24;     -- sizeof(zl_d3d_textured_vertex_t)

-- Render state keys
local D3DRS_ZENABLE          = 7;
local D3DRS_ZWRITEENABLE     = 14;   -- CRITICAL: 14 not 15 (15 = ALPHATESTENABLE)
local D3DRS_ALPHATESTENABLE  = 15;
local D3DRS_SRCBLEND         = 19;
local D3DRS_DESTBLEND        = 20;
local D3DRS_CULLMODE         = 22;
local D3DRS_ZFUNC            = 23;
local D3DRS_ALPHAREF         = 24;
local D3DRS_ALPHAFUNC        = 25;
local D3DRS_ALPHABLENDENABLE = 27;
local D3DRS_ZBIAS            = 47;
local D3DRS_LIGHTING         = 137;
local D3DRS_FOGENABLE        = 28;

-- Depth / alpha comparison
local D3DCMP_LESSEQUAL    = 4;
local D3DCMP_GREATEREQUAL = 7;

-- Texture stage states
local D3DTSS_COLOROP   = 1;
local D3DTSS_COLORARG1 = 2;
local D3DTSS_COLORARG2 = 3;
local D3DTSS_ALPHAOP   = 4;
local D3DTSS_ALPHAARG1 = 5;
local D3DTSS_ADDRESSU  = 13;
local D3DTSS_ADDRESSV  = 14;
local D3DTSS_MAGFILTER = 16;
local D3DTSS_MINFILTER = 17;

-- Texture stage ops / filter values
local D3DTOP_DISABLE     = 1;
local D3DTEXF_LINEAR     = 2;
local D3DTADDRESS_CLAMP  = 3;

-- Transform types
local D3DTS_WORLD = 256;

-- Reusable vertex buffers
local DOT_CIRCLE_SEGS = 12;
local d3d_verts    = ffi.new('zl_d3d_vertex_t[?]', DOT_CIRCLE_SEGS * 3);  -- 1 gradient circle
local CIRCLE_SEGS  = 16;
local circle_verts = ffi.new('zl_d3d_vertex_t[?]', CIRCLE_SEGS * 3);  -- triangle fan

-- Pole vertex buffer (thin quad = 2 triangles = 6 verts)
local pole_verts = ffi.new('zl_d3d_vertex_t[?]', 6);

-- Text vertex buffer (max 48 chars * 6 verts = 288 verts)
local MAX_TEXT_CHARS = 48;
local text_verts = ffi.new('zl_d3d_textured_vertex_t[?]', MAX_TEXT_CHARS * 6);


-- Pre-allocated D3D matrices (reused each frame to avoid GC pressure)
local identity_matrix = ffi.new('D3DMATRIX');
identity_matrix._11 = 1; identity_matrix._22 = 1; identity_matrix._33 = 1; identity_matrix._44 = 1;
local ortho_matrix = ffi.new('D3DMATRIX');
local restore_world = ffi.new('D3DMATRIX');
local restore_view  = ffi.new('D3DMATRIX');
local restore_proj  = ffi.new('D3DMATRIX');

-- Write a Lua table (from copy_matrix) back into a D3DMATRIX cdata
local function table_to_matrix(tbl, mat)
    mat._11 = tbl._11; mat._12 = tbl._12; mat._13 = tbl._13; mat._14 = tbl._14;
    mat._21 = tbl._21; mat._22 = tbl._22; mat._23 = tbl._23; mat._24 = tbl._24;
    mat._31 = tbl._31; mat._32 = tbl._32; mat._33 = tbl._33; mat._34 = tbl._34;
    mat._41 = tbl._41; mat._42 = tbl._42; mat._43 = tbl._43; mat._44 = tbl._44;
    return mat;
end



-- Copy D3DMATRIX cdata fields into a plain Lua table (cdata refs go stale between frames)
local function copy_matrix(m)
    return {
        _11=m._11, _12=m._12, _13=m._13, _14=m._14,
        _21=m._21, _22=m._22, _23=m._23, _24=m._24,
        _31=m._31, _32=m._32, _33=m._33, _34=m._34,
        _41=m._41, _42=m._42, _43=m._43, _44=m._44,
    };
end

-- Expose copy_matrix for zonelines.lua to use when caching
renderer.copy_matrix = copy_matrix;

-- D3D state
renderer.d3d_pass          = 0;
renderer.cached_view       = nil;
renderer.cached_proj       = nil;
renderer.cached_vp_w       = 0;
renderer.cached_vp_h       = 0;
renderer.hide_behind_walls = true;
-- The text/glow/label fields below are placeholders — sync_renderer() in
-- zonelines.lua overwrites them at load from default_settings (single source).
renderer.d3d_text_scale    = 1.0;   -- base font size multiplier
renderer.d3d_label_offset  = 0.6;  -- world yalms above dots for label
renderer.d3d_text_min_scale = 0.5; -- min font scale (far away)
renderer.d3d_text_max_scale = 3.0; -- max font scale (close up)
renderer.d3d_show_labels   = true;
renderer.d3d_show_distance = true;
renderer.d3d_dist_position = 'bottom';  -- 'bottom', 'top', 'left', 'right'
renderer.d3d_label_spacing = 2;         -- extra pixel gap between name and distance
renderer.dot_glow_enabled   = true;     -- pulsating dots
renderer.dot_glow_speed     = 2.0;      -- pulse speed (radians/sec)
renderer.dot_glow_intensity = 0.5;      -- glow brightness multiplier
renderer.dot_glow_min       = 0.4;      -- pulse minimum (0-1)
renderer.dot_glow_max       = 1.0;      -- pulse maximum (0-1)


-------------------------------------------------------------------------------
-- D3D Text: world position -> screen, drawn in an ortho pass for depth-tested labels.
-------------------------------------------------------------------------------

-- Project world → screen + NDC Z (for depth testing in ortho pass)
local function project_with_z(view, proj, vp_w, vp_h, wx, wy, wz)
    local vx = wx * view._11 + wy * view._21 + wz * view._31 + view._41;
    local vy = wx * view._12 + wy * view._22 + wz * view._32 + view._42;
    local vz = wx * view._13 + wy * view._23 + wz * view._33 + view._43;
    local vw = wx * view._14 + wy * view._24 + wz * view._34 + view._44;

    local cx = vx * proj._11 + vy * proj._21 + vz * proj._31 + vw * proj._41;
    local cy = vx * proj._12 + vy * proj._22 + vz * proj._32 + vw * proj._42;
    local cz = vx * proj._13 + vy * proj._23 + vz * proj._33 + vw * proj._43;
    local cw = vx * proj._14 + vy * proj._24 + vz * proj._34 + vw * proj._44;

    if (cw <= 0.001) then return 0, 0, false, 0; end

    local ndcx = cx / cw;
    local ndcy = cy / cw;
    local ndcz = cz / cw;
    local sx = (ndcx * 0.5 + 0.5) * vp_w;
    local sy = (-ndcy * 0.5 + 0.5) * vp_h;
    return sx, sy, true, ndcz;
end

-------------------------------------------------------------------------------
-- Dotted Line Tuning
-------------------------------------------------------------------------------

-- Adjustable via settings
local DOT_SPACING    = 0.3;    -- Visual dot spacing (yalms) — interpolates terrain
local MAX_DOTS       = 500;    -- Safety cap per zone line
local HOVER_HEIGHT   = 0.5;    -- Height above navmesh ground (yalms)
local MAX_GRADIENT   = 0.9;    -- Max yalms height change per dot before flattening

-- Per-zone-line overrides (keyed by tostring(rect_id), value = { height=N, trim=N, flatten=N })
local ZONELINE_OVERRIDES = {};

-- D3D dot size in world units (yalms).
local D3D_DOT_GLOW_SIZE = 0.35;

-- Distance fade: size-based (alpha doesn't work in beginscene pass 2)
local DISTANCE_FADE      = false;
local DISTANCE_FADE_ZONE = 0.3;

-- Reusable labels table (cleared each frame to avoid allocation)
local frame_labels = {};
local frame_labels_n = 0;


-- Convert RGB floats (0-1) to D3D ARGB uint32 with given alpha byte (0-255).
-- Uses arithmetic (not bit ops) to produce positive doubles matching hex literals.
local function rgb_to_argb(rgb, alpha)
    local r = math.floor((rgb[1] or 0) * 255 + 0.5);
    local g = math.floor((rgb[2] or 0) * 255 + 0.5);
    local b = math.floor((rgb[3] or 0) * 255 + 0.5);
    if (r > 255) then r = 255; elseif (r < 0) then r = 0; end
    if (g > 255) then g = 255; elseif (g < 0) then g = 0; end
    if (b > 255) then b = 255; elseif (b < 0) then b = 0; end
    return alpha * 0x1000000 + r * 0x10000 + g * 0x100 + b;
end

-- Color state (rebuilt from settings in apply_settings)
local USE_DIST_COLORS  = false;
-- Main color (used when distance colors are off)
local D3D_CORE_MAIN    = 0xCC00FF00;
local D3D_GLOW_MAIN    = 0x4000FF00;
local D3D_CIRCLE_MAIN  = 0x2200FF00;
-- Distance-based colors
local D3D_CORE_FAR     = 0xCC00FF00;
local D3D_CORE_MID     = 0xCCFFFF00;
local D3D_CORE_CLOSE   = 0xCCFF0000;
local D3D_GLOW_FAR     = 0x4000FF00;
local D3D_GLOW_MID     = 0x40FFFF00;
local D3D_GLOW_CLOSE   = 0x40FF0000;
local D3D_CIRCLE_FAR   = 0x2200FF00;
local D3D_CIRCLE_MID   = 0x22FFFF00;
local D3D_CIRCLE_CLOSE = 0x22FF0000;

local function rebuild_colors(s)
    local core_a = 0xCC;
    local glow_ratio = s.dot_glow or 0.15;
    local glow_a = math.floor(core_a * glow_ratio + 0.5);
    if (glow_a > 255) then glow_a = 255; end

    USE_DIST_COLORS = (s.use_dist_colors == true);

    -- Main color
    local main = s.dot_color or { 0, 1, 0 };
    D3D_CORE_MAIN   = rgb_to_argb(main, core_a);
    D3D_GLOW_MAIN   = rgb_to_argb(main, glow_a);
    D3D_CIRCLE_MAIN = rgb_to_argb(main, 0x22);

    -- Distance colors
    local far   = s.color_far   or { 0, 1, 0 };
    local mid   = s.color_mid   or { 1, 1, 0 };
    local close = s.color_close or { 1, 0, 0 };
    D3D_CORE_FAR     = rgb_to_argb(far,   core_a);
    D3D_CORE_MID     = rgb_to_argb(mid,   core_a);
    D3D_CORE_CLOSE   = rgb_to_argb(close, core_a);
    D3D_GLOW_FAR     = rgb_to_argb(far,   glow_a);
    D3D_GLOW_MID     = rgb_to_argb(mid,   glow_a);
    D3D_GLOW_CLOSE   = rgb_to_argb(close, glow_a);
    D3D_CIRCLE_FAR   = rgb_to_argb(far,   0x22);
    D3D_CIRCLE_MID   = rgb_to_argb(mid,   0x22);
    D3D_CIRCLE_CLOSE = rgb_to_argb(close, 0x22);

end

-- Sync tuning from settings (called only when settings change, not every frame)
local settings_applied = false;
local settings_rev = 0;       -- bumped on any settings change; invalidates curtain_cache
local curtain_cache = {};     -- [rect_id] = { sign, rev, data } — see compute_curtain_positions
local function apply_settings(s)
    if (s == nil) then return; end
    DOT_SPACING          = s.dot_spacing or 0.3;
    HOVER_HEIGHT         = s.hover_height or 0.5;
    MAX_GRADIENT         = s.rise_distance or 0.9;
    D3D_DOT_GLOW_SIZE    = (s.dot_size or 1.4) * 0.05;
    ZONELINE_OVERRIDES   = s.zoneline_overrides or {};
    DISTANCE_FADE        = (s.distance_fade == true);
    DISTANCE_FADE_ZONE   = s.distance_fade_zone or 0.3;
    rebuild_colors(s);
    settings_applied = true;
end

function renderer.mark_settings_dirty()
    settings_applied = false;
    settings_rev = settings_rev + 1;   -- invalidate the curtain position cache
end

-- Clear the curtain position cache. Call on zone change: zone lines and terrain
-- differ per zone, and rect_ids are not guaranteed unique across zones.
function renderer.invalidate_curtain_cache()
    curtain_cache = {};
end

-------------------------------------------------------------------------------
-- Distance Calculation (XZ plane)
-------------------------------------------------------------------------------

local function distance_xz(x1, z1, x2, z2)
    local dx = x1 - x2;
    local dz = z1 - z2;
    return math.sqrt(dx * dx + dz * dz);
end

-- Distance from player to the nearest point on a zone line's front edge.
-- For curtain zone lines (bounding boxes), this measures to the closest point
-- on the wall line at the player-facing depth edge — the actual zone trigger.
-- For circles (portals), falls back to center distance.
local function distance_to_zoneline(px, pz, zl)
    if (zl.sx == nil or zl.sz == nil or zl.sx <= 0 or zl.sz <= 0) then
        return distance_xz(px, pz, zl.x, zl.z);
    end

    local cos_r = math.cos(-(zl.ry or 0));
    local sin_r = math.sin(-(zl.ry or 0));
    local half_sx = zl.sx / 2;
    local half_sz = zl.sz / 2;

    -- Transform player to zone line local space
    local dx = px - zl.x;
    local dz = pz - zl.z;
    local lx =  dx * cos_r + dz * sin_r;
    local lz = -dx * sin_r + dz * cos_r;

    -- Clamp to bounding box in local space (nearest point on box)
    local cx = math.max(-half_sx, math.min(half_sx, lx));
    local cz = math.max(-half_sz, math.min(half_sz, lz));

    -- Distance from player to nearest point on box edge
    local dlx = lx - cx;
    local dlz = lz - cz;
    return math.sqrt(dlx * dlx + dlz * dlz);
end

-------------------------------------------------------------------------------
-- Compute curtain dot positions along the wider box edge.
-- Returns: { positions = {{wx,wy,wz}, ...}, hover_y, label_x, label_z }
-------------------------------------------------------------------------------

local function compute_curtain_positions(wx, wy, wz, half_sx, half_sy, half_sz,
                                          rot_y, player_x, player_z, terrain_heights, rect_id, edge_trim)
    local cos_r = math.cos(-rot_y);
    local sin_r = math.sin(-rot_y);

    -- Wall axis = wider dimension (stable, matches terrain extraction).
    -- Depth axis = narrower dimension (player walks through this).
    -- Only the depth offset SIGN uses player position (which edge to face).
    local along_x, wall_half, depth_half;
    if (half_sx >= half_sz) then
        along_x    = true;
        wall_half  = half_sx;
        depth_half = half_sz;
    else
        along_x    = false;
        wall_half  = half_sz;
        depth_half = half_sx;
    end

    -- Player offset in local space (only used for edge-facing direction)
    local dx = player_x - wx;
    local dz = player_z - wz;
    local local_x_comp =  dx * cos_r + dz * sin_r;
    local local_z_comp = -dx * sin_r + dz * cos_r;

    -- Push dots and label to the player-facing box edge. The facing-edge SIGN is
    -- the only player-dependent input to the result.
    local depth_sign;
    if (along_x) then
        depth_sign = (local_z_comp >= 0) and 1 or -1;
    else
        depth_sign = (local_x_comp >= 0) and 1 or -1;
    end
    local depth_offset = depth_sign * depth_half;

    -- Result cache: the output is a pure function of (rect_id, depth_sign, settings).
    -- Geometry and terrain are static per zone line; only the facing edge and tuning
    -- settings change. On a hit we skip the terrain interpolation, 3-pass smoothing,
    -- gradient blend, and all per-dot allocations.
    if (rect_id ~= nil) then
        local c = curtain_cache[rect_id];
        if (c ~= nil and c.sign == depth_sign and c.rev == settings_rev) then
            return c.data;
        end
    end

    -- Visual dot count
    local wall_len = wall_half * 2;
    local num_dots = math.max(2, math.floor(wall_len / DOT_SPACING) + 1);
    if (num_dots > MAX_DOTS) then num_dots = MAX_DOTS; end

    -- Synth ground: box bottom minus 2 yalms (fallback when no terrain data)
    local synth_ground = wy + half_sy - 2;

    -- Terrain height interpolation setup.
    -- New format: { pos_heights = {...}, neg_heights = {...} }
    -- Each array is actual terrain at that depth edge — no uniform offset needed.
    local th = nil;
    local th_adj = 0;
    if (terrain_heights ~= nil) then
        if (terrain_heights.pos_heights ~= nil) then
            -- Edge-first format: pick the array for the player-facing edge
            if (depth_offset >= 0) then
                th = terrain_heights.pos_heights;
            else
                th = terrain_heights.neg_heights or terrain_heights.pos_heights;
            end
            th_adj = 0;
        else
            -- Legacy format: center heights + uniform offset
            th = terrain_heights.heights;
            if (depth_offset >= 0) then
                th_adj = terrain_heights.pos_adj or 0;
            else
                th_adj = terrain_heights.neg_adj or 0;
            end
        end
    end
    local th_n = 0;
    if (th ~= nil) then th_n = #th; end

    -- Edge trimming: per-entry trim amount (e.g. 4.0 for Mog House entries whose
    -- DAT bounding boxes extend past visual railings). Most entries pass 0 (no trim).
    local trim_yalms = edge_trim or 0;
    local MIN_SPAN_YALMS = 4.0;
    local col_start = 0;
    local col_end = num_dots - 1;
    if (trim_yalms > 0 and wall_len > MIN_SPAN_YALMS) then
        local max_trim = (wall_len - MIN_SPAN_YALMS) / 2;
        local trim = math.min(trim_yalms, max_trim);
        local t_trim = trim / wall_len;
        col_start = math.ceil(t_trim * math.max(1, num_dots - 1));
        col_end = math.floor((1.0 - t_trim) * math.max(1, num_dots - 1));
    end

    -- Compute world positions with per-dot terrain following
    local positions = {};
    local label_hover_y = synth_ground - HOVER_HEIGHT;  -- fallback for label

    for col = col_start, col_end do
        local t = col / math.max(1, num_dots - 1);
        local wall_pos = -wall_half + wall_len * t;

        local lx, lz;
        if (along_x) then
            lx = wall_pos;
            lz = depth_offset;
        else
            lx = depth_offset;
            lz = wall_pos;
        end

        local wrx = lx * cos_r - lz * sin_r;
        local wrz = lx * sin_r + lz * cos_r;

        local pos_y = nil;
        if (th_n >= 2) then
            local th_t = t * (th_n - 1);      -- 0-based position in terrain array
            local lo = math.floor(th_t) + 1;   -- 1-based Lua index
            local hi = math.min(lo + 1, th_n);
            local frac = th_t - (lo - 1);

            local h_lo = th[lo];
            local h_hi = th[hi];

            if (h_lo ~= false and h_lo ~= nil and h_hi ~= false and h_hi ~= nil) then
                pos_y = (h_lo + (h_hi - h_lo) * frac) + th_adj - HOVER_HEIGHT;
            elseif (h_lo ~= false and h_lo ~= nil) then
                pos_y = h_lo + th_adj - HOVER_HEIGHT;
            elseif (h_hi ~= false and h_hi ~= nil) then
                pos_y = h_hi + th_adj - HOVER_HEIGHT;
            end
        end

        -- No terrain data at all: use synth ground fallback
        if (pos_y == nil and th_n < 2) then
            pos_y = synth_ground - HOVER_HEIGHT;
        end

        -- Skip dots where terrain is off-navmesh (both samples false)
        if (pos_y ~= nil) then
            positions[#positions + 1] = {
                wx = wx + wrx,
                wy = pos_y,
                wz = wz + wrz,
            };
        end
    end

    -- Auto-flatten: if terrain variance is small (e.g. town zone lines, flat hallways),
    -- snap all dots to median height for a clean straight line.
    local n = #positions;
    if (n >= 2) then
        local min_y, max_y = positions[1].wy, positions[1].wy;
        for i = 2, n do
            if (positions[i].wy < min_y) then min_y = positions[i].wy; end
            if (positions[i].wy > max_y) then max_y = positions[i].wy; end
        end
        local variance = max_y - min_y;  -- in FFXI coords, larger span = more variance
        if (variance < 1.5) then
            -- Flat enough — use midpoint height for a clean line
            local mid_y = min_y + (max_y - min_y) / 2;
            for i = 1, n do positions[i].wy = mid_y; end
        end
    end

    -- Smooth elevation: 3-pass neighbor moving average to remove jarring height jumps.
    if (n >= 3) then
        for pass = 1, 3 do
            local prev_y = positions[1].wy;
            for i = 2, n - 1 do
                local curr = positions[i].wy;
                local next_y = positions[i + 1].wy;
                local smoothed = prev_y * 0.25 + curr * 0.5 + next_y * 0.25;
                prev_y = curr;
                positions[i].wy = smoothed;
            end
        end
    end

    -- Per-entry overrides (cached lookup)
    local entry_ovr = {};
    if (rect_id ~= nil) then
        entry_ovr = ZONELINE_OVERRIDES[tostring(rect_id)] or {};
    end

    -- Per-entry cliff flatten override (0 = use global MAX_GRADIENT)
    local entry_gradient = MAX_GRADIENT;
    if (type(entry_ovr.flatten) == 'number' and entry_ovr.flatten > 0) then
        entry_gradient = entry_ovr.flatten;
    end

    -- Gradient flattening with smooth blend: scan from center outward. Flatten when:
    -- 1) Per-dot slope exceeds threshold (sharp cliff), OR
    -- 2) Total deviation from center height exceeds entry_gradient * 3 (gradual slope
    --    that accumulates — e.g. valley dips like Tahrongi Canyon).
    -- Threshold is normalized by DOT_SPACING so it measures slope (yalms/yalm).
    if (n >= 3) then
        local center = math.floor(n / 2) + 1;
        local BLEND_DOTS = 6;
        local grad_threshold = entry_gradient * DOT_SPACING;  -- per-dot threshold
        local max_deviation = entry_gradient * 3;  -- max total yalms from center
        local center_y = positions[center].wy;

        -- Scan right from center — blend to flat when too steep or too far
        for i = center + 1, n do
            local per_dot = math.abs(positions[i].wy - positions[i - 1].wy);
            local from_center = math.abs(positions[i].wy - center_y);
            if (per_dot > grad_threshold or from_center > max_deviation) then
                local flat_y = positions[i - 1].wy;
                local blend_start = math.max(center + 1, i - BLEND_DOTS);
                for j = blend_start, i - 1 do
                    local t = (j - blend_start) / math.max(1, i - 1 - blend_start);
                    positions[j].wy = positions[j].wy + (flat_y - positions[j].wy) * t * t;
                end
                for j = i, n do
                    positions[j].wy = flat_y;
                end
                break;
            end
        end

        -- Scan left from center — blend to flat when too steep or too far
        for i = center - 1, 1, -1 do
            local per_dot = math.abs(positions[i].wy - positions[i + 1].wy);
            local from_center = math.abs(positions[i].wy - center_y);
            if (per_dot > grad_threshold or from_center > max_deviation) then
                local flat_y = positions[i + 1].wy;
                local blend_end = math.min(center - 1, i + BLEND_DOTS);
                for j = blend_end, i + 1, -1 do
                    local t = (blend_end - j) / math.max(1, blend_end - i - 1);
                    positions[j].wy = positions[j].wy + (flat_y - positions[j].wy) * t * t;
                end
                for j = i, 1, -1 do
                    positions[j].wy = flat_y;
                end
                break;
            end
        end
    end

    -- Apply per-zone-line height override (positive = visually higher = subtract from wy)
    local h_offset = (type(entry_ovr.height) == 'number' and entry_ovr.height) or 0;
    if (h_offset ~= 0) then
        for i = 1, n do
            positions[i].wy = positions[i].wy - h_offset;
        end
    end

    -- Update label height from middle dot
    if (n >= 1) then
        local mid = math.floor(n / 2) + 1;
        label_hover_y = positions[math.min(mid, n)].wy;
    end

    -- Label position: player-facing edge center (unclamped)
    local label_lx, label_lz;
    if (along_x) then
        label_lx = 0;
        label_lz = depth_offset;
    else
        label_lx = depth_offset;
        label_lz = 0;
    end
    local label_wx = wx + label_lx * cos_r - label_lz * sin_r;
    local label_wz = wz + label_lx * sin_r + label_lz * cos_r;

    local result = { positions = positions, hover_y = label_hover_y, label_x = label_wx, label_z = label_wz };
    if (rect_id ~= nil) then
        curtain_cache[rect_id] = { sign = depth_sign, rev = settings_rev, data = result };
    end
    return result;
end



-------------------------------------------------------------------------------
-- Check: is this zone line a dotted curtain?
-------------------------------------------------------------------------------

local function is_curtain_zoneline(zl)
    local has_box = (zl.sx ~= nil and zl.sx > 0 and zl.sz ~= nil and zl.sz > 0);
    local is_box_source = (zl.source == 'dat' or zl.source == 'trigger');
    -- Exclude near-square massive boxes (e.g., 50x50 Navukgo arena triggers).
    -- These are area-capture triggers, not passage doorways.
    local is_square = has_box and (math.min(zl.sx, zl.sz) / math.max(zl.sx, zl.sz) > 0.6)
                      and math.max(zl.sx, zl.sz) > 20;
    return (is_box_source and has_box
            and not is_square and zl.shape ~= 'circle'
            and zl.terrain_heights ~= nil);
end


-------------------------------------------------------------------------------
-- D3D8 Depth-Tested Rendering: Billboard diamond dot
-- Draws a camera-facing diamond at (wx, wy, wz) in world units.
-------------------------------------------------------------------------------

-- Single gradient circle: center = core_col (bright), rim = glow_col (dim).
-- Billboard fan with DOT_CIRCLE_SEGS segments for smooth round shape.
local DOT_ANGLE_STEP = (2 * math.pi) / DOT_CIRCLE_SEGS;

local function draw_d3d_dot_gradient(device, rx, ry, rz, ux, uy, uz,
                                      wx, wy, wz, size, core_col, glow_col)
    local vi = 0;
    for i = 0, DOT_CIRCLE_SEGS - 1 do
        local a1 = i * DOT_ANGLE_STEP;
        local a2 = (i + 1) * DOT_ANGLE_STEP;
        local cos1 = math.cos(a1); local sin1 = math.sin(a1);
        local cos2 = math.cos(a2); local sin2 = math.sin(a2);

        -- Center vertex (core color)
        d3d_verts[vi].x = wx; d3d_verts[vi].y = wy; d3d_verts[vi].z = wz;
        d3d_verts[vi].color = core_col; vi = vi + 1;

        -- Edge vertex 1 (glow color, billboard offset along camera right + up)
        d3d_verts[vi].x = wx + (rx * cos1 + ux * sin1) * size;
        d3d_verts[vi].y = wy + (ry * cos1 + uy * sin1) * size;
        d3d_verts[vi].z = wz + (rz * cos1 + uz * sin1) * size;
        d3d_verts[vi].color = glow_col; vi = vi + 1;

        -- Edge vertex 2 (glow color)
        d3d_verts[vi].x = wx + (rx * cos2 + ux * sin2) * size;
        d3d_verts[vi].y = wy + (ry * cos2 + uy * sin2) * size;
        d3d_verts[vi].z = wz + (rz * cos2 + uz * sin2) * size;
        d3d_verts[vi].color = glow_col; vi = vi + 1;
    end

    device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, DOT_CIRCLE_SEGS, d3d_verts, VERTEX_SIZE);
end

-------------------------------------------------------------------------------
-- D3D8 Depth-Tested Rendering: Flat circle on ground plane
-- Draws a filled circle at (wx, wy, wz) with given radius, lying on XZ plane.
-------------------------------------------------------------------------------

local function draw_d3d_circle(device, wx, wy, wz, radius, color_argb)
    local angle_step = (2 * math.pi) / CIRCLE_SEGS;
    local vi = 0;

    for i = 0, CIRCLE_SEGS - 1 do
        local a1 = i * angle_step;
        local a2 = (i + 1) * angle_step;

        circle_verts[vi].x = wx;
        circle_verts[vi].y = wy;
        circle_verts[vi].z = wz;
        circle_verts[vi].color = color_argb;
        vi = vi + 1;

        circle_verts[vi].x = wx + math.cos(a1) * radius;
        circle_verts[vi].y = wy;
        circle_verts[vi].z = wz + math.sin(a1) * radius;
        circle_verts[vi].color = color_argb;
        vi = vi + 1;

        circle_verts[vi].x = wx + math.cos(a2) * radius;
        circle_verts[vi].y = wy;
        circle_verts[vi].z = wz + math.sin(a2) * radius;
        circle_verts[vi].color = color_argb;
        vi = vi + 1;
    end

    device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, CIRCLE_SEGS, circle_verts, VERTEX_SIZE);
end

-------------------------------------------------------------------------------
-- D3D Pole: Thin vertical billboard quad from (wx, wy, wz) upward by height
-- Uses camera right vector so the pole always faces the player.
-------------------------------------------------------------------------------

local POLE_HALF_WIDTH = 0.04;  -- half-width in yalms

local function draw_d3d_pole(device, wx, wy, wz, height, rx, ry, rz, color_argb)
    -- Billboard thin quad: width along camera right, height along world up (D3D Y)
    local hw = POLE_HALF_WIDTH;
    local top_y = wy - height;  -- D3D Y: subtract = up

    -- Bottom-left, bottom-right, top-right, top-left
    local bx1 = wx - rx * hw;
    local bz1 = wz - rz * hw;
    local bx2 = wx + rx * hw;
    local bz2 = wz + rz * hw;
    local tx1 = bx1;
    local tz1 = bz1;
    local tx2 = bx2;
    local tz2 = bz2;

    -- Triangle 1: BL, BR, TR
    pole_verts[0].x = bx1; pole_verts[0].y = wy;    pole_verts[0].z = bz1; pole_verts[0].color = color_argb;
    pole_verts[1].x = bx2; pole_verts[1].y = wy;    pole_verts[1].z = bz2; pole_verts[1].color = color_argb;
    pole_verts[2].x = tx2; pole_verts[2].y = top_y;  pole_verts[2].z = tz2; pole_verts[2].color = color_argb;
    -- Triangle 2: BL, TR, TL
    pole_verts[3].x = bx1; pole_verts[3].y = wy;    pole_verts[3].z = bz1; pole_verts[3].color = color_argb;
    pole_verts[4].x = tx2; pole_verts[4].y = top_y;  pole_verts[4].z = tz2; pole_verts[4].color = color_argb;
    pole_verts[5].x = tx1; pole_verts[5].y = top_y;  pole_verts[5].z = tz1; pole_verts[5].color = color_argb;

    device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, 2, pole_verts, VERTEX_SIZE);
end

-------------------------------------------------------------------------------
-- D3D Border Style: Dots (style 0) — billboard diamonds per position
-------------------------------------------------------------------------------

local function draw_d3d_style_dots(device, cdata, rx, ry, rz, ux, uy, uz, core_col, glow_col, dot_size)
    local sz = dot_size or D3D_DOT_GLOW_SIZE;
    for _, p in ipairs(cdata.positions) do
        draw_d3d_dot_gradient(device, rx, ry, rz, ux, uy, uz,
            p.wx, p.wy, p.wz, sz, core_col, glow_col);
    end
end


-------------------------------------------------------------------------------
-- D3D8 Depth-Tested Rendering: Main entry point
-- Called from d3d_beginscene pass 2 (before game renders world geometry).
-- Game geometry naturally occludes markers via depth buffer.
-------------------------------------------------------------------------------

local function get_d3d_dot_colors(dist)
    if (not USE_DIST_COLORS) then
        return D3D_CORE_MAIN, D3D_GLOW_MAIN;
    end
    if (dist < 10) then
        return D3D_CORE_CLOSE, D3D_GLOW_CLOSE;
    elseif (dist < 20) then
        return D3D_CORE_MID, D3D_GLOW_MID;
    end
    return D3D_CORE_FAR, D3D_GLOW_FAR;
end

local function get_d3d_circle_color(dist)
    if (not USE_DIST_COLORS) then return D3D_CIRCLE_MAIN; end
    if (dist < 10) then return D3D_CIRCLE_CLOSE; end
    if (dist < 20) then return D3D_CIRCLE_MID; end
    return D3D_CIRCLE_FAR;
end

-------------------------------------------------------------------------------
-- Extracted pass functions (own upvalue budgets — avoids LuaJIT 60-upvalue
-- limit on the main draw_d3d pcall closure)
-------------------------------------------------------------------------------

-- ============================================================================
-- GdiFonts labels: GDI renders each string (+outline) into a texture WE own
-- (stable, unlike the ImGui atlas), drawn as a depth-tested quad so terrain occludes it.
-- ============================================================================
local gdi = nil;
local gdi_tried = false;
local function ensure_gdi()
    if (gdi ~= nil or gdi_tried) then return gdi; end
    gdi_tried = true;
    local ok, lib = pcall(require, 'gdifonts.include');
    if (ok and lib ~= nil) then
        gdi = lib;
        pcall(function() gdi:set_auto_render(false); end);  -- we draw manually, occluded
    end
    return gdi;
end

renderer.gdi_font_family   = 'Arial';
renderer.gdi_outline_width = 2;     -- label outline thickness (px at render res)
renderer.gdi_bold          = true;  -- bold label text

-- ----------------------------------------------------------------------------
-- Font picker = common Windows fonts + bundled fonts/ the user has installed.
-- Read-only: never installs fonts or writes the registry; only offers a bundled
-- font once GdiFonts confirms it's installed (get_font_available).
-- ----------------------------------------------------------------------------
local COMMON_FONTS = { 'Arial', 'Calibri', 'Segoe UI', 'Consolas', 'Verdana', 'Tahoma', 'Trebuchet MS', 'Times New Roman' };
renderer.font_list = COMMON_FONTS;     -- rebuilt (common + installed bundled) by scan_fonts

-- Read a TTF/OTF family name (name table, nameID 1, Windows platform preferred).
local function ttf_family(path)
    local ok, fam = pcall(function()
        local fh = io.open(path, 'rb');
        if (fh == nil) then return nil; end
        local d = fh:read('*a'); fh:close();
        if (d == nil or #d < 12) then return nil; end
        local function u16(o) local a,b = d:byte(o), d:byte(o+1); if (a == nil or b == nil) then return 0; end return a*256 + b; end
        local function u32(o) local a,b,c,e = d:byte(o), d:byte(o+1), d:byte(o+2), d:byte(o+3); if (a == nil or e == nil) then return 0; end return ((a*256+b)*256+c)*256+e; end
        local ntab = u16(5);
        local rec, noff = 13, nil;
        for _ = 1, ntab do
            if (d:sub(rec, rec+3) == 'name') then noff = u32(rec+8) + 1; break; end
            rec = rec + 16;
        end
        if (noff == nil) then return nil; end
        local count = u16(noff+2);
        local storage = noff + u16(noff+4);
        local best = nil;
        for i = 0, count-1 do
            local r = noff + 6 + i*12;
            local pid, nid, len, off = u16(r), u16(r+6), u16(r+8), u16(r+10);
            if (nid == 1 and len > 0) then
                local str = d:sub(storage+off, storage+off+len-1);
                if (pid == 3 or pid == 0) then       -- Windows/Unicode = UTF-16BE
                    local out = {};
                    for j = 1, #str, 2 do out[#out+1] = string.char(str:byte(j+1) or 32); end
                    best = table.concat(out);
                    if (pid == 3) then break; end
                elseif (pid == 1 and best == nil) then  -- Mac = ASCII
                    best = str;
                end
            end
        end
        return best;
    end);
    return ok and fam or nil;
end

-- Build the picker list: common fonts + any bundled font the user has installed.
function renderer.scan_fonts()
    local list = {};
    for _, f in ipairs(COMMON_FONTS) do list[#list+1] = f; end

    -- gdifonts renders via GDI+, which only sees INSTALLED fonts. Offer a bundled
    -- font only once it's installed, so we never show one that renders blank.
    local g = nil;
    pcall(function() local ok, lib = pcall(require, 'gdifonts.include'); if (ok) then g = lib; end end);
    local function usable(name)
        if (g == nil) then return false; end
        local ok, r = pcall(function() return g:get_font_available(name); end);
        return (ok and r == true);
    end

    local dir = nil;
    pcall(function() dir = addon.path:append('\\fonts\\'); end);
    if (dir == nil) then pcall(function() dir = addon.path .. '\\fonts\\'; end); end
    if (dir ~= nil) then
        local files = nil;
        pcall(function() files = ashita.fs.get_dir(dir, '.*', false); end);
        if (files ~= nil) then
            for _, fn in ipairs(files) do
                local lower = tostring(fn):lower();
                if (lower:match('%.ttf$') or lower:match('%.otf$')) then
                    local fam = ttf_family(dir .. fn);
                    if (fam ~= nil and fam ~= '' and usable(fam)) then
                        local dup = false;
                        for _, x in ipairs(list) do if (x == fam) then dup = true; break; end end
                        if (not dup) then list[#list+1] = fam; end
                    end
                end
            end
        end
    end
    renderer.font_list = list;
    return list;
end

local GDI_FONT_HEIGHT = 30;     -- render resolution (downscaled at draw time = clean)
local gdi_cache = {};           -- text -> { obj=, frame= }
local gdi_frame = 0;

local function gdi_get(text)
    if (gdi == nil or text == nil or text == '') then return nil, nil; end
    local e = gdi_cache[text];
    if (e == nil) then
        local ok, obj = pcall(function()
            return gdi:create_object({
                font_family   = renderer.gdi_font_family or 'Arial',
                font_height   = GDI_FONT_HEIGHT,
                font_flags    = (renderer.gdi_bold ~= false) and 1 or 0,
                font_color    = 0xFFFFFFFF,
                outline_color = 0xFF000000,
                outline_width = renderer.gdi_outline_width or 2,
                text          = text,
            }, true);  -- manual = not added to gdifonts' own 2D auto-render
        end);
        if (not ok or obj == nil) then return nil, nil; end
        e = { obj = obj };
        gdi_cache[text] = e;
    end
    e.frame = gdi_frame;
    local tex, rect = nil, nil;
    pcall(function() tex, rect = e.obj:get_texture(); end);
    return tex, rect;
end

local function gdi_evict()
    if (gdi == nil) then return; end
    for k, e in pairs(gdi_cache) do
        if (gdi_frame - (e.frame or 0) > 60) then
            pcall(function() gdi:destroy_object(e.obj); end);
            gdi_cache[k] = nil;
        end
    end
end

function renderer.cleanup_gdi()
    if (gdi == nil) then return; end
    for k, e in pairs(gdi_cache) do
        pcall(function() gdi:destroy_object(e.obj); end);
        gdi_cache[k] = nil;
    end
end

-- Draw one gdifonts texture as a depth-tested screen quad (pixel-snapped).
local function draw_label_tex(device, tex, w, h, x, y, z)
    local x0 = math.floor(x + 0.5);
    local y0 = math.floor(y + 0.5);
    local x1 = x0 + math.floor(w + 0.5);
    local y1 = y0 + math.floor(h + 0.5);
    local col = 0xFFFFFFFF;  -- white; texture carries the real color + outline
    local v = text_verts;
    v[0].x=x0; v[0].y=y0; v[0].z=z; v[0].color=col; v[0].tu=0.0; v[0].tv=0.0;
    v[1].x=x1; v[1].y=y0; v[1].z=z; v[1].color=col; v[1].tu=1.0; v[1].tv=0.0;
    v[2].x=x0; v[2].y=y1; v[2].z=z; v[2].color=col; v[2].tu=0.0; v[2].tv=1.0;
    v[3].x=x1; v[3].y=y0; v[3].z=z; v[3].color=col; v[3].tu=1.0; v[3].tv=0.0;
    v[4].x=x1; v[4].y=y1; v[4].z=z; v[4].color=col; v[4].tu=1.0; v[4].tv=1.0;
    v[5].x=x0; v[5].y=y1; v[5].z=z; v[5].color=col; v[5].tu=0.0; v[5].tv=1.0;
    device:SetTexture(0, ffi.cast('IDirect3DBaseTexture8*', tex));
    device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, 2, text_verts, TEXTURED_VERTEX_SIZE);
end

local function draw_text_pass(device, view, text_scale)
    local vp_w = renderer.cached_vp_w;
    local vp_h = renderer.cached_vp_h;
    local cached_proj = renderer.cached_proj;

    if (frame_labels_n <= 0 or vp_w <= 0 or vp_h <= 0 or cached_proj == nil or view == nil) then
        return;
    end
    if (ensure_gdi() == nil) then return; end
    gdi_frame = gdi_frame + 1;

    device:SetVertexShader(D3DFVF_XYZ_DIFFUSE_TEX1);

    -- Texture stage: color AND alpha straight from the gdifonts texture
    device:SetTextureStageState(0, D3DTSS_COLOROP, 2);    -- SELECTARG1
    device:SetTextureStageState(0, D3DTSS_COLORARG1, 2);  -- TEXTURE
    device:SetTextureStageState(0, D3DTSS_ALPHAOP, 2);    -- SELECTARG1
    device:SetTextureStageState(0, D3DTSS_ALPHAARG1, 2);  -- TEXTURE

    device:SetTextureStageState(0, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
    device:SetTextureStageState(0, D3DTSS_MINFILTER, D3DTEXF_LINEAR);
    device:SetTextureStageState(0, D3DTSS_ADDRESSU, D3DTADDRESS_CLAMP);
    device:SetTextureStageState(0, D3DTSS_ADDRESSV, D3DTADDRESS_CLAMP);

    -- Terminate stage 1
    device:SetTexture(1, nil);
    device:SetTextureStageState(1, D3DTSS_COLOROP, D3DTOP_DISABLE);
    device:SetTextureStageState(1, D3DTSS_ALPHAOP, D3DTOP_DISABLE);

    -- Alpha test: discard transparent glyph background pixels
    device:SetRenderState(D3DRS_ALPHATESTENABLE, 1);
    device:SetRenderState(D3DRS_ALPHAREF, 0x80);   -- cut faint white-on-transparent edge bleed
    device:SetRenderState(D3DRS_ALPHAFUNC, D3DCMP_GREATEREQUAL);

    -- Set up ortho projection: screen pixels map 1:1, Z passes through for depth
    device:SetTransform(D3DTS_WORLD, identity_matrix);
    device:SetTransform(2, identity_matrix);  -- view = identity

    -- Rebuild ortho each frame (viewport size may change)
    ffi.fill(ortho_matrix, ffi.sizeof('D3DMATRIX'), 0);
    ortho_matrix._11 =  2.0 / vp_w;    -- X: [0,w] -> [-1,1]
    ortho_matrix._22 = -2.0 / vp_h;    -- Y: [0,h] -> [1,-1] (flip Y)
    ortho_matrix._33 =  1.0;            -- Z: pass through
    ortho_matrix._44 =  1.0;
    ortho_matrix._41 = -1.0;            -- X offset: pixel 0 -> clip -1
    ortho_matrix._42 =  1.0;            -- Y offset: pixel 0 -> clip +1
    device:SetTransform(3, ortho_matrix);  -- projection = ortho

    local ref_dist = 30.0;  -- distance where text is at base scale
    local min_s = renderer.d3d_text_min_scale;
    local max_s = renderer.d3d_text_max_scale;
    local base_s = text_scale;

    for li = 1, frame_labels_n do
        local lbl = frame_labels[li];
        if (lbl.x ~= nil and lbl.y ~= nil and lbl.z ~= nil
            and lbl.dist ~= nil) then
            local r1, r2, r3, r4 = project_with_z(
                view, cached_proj, vp_w, vp_h,
                lbl.x, lbl.y, lbl.z);
            local sx = tonumber(r1);
            local sy = tonumber(r2);
            local ndcz = tonumber(r4);
            if (r3 == true and sx ~= nil and sy ~= nil and ndcz ~= nil) then
                local dist_factor = ref_dist / math.max(lbl.dist, 1.0);
                dist_factor = math.max(min_s, math.min(max_s, dist_factor));
                local fs = base_s * dist_factor;
                -- Scale text with distance fade so labels shrink with dots
                if (lbl.fade ~= nil and lbl.fade < 1.0) then
                    fs = fs * lbl.fade;
                end
                -- Scale gdifonts texture px (rendered at GDI_FONT_HEIGHT) to screen px.
                local q = fs * 14.0 / GDI_FONT_HEIGHT;
                local line_height = fs * 14;
                local dpos = renderer.d3d_dist_position or 'bottom';
                local spacing = renderer.d3d_label_spacing or 2;

                -- Add separator for left/right positioning
                local draw_dist_text = lbl.dist_text;
                if (lbl.dist_text ~= nil) then
                    if (dpos == 'right') then
                        draw_dist_text = '- ' .. lbl.dist_text;
                    elseif (dpos == 'left') then
                        draw_dist_text = lbl.dist_text .. ' -';
                    end
                end

                local name_tex, name_rect = nil, nil;
                local name_tw, name_th = 0, 0;
                if (lbl.name ~= nil) then
                    name_tex, name_rect = gdi_get(lbl.name);
                    if (name_rect ~= nil) then name_tw = name_rect.right * q; name_th = name_rect.bottom * q; end
                end
                local dist_tex, dist_rect = nil, nil;
                local dist_tw, dist_th = 0, 0;
                if (draw_dist_text ~= nil) then
                    dist_tex, dist_rect = gdi_get(draw_dist_text);
                    if (dist_rect ~= nil) then dist_tw = dist_rect.right * q; dist_th = dist_rect.bottom * q; end
                end

                -- Bottom-anchored: text grows UPWARD from sy (label anchor just
                -- above the dots) so close-range scaling doesn't collide with them.

                local has_both = (lbl.name ~= nil and draw_dist_text ~= nil);

                local ny, nx;  -- name position
                local dx, dy;  -- distance position

                if (dpos == 'bottom') then
                    if (has_both) then
                        dy = sy - line_height;
                        ny = sy - 2 * line_height - spacing;
                    elseif (draw_dist_text ~= nil) then
                        dy = sy - line_height;
                    else
                        ny = sy - line_height;
                    end
                elseif (dpos == 'top') then
                    if (has_both) then
                        ny = sy - line_height;
                        dy = sy - 2 * line_height - spacing;
                    elseif (draw_dist_text ~= nil) then
                        dy = sy - line_height;
                    else
                        ny = sy - line_height;
                    end
                elseif (dpos == 'left' or dpos == 'right') then
                    ny = sy - line_height;
                    dy = sy - line_height;
                end

                if (name_tex ~= nil and ny ~= nil) then
                    nx = sx - name_tw / 2;
                    draw_label_tex(device, name_tex, name_tw, name_th, nx, ny, ndcz);
                end

                if (dist_tex ~= nil and dy ~= nil) then
                    if (dpos == 'bottom' or dpos == 'top') then
                        dx = sx - dist_tw / 2;
                    elseif (dpos == 'right') then
                        dx = sx + name_tw / 2 + spacing;
                    elseif (dpos == 'left') then
                        dx = sx - name_tw / 2 - dist_tw - spacing;
                    else
                        dx = sx - dist_tw / 2;
                    end
                    draw_label_tex(device, dist_tex, dist_tw, dist_th, dx, dy, ndcz);
                end
            end
        end
    end

    gdi_evict();
end

function renderer.draw_d3d(zone_lines, player_x, player_y, player_z, s)
    if (zone_lines == nil or #zone_lines == 0) then return; end

    local device = d3d8.get_device();
    if (device == nil) then return; end

    -- Try fresh view matrix from device (prevents camera lag), fall back to cached copy
    local view = renderer.cached_view;
    local fresh_ok, fresh_v = pcall(function()
        local _, v = device:GetTransform(2);  -- D3DTS_VIEW
        if (v ~= nil) then
            local tbl = copy_matrix(v);
            if (type(tbl._11) == 'number') then return tbl; end
        end
        return nil;
    end);
    if (fresh_ok and fresh_v ~= nil) then
        view = fresh_v;
    end
    if (view == nil) then return; end

    if (not settings_applied) then
        apply_settings(s);
    end

    -- Quick pre-check: skip entire render state manipulation if no zone line
    -- is within render distance.  Setting/restoring D3D state on every frame
    -- even when nothing is drawn can cause sky blinking in open areas.
    local render_dist = s.render_distance or 100.0;
    local any_visible = false;
    for _, zl in ipairs(zone_lines) do
        local dx = player_x - zl.x;
        local dz = player_z - zl.z;
        if (dx * dx + dz * dz <= render_dist * render_dist) then
            any_visible = true;
            break;
        end
    end
    if (not any_visible) then return; end

    -- Extract camera right/up vectors from view matrix for billboard orientation
    -- (view is a plain Lua table — field access is safe, no pcall needed)
    local rx, ry, rz = view._11, view._21, view._31;
    local ux, uy, uz = view._12, view._22, view._32;
    if (type(rx) ~= 'number' or type(uy) ~= 'number') then return; end

    local rlen = math.sqrt(rx * rx + ry * ry + rz * rz);
    if (rlen > 0.001) then rx = rx / rlen; ry = ry / rlen; rz = rz / rlen; end
    local ulen = math.sqrt(ux * ux + uy * uy + uz * uz);
    if (ulen > 0.001) then ux = ux / ulen; uy = uy / ulen; uz = uz / ulen; end

    -- Save ALL render states (must restore even if drawing errors out)
    local _, save_light    = device:GetRenderState(D3DRS_LIGHTING);
    local _, save_zenable  = device:GetRenderState(D3DRS_ZENABLE);
    local _, save_zwrite   = device:GetRenderState(D3DRS_ZWRITEENABLE);
    local _, save_zfunc    = device:GetRenderState(D3DRS_ZFUNC);
    local _, save_zbias    = device:GetRenderState(D3DRS_ZBIAS);
    local _, save_ablend   = device:GetRenderState(D3DRS_ALPHABLENDENABLE);
    local _, save_srcblend = device:GetRenderState(D3DRS_SRCBLEND);
    local _, save_dstblend = device:GetRenderState(D3DRS_DESTBLEND);
    local _, save_cull     = device:GetRenderState(D3DRS_CULLMODE);
    local _, save_atest    = device:GetRenderState(D3DRS_ALPHATESTENABLE);
    local _, save_aref     = device:GetRenderState(D3DRS_ALPHAREF);   -- text pass sets these (0x40 / GREATEREQUAL);
    local _, save_afunc    = device:GetRenderState(D3DRS_ALPHAFUNC);  -- save so we don't leak them into the world draw
    local _, save_fog      = device:GetRenderState(D3DRS_FOGENABLE);  -- zone fog tints our text/markers if left on
    local _, save_fvf      = device:GetVertexShader();
    local _, save_tex      = device:GetTexture(0);
    local _, save_ps       = device:GetPixelShader();
    -- Save transforms as Lua tables — raw cdata from GetTransform() points to
    -- internal D3D buffers that go stale when we SetTransform() our own matrices.
    local _, raw_world = device:GetTransform(D3DTS_WORLD);
    local save_world = (raw_world ~= nil) and copy_matrix(raw_world) or nil;
    local _, raw_view = device:GetTransform(2);  -- D3DTS_VIEW
    local save_view = (raw_view ~= nil) and copy_matrix(raw_view) or nil;
    local _, raw_proj = device:GetTransform(3);  -- D3DTS_PROJECTION
    local save_proj = (raw_proj ~= nil) and copy_matrix(raw_proj) or nil;
    local _, save_colorop   = device:GetTextureStageState(0, D3DTSS_COLOROP);
    local _, save_colorarg1 = device:GetTextureStageState(0, D3DTSS_COLORARG1);
    local _, save_colorarg2 = device:GetTextureStageState(0, D3DTSS_COLORARG2);
    local _, save_alphaop   = device:GetTextureStageState(0, D3DTSS_ALPHAOP);
    local _, save_alphaarg1 = device:GetTextureStageState(0, D3DTSS_ALPHAARG1);
    local _, save_magfilter = device:GetTextureStageState(0, D3DTSS_MAGFILTER);
    local _, save_minfilter = device:GetTextureStageState(0, D3DTSS_MINFILTER);
    local _, save_addru     = device:GetTextureStageState(0, D3DTSS_ADDRESSU);
    local _, save_addrv     = device:GetTextureStageState(0, D3DTSS_ADDRESSV);
    local _, save_s1_colorop = device:GetTextureStageState(1, D3DTSS_COLOROP);
    local _, save_s1_alphaop = device:GetTextureStageState(1, D3DTSS_ALPHAOP);

    -- Set render states for depth-tested colored primitives
    device:SetTexture(0, nil);
    device:SetVertexShader(D3DFVF_XYZ_DIFFUSE);
    -- CRITICAL: Disable any active pixel shader. ImGui/d3d8to9 leaves a pixel shader
    -- active that overrides all TextureStageState settings, producing garbled output.
    device:SetPixelShader(0);
    device:SetRenderState(D3DRS_LIGHTING, 0);
    device:SetRenderState(D3DRS_FOGENABLE, 0);           -- no zone fog tinting our markers/text
    device:SetRenderState(D3DRS_CULLMODE, 1);             -- D3DCULL_NONE
    device:SetRenderState(D3DRS_ALPHABLENDENABLE, 1);
    device:SetRenderState(D3DRS_SRCBLEND, 5);             -- D3DBLEND_SRCALPHA
    device:SetRenderState(D3DRS_DESTBLEND, 6);            -- D3DBLEND_INVSRCALPHA
    device:SetRenderState(D3DRS_ZENABLE, 1);
    device:SetRenderState(D3DRS_ZWRITEENABLE, 1);
    device:SetRenderState(D3DRS_ZFUNC, D3DCMP_LESSEQUAL);
    device:SetRenderState(D3DRS_ZBIAS, 8);

    -- Explicit TextureStageState for untextured vertex-color primitives
    device:SetTextureStageState(0, D3DTSS_COLOROP, 2);    -- SELECTARG1
    device:SetTextureStageState(0, D3DTSS_COLORARG1, 0);  -- DIFFUSE
    device:SetTextureStageState(0, D3DTSS_ALPHAOP, 2);    -- SELECTARG1
    device:SetTextureStageState(0, D3DTSS_ALPHAARG1, 0);  -- DIFFUSE

    -- World transform = identity (vertices already in world space)
    device:SetTransform(D3DTS_WORLD, identity_matrix);

    -- ══ Drawing code wrapped in pcall — state restore ALWAYS runs below ══
    local draw_ok, draw_err = pcall(function()
        local render_dist  = s.render_distance or 100.0;
        local want_labels  = renderer.d3d_show_labels;
        local want_dist    = renderer.d3d_show_distance;
        local text_scale   = renderer.d3d_text_scale;

        -- Collect label data during marker loop (drawn in text pass)
        frame_labels_n = 0;

        -- ── Glow pulse (modulates existing dots — no separate pass needed) ──
        local glow_pulse = 1.0;
        local glow_size_mult = 1.0;
        if (renderer.dot_glow_enabled) then
            local t = math.sin(os.clock() * renderer.dot_glow_speed);  -- -1 to 1
            local gmin = renderer.dot_glow_min or 0.4;
            local gmax = renderer.dot_glow_max or 1.0;
            local mid = (gmin + gmax) / 2;
            local half = (gmax - gmin) / 2;
            glow_pulse = mid + half * t;                     -- alpha oscillation
            glow_size_mult = 1.0 - (1.0 - glow_pulse) * 0.3; -- subtle size breathing
        end

        -- ── Pass 1: Untextured colored markers (dots + circles) ──

        for _, zl in ipairs(zone_lines) do
            local dist = distance_xz(player_x, player_z, zl.x, zl.z);

            -- Cache override lookup once per zone line
            local rect_key = tostring(zl.rect_id);
            local ovr = ZONELINE_OVERRIDES[rect_key] or {};
            if (dist <= render_dist and ovr.hide ~= true) then
                local label_y = zl.y;
                local label_x = zl.x;
                local label_z = zl.z;
                -- Display distance measures to nearest box edge, not center
                local display_dist = distance_to_zoneline(player_x, player_z, zl);

                -- Distance fade: shrink geometry near render_distance edge
                local fade = 1.0;
                if (DISTANCE_FADE and DISTANCE_FADE_ZONE > 0.001) then
                    local fade_near = render_dist * (1.0 - DISTANCE_FADE_ZONE);
                    if (display_dist > fade_near) then
                        fade = math.clamp((render_dist - display_dist) / (render_dist - fade_near), 0.0, 1.0);
                    end
                end

                if (is_curtain_zoneline(zl)) then
                    -- Curtain zone line: compute dot positions along the wider edge
                    local core_col, glow_col = get_d3d_dot_colors(display_dist);

                    -- Apply glow pulse to edge alpha and dot size
                    if (renderer.dot_glow_enabled) then
                        local gr = math.floor(glow_col / 0x10000) % 0x100;
                        local gg = math.floor(glow_col / 0x100) % 0x100;
                        local gb = glow_col % 0x100;
                        local ga = math.floor(glow_col / 0x1000000) % 0x100;
                        ga = math.floor(ga * glow_pulse * renderer.dot_glow_intensity * 2 + 0.5);
                        if (ga > 255) then ga = 255; end
                        glow_col = ga * 0x1000000 + gr * 0x10000 + gg * 0x100 + gb;
                    end

                    local zl_trim = (type(ovr.trim) == 'number' and ovr.trim) or 0;
                    local cdata = compute_curtain_positions(zl.x, zl.y, zl.z,
                        zl.sx / 2, zl.sy / 2, zl.sz / 2,
                        zl.ry or 0, player_x, player_z, zl.terrain_heights, zl.rect_id, zl_trim);
                    label_y = cdata.hover_y;
                    label_x = cdata.label_x;
                    label_z = cdata.label_z;
                    local dot_sz = D3D_DOT_GLOW_SIZE * glow_size_mult * fade;
                    draw_d3d_style_dots(device, cdata, rx, ry, rz, ux, uy, uz, core_col, glow_col, dot_sz);
                else
                    -- Non-curtain: circle marker (portals)
                    local fill_col = get_d3d_circle_color(display_dist);
                    local has_box = (zl.sx ~= nil and zl.sx > 0 and zl.sz ~= nil and zl.sz > 0);
                    local r;
                    if (has_box) then
                        r = math.max(zl.sx or 8.0, zl.sz or 8.0) / 2;
                    else
                        r = zl.sx or 8.0;
                    end
                    draw_d3d_circle(device, zl.x, zl.y, zl.z, r * fade, fill_col);

                    -- Draw vertical pole from circle center up to label height
                    local pole_h = (type(ovr.pole_height) == 'number' and ovr.pole_height > 0)
                        and ovr.pole_height or 4.0;
                    pole_h = pole_h * fade;
                    local core_col = get_d3d_dot_colors(display_dist);
                    draw_d3d_pole(device, zl.x, zl.y, zl.z, pole_h, rx, ry, rz, core_col);
                    label_y = zl.y - pole_h;  -- move label to top of pole
                end

                -- Collect labels for text pass (name + distance stacked in screen space)
                -- Skip labels when fade is too small (unreadable specks)
                if ((want_labels or want_dist) and fade >= 0.15) then
                    local text_y = label_y - renderer.d3d_label_offset;
                    local name = nil;
                    local dist_text = nil;
                    if (want_labels) then
                        name = zl.display_name;
                        if (name == nil or name == '') then name = 'Zone Line'; end
                    end
                    if (want_dist) then
                        dist_text = string.format('%.0fy', display_dist);
                    end
                    frame_labels_n = frame_labels_n + 1;
                    local lbl = frame_labels[frame_labels_n];
                    if (lbl == nil) then lbl = {}; frame_labels[frame_labels_n] = lbl; end
                    lbl.x = label_x; lbl.y = text_y; lbl.z = label_z;
                    lbl.name = name; lbl.dist_text = dist_text; lbl.dist = display_dist;
                    lbl.fade = fade;
                end
            end
        end

        -- ── Pass 2: Text labels ──
        -- (Extracted to standalone function to stay within LuaJIT 60-upvalue limit)
        draw_text_pass(device, view, text_scale);
    end);

    -- ══ ALWAYS restore render states (even if drawing errored out) ══
    if (save_world ~= nil) then device:SetTransform(D3DTS_WORLD, table_to_matrix(save_world, restore_world)); end
    if (save_view ~= nil) then device:SetTransform(2, table_to_matrix(save_view, restore_view)); end
    if (save_proj ~= nil) then device:SetTransform(3, table_to_matrix(save_proj, restore_proj)); end
    device:SetTexture(0, save_tex);
    -- GetTexture(0) AddRef'd this texture (Ashita's wrapper returns the raw
    -- pointer, no ffi.gc). Release the reference we own or its refcount climbs
    -- every frame, pinning zone textures alive across zone changes (VRAM creep).
    -- A NULL cdata pointer compares == nil, so this also covers "nothing bound".
    if (save_tex ~= nil) then save_tex:Release(); end
    device:SetRenderState(D3DRS_LIGHTING, save_light);
    device:SetRenderState(D3DRS_FOGENABLE, save_fog);
    device:SetRenderState(D3DRS_ZENABLE, save_zenable);
    device:SetRenderState(D3DRS_ZWRITEENABLE, save_zwrite);
    device:SetRenderState(D3DRS_ZFUNC, save_zfunc);
    device:SetRenderState(D3DRS_ZBIAS, save_zbias);
    device:SetRenderState(D3DRS_ALPHABLENDENABLE, save_ablend);
    device:SetRenderState(D3DRS_SRCBLEND, save_srcblend);
    device:SetRenderState(D3DRS_DESTBLEND, save_dstblend);
    device:SetRenderState(D3DRS_CULLMODE, save_cull);
    device:SetRenderState(D3DRS_ALPHATESTENABLE, save_atest);
    device:SetRenderState(D3DRS_ALPHAREF, save_aref);    -- restore so foliage/fence/hair
    device:SetRenderState(D3DRS_ALPHAFUNC, save_afunc);  -- alpha-test isn't disturbed this frame
    device:SetVertexShader(save_fvf);
    if (save_ps ~= nil) then device:SetPixelShader(save_ps); end
    device:SetTextureStageState(0, D3DTSS_COLOROP, save_colorop);
    device:SetTextureStageState(0, D3DTSS_COLORARG1, save_colorarg1);
    device:SetTextureStageState(0, D3DTSS_COLORARG2, save_colorarg2);
    device:SetTextureStageState(0, D3DTSS_ALPHAOP, save_alphaop);
    device:SetTextureStageState(0, D3DTSS_ALPHAARG1, save_alphaarg1);
    device:SetTextureStageState(0, D3DTSS_MAGFILTER, save_magfilter);
    device:SetTextureStageState(0, D3DTSS_MINFILTER, save_minfilter);
    device:SetTextureStageState(0, D3DTSS_ADDRESSU, save_addru);
    device:SetTextureStageState(0, D3DTSS_ADDRESSV, save_addrv);
    device:SetTextureStageState(1, D3DTSS_COLOROP, save_s1_colorop);
    device:SetTextureStageState(1, D3DTSS_ALPHAOP, save_s1_alphaop);

    -- Log drawing errors (once)
    if (not draw_ok) then
        if (not renderer._draw_err_logged) then
            print(chat.header('zonelines') .. chat.error('draw_d3d error: ' .. tostring(draw_err)));
            renderer._draw_err_logged = true;
        end
    else
        renderer._draw_err_logged = false;
    end
end



return renderer;
