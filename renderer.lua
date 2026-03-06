--[[
    ZoneLines v1.0.0 - Zone Line Rendering via D3D8

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
-- D3D8 FFI: Vertex struct and constants (depth-tested rendering pipeline)
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

-- Font atlas state (initialized from d3d_present where ImGui is ready)
local font_atlas_tex_ptr = nil;
local font_baked         = nil;
local font_baked_size    = 0;


-- D3D text colors (ARGB)
local D3D_TEXT_WHITE  = 0xFFFFFFFF;

-- D3D state
renderer.d3d_pass          = 0;
renderer.cached_view       = nil;
renderer.cached_proj       = nil;
renderer.cached_vp_w       = 0;
renderer.cached_vp_h       = 0;
renderer.hide_behind_walls = true;
renderer.d3d_text_scale    = 1.0;   -- base font size multiplier
renderer.d3d_label_offset  = 0.6;  -- world yalms above dots for label
renderer.d3d_text_min_scale = 0.5; -- min font scale (far away)
renderer.d3d_text_max_scale = 3.0; -- max font scale (close up)
renderer.d3d_show_labels   = true;
renderer.d3d_show_distance = true;

-------------------------------------------------------------------------------
-- Font Atlas: Initialize from ImGui's baked font atlas for D3D text rendering
-------------------------------------------------------------------------------

local font_init_fail_count = 0;  -- rate-limit failure logs

function renderer.init_font_atlas()
    local size = imgui.GetFontSize();

    -- Already initialized
    if (font_baked ~= nil and font_atlas_tex_ptr ~= nil and math.abs(size - font_baked_size) < 0.1) then
        return true;
    end

    local font = imgui.GetFont();
    if (font == nil) then return false; end

    local atlas = font.ContainerAtlas;
    if (atlas == nil) then return false; end

    local tex_ref = atlas.TexRef;
    if (tex_ref == nil) then return false; end

    -- Try GetTexID method, fall back to _TexID field (matches mobhud)
    local tex_id_ok, tex_id = pcall(function() return tex_ref:GetTexID(); end);
    if (not tex_id_ok or tex_id == nil or tex_id == 0) then
        local raw_ok, raw_id = pcall(function() return tex_ref._TexID; end);
        if (raw_ok and raw_id ~= nil and raw_id ~= 0) then
            tex_id = raw_id;
        else
            font_init_fail_count = font_init_fail_count + 1;
            if (font_init_fail_count <= 1) then
                print('[zonelines] font atlas: GetTexID failed — may need game restart to recover');
            end
            return false;
        end
    end

    -- Get baked font data
    local baked = nil;

    -- Primary: imgui.GetFontBaked()
    local baked1_ok, baked1 = pcall(function() return imgui.GetFontBaked(); end);
    if (baked1_ok and baked1 ~= nil) then
        local g_ok, g = pcall(function() return baked1:FindGlyph(65); end);
        if (g_ok and g ~= nil) then
            local u_ok, u1 = pcall(function() return g.U1; end);
            if (u_ok and u1 ~= nil and u1 > 0) then
                baked = baked1;
            end
        end
    end

    -- Fallback: font.LastBaked
    if (baked == nil) then
        local lb_ok, lb = pcall(function() return font.LastBaked; end);
        if (lb_ok and lb ~= nil) then
            local g_ok, g = pcall(function() return lb:FindGlyph(65); end);
            if (g_ok and g ~= nil) then
                local u_ok, u1 = pcall(function() return g.U1; end);
                if (u_ok and u1 ~= nil and u1 > 0) then
                    baked = lb;
                end
            end
        end
    end

    if (baked == nil) then return false; end

    -- Re-read TexID (atlas texture may have changed after bake)
    local tex_id2_ok, tex_id2 = pcall(function() return tex_ref:GetTexID(); end);
    if (tex_id2_ok and tex_id2 ~= nil and tex_id2 ~= 0) then
        tex_id = tex_id2;
    end

    -- Cast ImGui texture ID to D3D8 pointer
    local base_ok, base_ptr = pcall(function()
        return ffi.cast('IDirect3DBaseTexture8*', ffi.cast('uintptr_t', tex_id));
    end);
    if (not base_ok or base_ptr == nil) then return false; end

    font_atlas_tex_ptr = base_ptr;
    font_baked = baked;

    local sz_ok, sz = pcall(function() return baked.Size; end);
    font_baked_size = (sz_ok and sz and sz > 0) and sz or size;

    font_init_fail_count = 0;
    return true;
end

function renderer.is_font_atlas_ready()
    return font_atlas_tex_ptr ~= nil and font_baked ~= nil;
end

-------------------------------------------------------------------------------
-- D3D Text: Screen-space ortho text (pixel-perfect, matching mobhud approach)
-- Projects world position → screen coords, builds glyph quads in pixel space,
-- renders with ortho projection for depth-tested but pixel-crisp text.
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

-- Measure text width in screen pixels at given scale
local function measure_text_screen(text, scale)
    local width = 0;
    for i = 1, #text do
        local g = font_baked:FindGlyph(string.byte(text, i));
        if (g ~= nil) then
            width = width + g.AdvanceX * scale;
        end
    end
    return width;
end

-- Build screen-space glyph quads into text_verts buffer.
-- Returns vertex count. sx/sy = screen anchor, z = NDC depth, scale = pixel scale.
local function build_text_screen(text, color, sx, sy, z, scale)
    local vi = 0;
    local len = #text;
    if (len > MAX_TEXT_CHARS) then len = MAX_TEXT_CHARS; end
    local cursor_x = 0;

    for i = 1, len do
        local g = font_baked:FindGlyph(string.byte(text, i));
        if (g ~= nil) then
            if (g.X1 - g.X0 > 0 and g.Y1 - g.Y0 > 0) then
                local x0 = sx + cursor_x + g.X0 * scale;
                local y0 = sy + g.Y0 * scale;
                local x1 = sx + cursor_x + g.X1 * scale;
                local y1 = sy + g.Y1 * scale;

                -- Triangle 1: TL, TR, BL
                text_verts[vi].x = x0; text_verts[vi].y = y0; text_verts[vi].z = z;
                text_verts[vi].color = color; text_verts[vi].tu = g.U0; text_verts[vi].tv = g.V0;
                text_verts[vi+1].x = x1; text_verts[vi+1].y = y0; text_verts[vi+1].z = z;
                text_verts[vi+1].color = color; text_verts[vi+1].tu = g.U1; text_verts[vi+1].tv = g.V0;
                text_verts[vi+2].x = x0; text_verts[vi+2].y = y1; text_verts[vi+2].z = z;
                text_verts[vi+2].color = color; text_verts[vi+2].tu = g.U0; text_verts[vi+2].tv = g.V1;

                -- Triangle 2: TR, BR, BL
                text_verts[vi+3].x = x1; text_verts[vi+3].y = y0; text_verts[vi+3].z = z;
                text_verts[vi+3].color = color; text_verts[vi+3].tu = g.U1; text_verts[vi+3].tv = g.V0;
                text_verts[vi+4].x = x1; text_verts[vi+4].y = y1; text_verts[vi+4].z = z;
                text_verts[vi+4].color = color; text_verts[vi+4].tu = g.U1; text_verts[vi+4].tv = g.V1;
                text_verts[vi+5].x = x0; text_verts[vi+5].y = y1; text_verts[vi+5].z = z;
                text_verts[vi+5].color = color; text_verts[vi+5].tu = g.U0; text_verts[vi+5].tv = g.V1;

                vi = vi + 6;
            end
            cursor_x = cursor_x + g.AdvanceX * scale;
        end
    end
    return vi;
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

-- Sync tuning from settings each frame
local function apply_settings(s)
    if (s == nil) then return; end
    DOT_SPACING          = s.dot_spacing or 0.3;
    HOVER_HEIGHT         = s.hover_height or 0.5;
    MAX_GRADIENT         = s.rise_distance or 0.9;
    D3D_DOT_GLOW_SIZE    = (s.dot_size or 1.4) * 0.05;
    ZONELINE_OVERRIDES   = s.zoneline_overrides or {};
    rebuild_colors(s);
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
-- Compute curtain positions (shared rendering logic)
-- Returns: { positions = {{wx,wy,wz}, ...}, hover_y = number,
--            label_x = number, label_z = number }
--
-- Visual improvements over the original dot logic:
--   - Label positioned at player-facing edge center
--   - Full-span dots (no edge trimming)
--   - Centered mode for ground line style
--   - Height from terrain MAX (same as original working code)
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

    -- Push dots and label to the player-facing box edge.
    local depth_offset;
    if (along_x) then
        local sign = (local_z_comp >= 0) and 1 or -1;
        depth_offset = sign * depth_half;
    else
        local sign = (local_x_comp >= 0) and 1 or -1;
        depth_offset = sign * depth_half;
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

        -- Per-position terrain height via interpolation
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

    -- Smooth elevation: 3-pass moving average to remove jarring height changes.
    -- Each pass averages each dot with its neighbors, creating gentle curves.
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
    local h_offset = entry_ovr.height or 0;
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

    return { positions = positions, hover_y = label_hover_y, label_x = label_wx, label_z = label_wz };
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

        -- Center vertex
        circle_verts[vi].x = wx;
        circle_verts[vi].y = wy;
        circle_verts[vi].z = wz;
        circle_verts[vi].color = color_argb;
        vi = vi + 1;

        -- Edge vertex 1
        circle_verts[vi].x = wx + math.cos(a1) * radius;
        circle_verts[vi].y = wy;
        circle_verts[vi].z = wz + math.sin(a1) * radius;
        circle_verts[vi].color = color_argb;
        vi = vi + 1;

        -- Edge vertex 2
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

local function draw_d3d_style_dots(device, cdata, rx, ry, rz, ux, uy, uz, core_col, glow_col)
    for _, p in ipairs(cdata.positions) do
        draw_d3d_dot_gradient(device, rx, ry, rz, ux, uy, uz,
            p.wx, p.wy, p.wz, D3D_DOT_GLOW_SIZE, core_col, glow_col);
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

function renderer.draw_d3d(zone_lines, player_x, player_y, player_z, s)
    if (zone_lines == nil or #zone_lines == 0) then return; end

    local view = renderer.cached_view;
    if (view == nil) then return; end

    local device = d3d8.get_device();
    if (device == nil) then return; end

    apply_settings(s);

    -- Extract camera right/up vectors from view matrix for billboard orientation
    local ok, rx, ry, rz, ux, uy, uz = pcall(function()
        return view._11, view._21, view._31, view._12, view._22, view._32;
    end);
    if (not ok or type(rx) ~= 'number' or type(uy) ~= 'number') then return; end

    -- Normalize
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
    local _, save_fvf      = device:GetVertexShader();
    local _, save_tex      = device:GetTexture(0);
    local _, save_ps       = device:GetPixelShader();
    local _, save_world    = device:GetTransform(D3DTS_WORLD);
    local _, save_view_t   = device:GetTransform(2);  -- D3DTS_VIEW
    local _, save_proj_t   = device:GetTransform(3);  -- D3DTS_PROJECTION
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

        -- ── Pass 1: Untextured colored markers (dots + circles) ──

        for _, zl in ipairs(zone_lines) do
            local dist = distance_xz(player_x, player_z, zl.x, zl.z);

            -- Cache override lookup once per zone line
            local rect_key = tostring(zl.rect_id);
            local ovr = ZONELINE_OVERRIDES[rect_key] or {};
            if (dist <= render_dist and not ovr.hide) then
                local label_y = zl.y;
                local label_x = zl.x;
                local label_z = zl.z;
                -- Display distance measures to nearest box edge, not center
                local display_dist = distance_to_zoneline(player_x, player_z, zl);

                if (is_curtain_zoneline(zl)) then
                    -- Curtain zone line: compute dot positions along the wider edge
                    local core_col, glow_col = get_d3d_dot_colors(display_dist);
                    local zl_trim = ovr.trim or 0;
                    local cdata = compute_curtain_positions(zl.x, zl.y, zl.z,
                        zl.sx / 2, zl.sy / 2, zl.sz / 2,
                        zl.ry or 0, player_x, player_z, zl.terrain_heights, zl.rect_id, zl_trim);
                    label_y = cdata.hover_y;
                    label_x = cdata.label_x;
                    label_z = cdata.label_z;
                    draw_d3d_style_dots(device, cdata, rx, ry, rz, ux, uy, uz, core_col, glow_col);
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
                    draw_d3d_circle(device, zl.x, zl.y, zl.z, r, fill_col);

                    -- Draw vertical pole from circle center up to label height
                    local pole_h = (type(ovr.pole_height) == 'number' and ovr.pole_height > 0)
                        and ovr.pole_height or 4.0;
                    local core_col = get_d3d_dot_colors(display_dist);
                    draw_d3d_pole(device, zl.x, zl.y, zl.z, pole_h, rx, ry, rz, core_col);
                    label_y = zl.y - pole_h;  -- move label to top of pole
                end

                -- Collect labels for text pass (name on top, distance below)
                if (want_labels or want_dist) then
                    local text_y = label_y - renderer.d3d_label_offset;
                    if (want_labels) then
                        local name = zl.display_name;
                        if (name == nil or name == '') then name = 'Zone Line'; end
                        frame_labels_n = frame_labels_n + 1;
                        local lbl = frame_labels[frame_labels_n];
                        if (lbl == nil) then lbl = {}; frame_labels[frame_labels_n] = lbl; end
                        lbl.x = label_x; lbl.y = text_y; lbl.z = label_z;
                        lbl.text = name; lbl.dist = display_dist;
                    end
                    if (want_dist) then
                        local dist_y = text_y + (want_labels and 0.4 or 0);
                        frame_labels_n = frame_labels_n + 1;
                        local lbl = frame_labels[frame_labels_n];
                        if (lbl == nil) then lbl = {}; frame_labels[frame_labels_n] = lbl; end
                        lbl.x = label_x; lbl.y = dist_y; lbl.z = label_z;
                        lbl.text = string.format('%.0fy', display_dist); lbl.dist = display_dist;
                    end
                end
            end
        end

        -- ── Pass 2: Screen-space text labels (ortho projection, pixel-perfect) ──

        local vp_w = renderer.cached_vp_w;
        local vp_h = renderer.cached_vp_h;
        local cached_proj = renderer.cached_proj;

        if (frame_labels_n > 0 and font_baked ~= nil and font_atlas_tex_ptr ~= nil
            and vp_w > 0 and vp_h > 0 and cached_proj ~= nil) then

            -- Use device's current view (this frame's camera) + cached proj from d3d_present
            -- (stable main-pass FOV — device proj at beginscene may be from shadow/UI pass)
            local _, cur_view = device:GetTransform(2);
            if (cur_view ~= nil) then

                -- Switch to textured vertex format
                device:SetTexture(0, font_atlas_tex_ptr);
                device:SetVertexShader(D3DFVF_XYZ_DIFFUSE_TEX1);

                -- Texture stage: color from vertex (flat text), alpha from texture (glyph shape)
                device:SetTextureStageState(0, D3DTSS_COLOROP, 2);    -- SELECTARG1
                device:SetTextureStageState(0, D3DTSS_COLORARG1, 0);  -- DIFFUSE
                device:SetTextureStageState(0, D3DTSS_ALPHAOP, 2);    -- SELECTARG1
                device:SetTextureStageState(0, D3DTSS_ALPHAARG1, 2);  -- TEXTURE

                -- LINEAR filtering
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
                device:SetRenderState(D3DRS_ALPHAREF, 0x40);
                device:SetRenderState(D3DRS_ALPHAFUNC, D3DCMP_GREATEREQUAL);

                -- Set up ortho projection: screen pixels map 1:1, Z passes through for depth
                device:SetTransform(D3DTS_WORLD, identity_matrix);
                device:SetTransform(2, identity_matrix);  -- view = identity

                -- Rebuild ortho each frame (viewport size may change)
                ffi.fill(ortho_matrix, ffi.sizeof('D3DMATRIX'), 0);
                ortho_matrix._11 =  2.0 / vp_w;    -- X: [0,w] → [-1,1]
                ortho_matrix._22 = -2.0 / vp_h;    -- Y: [0,h] → [1,-1] (flip Y)
                ortho_matrix._33 =  1.0;            -- Z: pass through
                ortho_matrix._44 =  1.0;
                ortho_matrix._41 = -1.0;            -- X offset: pixel 0 → clip -1
                ortho_matrix._42 =  1.0;            -- Y offset: pixel 0 → clip +1
                device:SetTransform(3, ortho_matrix);  -- projection = ortho

                local ref_dist = 30.0;  -- distance where text is at base scale
                local min_s = renderer.d3d_text_min_scale;
                local max_s = renderer.d3d_text_max_scale;
                local base_s = text_scale;

                for li = 1, frame_labels_n do
                    local lbl = frame_labels[li];
                    if (lbl.x ~= nil and lbl.y ~= nil and lbl.z ~= nil
                        and lbl.dist ~= nil and lbl.text ~= nil) then
                        local lok, _ = pcall(function()
                            if (cur_view == nil or cached_proj == nil) then return; end
                            local r1, r2, r3, r4 = project_with_z(
                                cur_view, cached_proj, vp_w, vp_h,
                                lbl.x, lbl.y, lbl.z);
                            local sx = tonumber(r1);
                            local sy = tonumber(r2);
                            local ndcz = tonumber(r4);
                            if (r3 ~= true or sx == nil or sy == nil or ndcz == nil) then return; end

                            local dist_factor = ref_dist / math.max(lbl.dist, 1.0);
                            dist_factor = math.max(min_s, math.min(max_s, dist_factor));
                            local fs = base_s * dist_factor;

                            local tw = measure_text_screen(lbl.text, fs);
                            local cx = -tw / 2;

                            -- Main text (no shadow)
                            local mv = build_text_screen(lbl.text, D3D_TEXT_WHITE,
                                sx, sy, ndcz, fs);
                            if (mv > 0) then
                                for j = 0, mv - 1 do
                                    text_verts[j].x = text_verts[j].x + cx;
                                end
                                device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, mv / 3, text_verts, TEXTURED_VERTEX_SIZE);
                            end
                        end);
                    end
                end
            end
        end
    end);

    -- ══ ALWAYS restore render states (even if drawing errored out) ══
    if (save_world ~= nil) then device:SetTransform(D3DTS_WORLD, save_world); end
    if (save_view_t ~= nil) then device:SetTransform(2, save_view_t); end
    if (save_proj_t ~= nil) then device:SetTransform(3, save_proj_t); end
    device:SetTexture(0, save_tex);
    device:SetRenderState(D3DRS_LIGHTING, save_light);
    device:SetRenderState(D3DRS_ZENABLE, save_zenable);
    device:SetRenderState(D3DRS_ZWRITEENABLE, save_zwrite);
    device:SetRenderState(D3DRS_ZFUNC, save_zfunc);
    device:SetRenderState(D3DRS_ZBIAS, save_zbias);
    device:SetRenderState(D3DRS_ALPHABLENDENABLE, save_ablend);
    device:SetRenderState(D3DRS_SRCBLEND, save_srcblend);
    device:SetRenderState(D3DRS_DESTBLEND, save_dstblend);
    device:SetRenderState(D3DRS_CULLMODE, save_cull);
    device:SetRenderState(D3DRS_ALPHATESTENABLE, save_atest);
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

    -- Log drawing errors (previously silently swallowed by outer pcall)
    if (not draw_ok) then
        if (not renderer._draw_err_logged) then
            print(chat.header('zonelines') .. chat.error('draw_d3d error: ' .. tostring(draw_err)));
            renderer._draw_err_logged = true;
        end
    else
        renderer._draw_err_logged = false;
    end
end



-------------------------------------------------------------------------------
-- render: Called from d3d_present — syncs settings and initializes font atlas.
-- Marker drawing happens in draw_d3d (d3d_beginscene).
-------------------------------------------------------------------------------

function renderer.render(zone_lines, player_x, player_y, player_z, s)
    if (zone_lines == nil or #zone_lines == 0) then return; end

    -- Initialize font atlas for D3D text (uses default ImGui font)
    if (renderer.hide_behind_walls and not renderer.is_font_atlas_ready()) then
        pcall(renderer.init_font_atlas);
    end
end

return renderer;
