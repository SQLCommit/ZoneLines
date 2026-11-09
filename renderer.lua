-- Zone line markers and labels.

require 'common';

local ffi   = require 'ffi';
local d3d8  = require 'd3d8';
local chat  = require 'chat';
local data  = require 'data';
local docks = require 'docks';
local crests = require 'crests';

local renderer = {};

-- D3D8 FFI types and constants.

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

local effects = require 'effects';
local textures = require 'textures';
local signs   = require 'signs';
local transport = require 'transport';

local D3DPT_TRIANGLELIST = 4;

local D3DFVF_XYZ_DIFFUSE      = 0x042;  -- XYZ + DIFFUSE
local D3DFVF_XYZ_DIFFUSE_TEX1 = 0x142;  -- XYZ + DIFFUSE + TEX1
local VERTEX_SIZE              = 16;     -- Vertex bytes.
local TEXTURED_VERTEX_SIZE     = 24;     -- Textured vertex bytes.

local D3DRS_ZENABLE          = 7;
local D3DRS_ZWRITEENABLE     = 14;   -- Depth writes.
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

local D3DCMP_LESSEQUAL    = 4;
local D3DCMP_GREATEREQUAL = 7;

local D3DTSS_COLOROP   = 1;
local D3DTSS_COLORARG1 = 2;
local D3DTSS_COLORARG2 = 3;
local D3DTSS_ALPHAOP   = 4;
local D3DTSS_ALPHAARG1 = 5;
local D3DTSS_ALPHAARG2 = 6;
local D3DTSS_ADDRESSU  = 13;
local D3DTSS_ADDRESSV  = 14;
local D3DTSS_MAGFILTER = 16;
local D3DTSS_MINFILTER = 17;

local D3DTOP_DISABLE     = 1;
local D3DTEXF_LINEAR     = 2;
local D3DTADDRESS_CLAMP  = 3;

local D3DTS_WORLD = 256;

local DOT_CIRCLE_SEGS = 12;
local MAX_BATCH_DOTS = 512;
local d3d_verts    = ffi.new('zl_d3d_vertex_t[?]', DOT_CIRCLE_SEGS * 3 * MAX_BATCH_DOTS);  -- All dots of a run.
local batch_n = 0;
local CIRCLE_SEGS  = 16;
local circle_verts = ffi.new('zl_d3d_vertex_t[?]', CIRCLE_SEGS * 3);  -- Triangle fan.

local pole_verts = ffi.new('zl_d3d_vertex_t[?]', 6);

local text_verts = ffi.new('zl_d3d_textured_vertex_t[?]', 6);

local identity_matrix = ffi.new('D3DMATRIX');
identity_matrix._11 = 1; identity_matrix._22 = 1; identity_matrix._33 = 1; identity_matrix._44 = 1;
local ortho_matrix  = ffi.new('D3DMATRIX');
local restore_world = ffi.new('D3DMATRIX');
local restore_view  = ffi.new('D3DMATRIX');
local restore_proj  = ffi.new('D3DMATRIX');
local fresh_view    = ffi.new('D3DMATRIX');
local cached_view   = ffi.new('D3DMATRIX');
local cached_proj   = ffi.new('D3DMATRIX');
local out_dw   = ffi.new('DWORD[1]');
local out_vp   = ffi.new('D3DVIEWPORT8[1]');
local out_tex  = ffi.new('IDirect3DBaseTexture8*[1]');

-- Vtable getters, nil on failure.
local function get_rs(d, k)
    if (d.lpVtbl.GetRenderState(d, k, out_dw) ~= 0) then return nil; end
    return out_dw[0];
end
local function get_tss(d, stage, k)
    if (d.lpVtbl.GetTextureStageState(d, stage, k, out_dw) ~= 0) then return nil; end
    return out_dw[0];
end

renderer.d3d_pass          = 0;
renderer.have_view         = false;
renderer.have_proj         = false;
renderer.cached_vp_w       = 0;
renderer.cached_vp_h       = 0;
-- Placeholders until sync.
local SYNC_FIELDS = {   -- Field, setting key, flag.
    { 'd3d_text_scale', 'd3d_text_scale' }, { 'd3d_label_offset', 'd3d_label_offset' },
    { 'd3d_text_min_scale', 'd3d_text_min_scale' }, { 'd3d_text_max_scale', 'd3d_text_max_scale' },
    { 'gdi_font_family', 'd3d_font_family' }, { 'gdi_outline_width', 'd3d_outline_width' },
    { 'gdi_bold', 'd3d_bold', true }, { 'd3d_show_labels', 'd3d_show_labels', true },
    { 'd3d_show_distance', 'd3d_show_distance', true }, { 'd3d_dist_position', 'd3d_dist_position' },
    { 'd3d_label_spacing', 'd3d_label_spacing' }, { 'dot_glow_enabled', 'dot_glow_enabled', true },
    { 'dot_glow_speed', 'dot_glow_speed' }, { 'dot_glow_intensity', 'dot_glow_intensity' },
    { 'dot_glow_min', 'dot_glow_min' }, { 'dot_glow_max', 'dot_glow_max' },
    { 'd3d_labels_fixed', 'd3d_labels_fixed' },
};
for _, f in ipairs(SYNC_FIELDS) do renderer[f[1]] = f[3] and false or 0; end
renderer.d3d_dist_position = 'bottom';
renderer.gdi_font_family = 'Arial';

-- Label and glow settings.
function renderer.sync(s, d)
    for _, f in ipairs(SYNC_FIELDS) do
        local v = s[f[2]];
        if (f[3]) then
            renderer[f[1]] = (v ~= false);
        else
            if (v == nil) then v = d[f[2]]; end
            renderer[f[1]] = v;
        end
    end
    effects.sync(s);
    signs.sync(s);
end

-- World position to screen.

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

local DOT_SPACING    = 0.3;    -- Dot spacing, yalms.
local MAX_DOTS       = 500;    -- Cap per line.
local HOVER_HEIGHT   = 0.5;    -- Height above ground.
local MAX_GRADIENT   = 0.9;    -- Max height change per dot.

-- Overrides by rect id.
local ZONELINE_OVERRIDES = {};

-- Rim glow alpha gain.
local GLOW_GAIN = 0.625;

local D3D_DOT_GLOW_SIZE = 0.35;

local DISTANCE_FADE      = false;
local DISTANCE_FADE_ZONE = 0.3;

local frame_labels = {};
local frame_labels_n = 0;

-- RGB floats to ARGB.
local function rgb_to_argb(rgb, alpha)
    local r = math.floor((rgb[1] or 0) * 255 + 0.5);
    local g = math.floor((rgb[2] or 0) * 255 + 0.5);
    local b = math.floor((rgb[3] or 0) * 255 + 0.5);
    if (r > 255) then r = 255; elseif (r < 0) then r = 0; end
    if (g > 255) then g = 255; elseif (g < 0) then g = 0; end
    if (b > 255) then b = 255; elseif (b < 0) then b = 0; end
    return alpha * 0x1000000 + r * 0x10000 + g * 0x100 + b;
end

local USE_DIST_COLORS  = false;
local D3D_CORE_MAIN    = 0xCC00FF00;
local D3D_GLOW_MAIN    = 0x4000FF00;
local D3D_CIRCLE_MAIN  = 0x2200FF00;
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

    local main = s.dot_color or { 0, 1, 0 };
    D3D_CORE_MAIN   = rgb_to_argb(main, core_a);
    D3D_GLOW_MAIN   = rgb_to_argb(main, glow_a);
    D3D_CIRCLE_MAIN = rgb_to_argb(main, 0x22);

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

-- Sync tuning from settings.
local settings_applied = false;
local overrides_stale = true;     -- Overrides need rebuild.
local settings_rev = 0;           -- Geometry revision.
local curtain_cache = {};         -- Curtain cache by rect id.
local function apply_settings(s)
    if (s == nil) then return; end
    local spacing  = s.dot_spacing or 0.3;
    local hover    = s.hover_height or 0.5;
    local gradient = s.rise_distance or 0.9;
    local geometry = (spacing ~= DOT_SPACING or hover ~= HOVER_HEIGHT or gradient ~= MAX_GRADIENT);
    DOT_SPACING          = spacing;
    HOVER_HEIGHT         = hover;
    MAX_GRADIENT         = gradient;
    D3D_DOT_GLOW_SIZE    = (s.dot_size or 1.4) * 0.05;
    if (overrides_stale) then
        ZONELINE_OVERRIDES = data.effective_overrides(s.zoneline_overrides);
        overrides_stale = false;
        geometry = true;
    end
    DISTANCE_FADE        = (s.distance_fade == true);
    DISTANCE_FADE_ZONE   = s.distance_fade_zone or 0.3;
    rebuild_colors(s);
    if (geometry) then settings_rev = settings_rev + 1; end
    settings_applied = true;
end

-- Settings changed; mark dirty.
function renderer.mark_settings_dirty(overrides_changed)
    settings_applied = false;
    if (overrides_changed) then overrides_stale = true; end
end

-- Clear cache on zone change.
function renderer.invalidate_curtain_cache()
    curtain_cache = {};
    effects.reset_zone();
    renderer.clear_zone_text();
end

local function distance_xz(x1, z1, x2, z2)
    local dx = x1 - x2;
    local dz = z1 - z2;
    return math.sqrt(dx * dx + dz * dz);
end

-- Distance to trigger edge.
local function distance_to_zoneline(px, pz, zl)
    if (zl.sx == nil or zl.sz == nil or zl.sx <= 0 or zl.sz <= 0) then
        return distance_xz(px, pz, zl.x, zl.z);
    end

    local cos_r = zl.cr;
    local sin_r = zl.sr;
    local half_sx = zl.sx / 2;
    local half_sz = zl.sz / 2;

    local dx = px - zl.x;
    local dz = pz - zl.z;
    local lx =  dx * cos_r + dz * sin_r;
    local lz = -dx * sin_r + dz * cos_r;

    local cx = math.max(-half_sx, math.min(half_sx, lx));
    local cz = math.max(-half_sz, math.min(half_sz, lz));

    local dlx = lx - cx;
    local dlz = lz - cz;
    return math.sqrt(dlx * dlx + dlz * dlz);
end

-- Curtain dots along the edge.

local EMPTY_OVR = {};

local function compute_curtain_positions(wx, wy, wz, half_sx, half_sy, half_sz,
                                          cos_r, sin_r, player_x, player_z, terrain_heights, rect_id, entry_ovr)

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

    local dx = player_x - wx;
    local dz = player_z - wz;
    local local_x_comp =  dx * cos_r + dz * sin_r;
    local local_z_comp = -dx * sin_r + dz * cos_r;

    local depth_sign;
    if (along_x) then
        depth_sign = (local_z_comp >= 0) and 1 or -1;
    else
        depth_sign = (local_x_comp >= 0) and 1 or -1;
    end
    local depth_offset = depth_sign * depth_half;

    -- Cache by rect and settings.
    if (rect_id ~= nil) then
        local c = curtain_cache[rect_id];
        if (c ~= nil and c.sign == depth_sign and c.rev == settings_rev) then
            return c.data;
        end
    end

    local wall_len = wall_half * 2;
    local num_dots = math.max(2, math.floor(wall_len / DOT_SPACING) + 1);
    if (num_dots > MAX_DOTS) then num_dots = MAX_DOTS; end

    local synth_ground = wy + half_sy - 2;

    local th = nil;
    local th_adj = 0;
    if (terrain_heights ~= nil) then
        if (terrain_heights.pos_heights ~= nil) then
            if (depth_offset >= 0) then
                th = terrain_heights.pos_heights;
            else
                th = terrain_heights.neg_heights or terrain_heights.pos_heights;
            end
            th_adj = 0;
        else
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

    -- Edge trimming.
    local trim_yalms = (type(entry_ovr.trim) == 'number' and entry_ovr.trim) or 0;
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

    local px, py, pz = {}, {}, {};
    local n = 0;
    local label_hover_y = synth_ground - HOVER_HEIGHT;  -- Label fallback height.

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
            local th_t = t * (th_n - 1);      -- 0-based terrain position.
            local lo = math.floor(th_t) + 1;   -- 1-based Lua index.
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

        if (pos_y == nil and th_n < 2) then
            pos_y = synth_ground - HOVER_HEIGHT;
        end

        if (pos_y ~= nil) then
            n = n + 1;
            px[n] = wx + wrx;
            py[n] = pos_y;
            pz[n] = wz + wrz;
        end
    end

    -- Auto-flatten flat terrain.
    if (n >= 2) then
        local min_y, max_y = py[1], py[1];
        for i = 2, n do
            if (py[i] < min_y) then min_y = py[i]; end
            if (py[i] > max_y) then max_y = py[i]; end
        end
        local variance = max_y - min_y;  -- Height span.
        if (variance < 1.5) then
            local mid_y = min_y + (max_y - min_y) / 2;
            for i = 1, n do py[i] = mid_y; end
        end
    end

    if (n >= 3) then
        for pass = 1, 3 do
            local prev_y = py[1];
            for i = 2, n - 1 do
                local curr = py[i];
                local next_y = py[i + 1];
                local smoothed = prev_y * 0.25 + curr * 0.5 + next_y * 0.25;
                prev_y = curr;
                py[i] = smoothed;
            end
        end
    end

    local entry_gradient = MAX_GRADIENT;
    if (type(entry_ovr.flatten) == 'number' and entry_ovr.flatten > 0) then
        entry_gradient = entry_ovr.flatten;
    end

    -- Flatten steep or off-center.
    if (n >= 3) then
        local center = math.floor(n / 2) + 1;
        local BLEND_DOTS = 6;
        local grad_threshold = entry_gradient * DOT_SPACING;  -- Per-dot threshold.
        local max_deviation = entry_gradient * 3;  -- Max yalms from center.
        local center_y = py[center];

        for i = center + 1, n do
            local per_dot = math.abs(py[i] - py[i - 1]);
            local from_center = math.abs(py[i] - center_y);
            if (per_dot > grad_threshold or from_center > max_deviation) then
                local flat_y = py[i - 1];
                local blend_start = math.max(center + 1, i - BLEND_DOTS);
                for j = blend_start, i - 1 do
                    local t = (j - blend_start) / math.max(1, i - 1 - blend_start);
                    py[j] = py[j] + (flat_y - py[j]) * t * t;
                end
                for j = i, n do
                    py[j] = flat_y;
                end
                break;
            end
        end

        for i = center - 1, 1, -1 do
            local per_dot = math.abs(py[i] - py[i + 1]);
            local from_center = math.abs(py[i] - center_y);
            if (per_dot > grad_threshold or from_center > max_deviation) then
                local flat_y = py[i + 1];
                local blend_end = math.min(center - 1, i + BLEND_DOTS);
                for j = blend_end, i + 1, -1 do
                    local t = (blend_end - j) / math.max(1, blend_end - i - 1);
                    py[j] = py[j] + (flat_y - py[j]) * t * t;
                end
                for j = i, 1, -1 do
                    py[j] = flat_y;
                end
                break;
            end
        end
    end

    -- Per-line height override.
    local h_offset = (type(entry_ovr.height) == 'number' and entry_ovr.height) or 0;
    if (h_offset ~= 0) then
        for i = 1, n do
            py[i] = py[i] - h_offset;
        end
    end

    if (n >= 1) then
        local mid = math.floor(n / 2) + 1;
        label_hover_y = py[math.min(mid, n)];
    end

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

    local result = { n = n, px = px, py = py, pz = pz, hover_y = label_hover_y, label_x = label_wx, label_z = label_wz };
    if (rect_id ~= nil) then
        curtain_cache[rect_id] = { sign = depth_sign, rev = settings_rev, data = result };
    end
    return result;
end

local function curtain_shape(zl)
    local has_box = (zl.sx ~= nil and zl.sx > 0 and zl.sz ~= nil and zl.sz > 0);
    local is_box_source = (zl.source == 'dat' or zl.source == 'trigger' or zl.kind == 'dock');
    -- Square boxes are area triggers.
    local is_square = has_box and (math.min(zl.sx, zl.sz) / math.max(zl.sx, zl.sz) > 0.6)
                      and math.max(zl.sx, zl.sz) > 20;
    return is_box_source and has_box and not is_square and zl.shape ~= 'circle';
end

local function is_curtain_zoneline(zl)
    return curtain_shape(zl) and zl.terrain_heights ~= nil;
end

renderer.curtain_shape = curtain_shape;


-- Gradient fan dot, batched.
local DOT_ANGLE_STEP = (2 * math.pi) / DOT_CIRCLE_SEGS;
local DCOS, DSIN = {}, {};
for i = 0, DOT_CIRCLE_SEGS do DCOS[i] = math.cos(i * DOT_ANGLE_STEP); DSIN[i] = math.sin(i * DOT_ANGLE_STEP); end

local function flush_dots(device)
    if (batch_n > 0) then
        device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, DOT_CIRCLE_SEGS * batch_n, d3d_verts, VERTEX_SIZE);
        batch_n = 0;
    end
end

local function add_dot(device, rx, ry, rz, ux, uy, uz, wx, wy, wz, size, core_col, glow_col)
    if (batch_n >= MAX_BATCH_DOTS) then flush_dots(device); end
    local vi = batch_n * DOT_CIRCLE_SEGS * 3;
    for i = 0, DOT_CIRCLE_SEGS - 1 do
        local cos1 = DCOS[i]; local sin1 = DSIN[i];
        local cos2 = DCOS[i + 1]; local sin2 = DSIN[i + 1];

        d3d_verts[vi].x = wx; d3d_verts[vi].y = wy; d3d_verts[vi].z = wz;
        d3d_verts[vi].color = core_col; vi = vi + 1;

        d3d_verts[vi].x = wx + (rx * cos1 + ux * sin1) * size;
        d3d_verts[vi].y = wy + (ry * cos1 + uy * sin1) * size;
        d3d_verts[vi].z = wz + (rz * cos1 + uz * sin1) * size;
        d3d_verts[vi].color = glow_col; vi = vi + 1;

        d3d_verts[vi].x = wx + (rx * cos2 + ux * sin2) * size;
        d3d_verts[vi].y = wy + (ry * cos2 + uy * sin2) * size;
        d3d_verts[vi].z = wz + (rz * cos2 + uz * sin2) * size;
        d3d_verts[vi].color = glow_col; vi = vi + 1;
    end
    batch_n = batch_n + 1;
end

local CCOS, CSIN = {}, {};
for i = 0, CIRCLE_SEGS do
    CCOS[i] = math.cos(i * ((2 * math.pi) / CIRCLE_SEGS));
    CSIN[i] = math.sin(i * ((2 * math.pi) / CIRCLE_SEGS));
end

local function draw_d3d_circle(device, wx, wy, wz, radius, color_argb)
    local vi = 0;

    for i = 0, CIRCLE_SEGS - 1 do

        circle_verts[vi].x = wx;
        circle_verts[vi].y = wy;
        circle_verts[vi].z = wz;
        circle_verts[vi].color = color_argb;
        vi = vi + 1;

        circle_verts[vi].x = wx + CCOS[i] * radius;
        circle_verts[vi].y = wy;
        circle_verts[vi].z = wz + CSIN[i] * radius;
        circle_verts[vi].color = color_argb;
        vi = vi + 1;

        circle_verts[vi].x = wx + CCOS[i + 1] * radius;
        circle_verts[vi].y = wy;
        circle_verts[vi].z = wz + CSIN[i + 1] * radius;
        circle_verts[vi].color = color_argb;
        vi = vi + 1;
    end

    device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, CIRCLE_SEGS, circle_verts, VERTEX_SIZE);
end

local POLE_HALF_WIDTH = 0.04;  -- Half-width, yalms.

-- NPC gem marker.
local GEM_W, GEM_H = 0.1, 0.17;                -- Half width and height.
local npc_verts = ffi.new('zl_d3d_vertex_t[?]', 24);
local npc_n = 0;

local function npc_tri(x0, y0, z0, c0, x1, y1, z1, c1, x2, y2, z2, c2)
    local v, i = npc_verts, npc_n;
    v[i].x, v[i].y, v[i].z, v[i].color = x0, y0, z0, c0;
    v[i + 1].x, v[i + 1].y, v[i + 1].z, v[i + 1].color = x1, y1, z1, c1;
    v[i + 2].x, v[i + 2].y, v[i + 2].z, v[i + 2].color = x2, y2, z2, c2;
    npc_n = i + 3;
end

-- Opaque shaded colour.
local function npc_shade(r, g, b, k, w)
    w = w or 0;
    r, g, b = (r + (255 - r) * w) * k, (g + (255 - g) * w) * k, (b + (255 - b) * w) * k;
    return 0xFF000000 + math.floor(r) * 0x10000 + math.floor(g) * 0x100 + math.floor(b);
end

-- Draws gem; returns label point.
local function draw_npc_gem(device, wx, cy, wz, rx, ry, rz, ux, uy, uz, core, now, seed, fade)
    npc_n = 0;
    local t = now + (seed * 0.618) % 1 * 6.0;
    local top = cy - GEM_H * fade - 0.05;                 -- Label anchor.
    cy = cy - 0.05 * math.sin(t * 2.0);                   -- Bob.
    local turn = math.cos(t * 1.4);                       -- Spin.
    local w = GEM_W * (0.3 + 0.7 * math.abs(turn)) * fade;
    local h = GEM_H * fade;
    local r, g, b = math.floor(core / 0x10000) % 256, math.floor(core / 0x100) % 256, core % 256;
    local lit = 0.5 + 0.5 * turn;                         -- Facet light.
    local mid = npc_shade(r, g, b, 1, 0.55);
    local left, right = npc_shade(r, g, b, 0.55 + 0.45 * lit), npc_shade(r, g, b, 1 - 0.45 * lit);
    local lx, lz, qx, qz = wx - rx * w, wz - rz * w, wx + rx * w, wz + rz * w;
    npc_tri(wx, cy, wz, mid, lx, cy, lz, left, wx, cy - h, wz, left);
    npc_tri(wx, cy, wz, mid, wx, cy + h, wz, left, lx, cy, lz, left);
    npc_tri(wx, cy, wz, mid, wx, cy - h, wz, right, qx, cy, qz, right);
    npc_tri(wx, cy, wz, mid, qx, cy, qz, right, wx, cy + h, wz, right);
    device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, npc_n / 3, npc_verts, VERTEX_SIZE);
    local breathe = 0.75 + 0.25 * math.sin(t * 2.6);
    effects.glow(device, wx, cy, wz, 0.42 * fade, core % 0x1000000, 0.45 * breathe, rx, ry, rz, ux, uy, uz);
    return top;
end

local function draw_d3d_pole(device, wx, wy, wz, height, rx, ry, rz, color_argb, ux, uy, uz, now, seed, fade)
    if (now ~= nil) then return draw_npc_gem(device, wx, wy, wz, rx, ry, rz, ux, uy, uz, color_argb, now, seed, fade); end
    local hw = POLE_HALF_WIDTH;
    local top_y = wy - height;  -- D3D Y up is negative.

    local bx1 = wx - rx * hw;
    local bz1 = wz - rz * hw;
    local bx2 = wx + rx * hw;
    local bz2 = wz + rz * hw;
    local tx1 = bx1;
    local tz1 = bz1;
    local tx2 = bx2;
    local tz2 = bz2;

    pole_verts[0].x = bx1; pole_verts[0].y = wy;    pole_verts[0].z = bz1; pole_verts[0].color = color_argb;
    pole_verts[1].x = bx2; pole_verts[1].y = wy;    pole_verts[1].z = bz2; pole_verts[1].color = color_argb;
    pole_verts[2].x = tx2; pole_verts[2].y = top_y;  pole_verts[2].z = tz2; pole_verts[2].color = color_argb;
    pole_verts[3].x = bx1; pole_verts[3].y = wy;    pole_verts[3].z = bz1; pole_verts[3].color = color_argb;
    pole_verts[4].x = tx2; pole_verts[4].y = top_y;  pole_verts[4].z = tz2; pole_verts[4].color = color_argb;
    pole_verts[5].x = tx1; pole_verts[5].y = top_y;  pole_verts[5].z = tz1; pole_verts[5].color = color_argb;

    device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, 2, pole_verts, VERTEX_SIZE);
end

local function draw_d3d_style_dots(device, cdata, rx, ry, rz, ux, uy, uz, core_col, glow_col, dot_size)
    local sz = dot_size or D3D_DOT_GLOW_SIZE;
    local px, py, pz = cdata.px, cdata.py, cdata.pz;
    for i = 1, cdata.n do
        add_dot(device, rx, ry, rz, ux, uy, uz, px[i], py[i], pz[i], sz, core_col, glow_col);
    end
end

-- Dots with per-dot style.
local function draw_fx_dots(device, cdata, rx, ry, rz, ux, uy, uz)
    local px, py, pz = cdata.px, cdata.py, cdata.pz;
    local fs, fc, fg = effects.fs, effects.fc, effects.fg;
    for i = 1, cdata.n do
        add_dot(device, rx, ry, rz, ux, uy, uz, px[i], py[i], pz[i], fs[i], fc[i], fg[i]);
    end
end

-- Draw in BeginScene pass 2.

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


-- Render GDI text quads.
local gdi = nil;
local gdi_tried = false;
local gdi_warned = false;

local function gdi_warn(text)
    if (gdi_warned) then return; end
    gdi_warned = true;
    print(chat.header('zonelines'):append(chat.error(text)));
end

local function ensure_gdi()
    if (gdi ~= nil or gdi_tried) then return gdi; end
    gdi_tried = true;
    local ok, lib = pcall(require, 'gdifonts.include');
    if (ok and lib ~= nil) then
        gdi = lib;
        pcall(function() gdi:set_auto_render(false); end);  -- Manual draw.
    else
        pcall(function() require('textures').log('gdifonts: ' .. tostring(lib)); end);
        gdi_warn('Labels are off: the GdiFonts text library failed to load (logs\\zonelines.log).');
    end
    return gdi;
end

-- Common fonts plus folder fonts.
local COMMON_FONTS = { 'Arial', 'Calibri', 'Segoe UI', 'Consolas', 'Verdana', 'Tahoma', 'Trebuchet MS', 'Times New Roman' };
renderer.font_list = COMMON_FONTS;     -- Rebuilt by scan_fonts.

-- Read font family name.
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
                if (pid == 3 or pid == 0) then       -- Windows UTF-16BE
                    local out = {};
                    for j = 1, #str, 2 do out[#out+1] = string.char(str:byte(j+1) or 32); end
                    best = table.concat(out);
                    if (pid == 3) then break; end
                elseif (pid == 1 and best == nil) then  -- Mac ASCII
                    best = str;
                end
            end
        end
        return best;
    end);
    return ok and fam or nil;
end

function renderer.scan_fonts()
    local list = {};
    for _, f in ipairs(COMMON_FONTS) do list[#list+1] = f; end

    -- Load folder fonts.
    local g = ensure_gdi();
    local function usable(name)
        if (g == nil) then return false; end
        local ok, r = pcall(function() return g:get_font_available(name); end);
        return (ok and r == true);
    end

    local dir, loaded = nil, 0;
    pcall(function() dir = addon.path:append('\\fonts\\'); end);
    if (dir == nil) then pcall(function() dir = addon.path .. '\\fonts\\'; end); end
    if (dir ~= nil) then
        local files = nil;
        pcall(function() files = ashita.fs.get_dir(dir, '.*', false); end);
        if (files ~= nil) then
            for _, fn in ipairs(files) do
                local lower = tostring(fn):lower();
                if (lower:match('%.ttf$') or lower:match('%.otf$')) then
                    local fam = nil;
                    if (g ~= nil) then pcall(function() fam = g:add_font(dir .. fn); end); end
                    if (fam ~= nil) then loaded = loaded + 1; end
                    if (fam == nil) then fam = ttf_family(dir .. fn); end
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
    pcall(function() require('textures').log('fonts: ' .. loaded .. ' loaded from the folder; listed ' .. table.concat(list, ', ', #COMMON_FONTS + 1)); end);
    return list;
end

local GDI_FONT_HEIGHT = 30;     -- Render height.
local gdi_cache = {};           -- Text cache, idle-dropped.
local gdi_perm = {};            -- Distance labels, kept.
local gdi_zone = {};            -- Zone-scoped names.
local gdi_free, gdi_free_n = {}, 0;   -- Idle label objects.
local GDI_FREE_MAX = 6;
local gdi_frame = 0;
local cache_family, cache_bold, cache_outline = nil, nil, nil;

local function gdi_get(text, perm)
    if (gdi == nil or text == nil or text == '') then return nil, nil; end
    local store = (perm == 'zone') and gdi_zone or perm and gdi_perm or gdi_cache;
    local e = store[text];
    if (e == nil and not perm and gdi_free_n > 0) then
        e = gdi_free[gdi_free_n];
        gdi_free[gdi_free_n] = nil;
        gdi_free_n = gdi_free_n - 1;
        e.obj:set_text(text);
        store[text] = e;
    end
    if (e == nil) then
        local ok, obj = pcall(gdi.create_object, gdi, {
            font_family   = renderer.gdi_font_family or 'Arial',
            font_height   = GDI_FONT_HEIGHT,
            font_flags    = (renderer.gdi_bold ~= false) and 1 or 0,
            font_color    = 0xFFFFFFFF,
            outline_color = 0xFF000000,
            outline_width = renderer.gdi_outline_width or 2,
            text          = text,
        }, true);
        if (not ok or obj == nil) then
            gdi_warn('Label text could not be created for font "' .. tostring(renderer.gdi_font_family) .. '". Try another font.');
            return nil, nil;
        end
        e = { obj = obj };
        store[text] = e;
    end
    e.frame = gdi_frame;
    local ok, tex, rect = pcall(e.obj.get_texture, e.obj);
    if (not ok) then return nil, nil; end
    return tex, rect;
end

-- Distance text per yalm.
local DIST_TEXT = { plain = {}, right = {}, left = {} };
local function dist_text(n, pos)
    local kind = (pos == 'right') and 'right' or (pos == 'left') and 'left' or 'plain';
    local t = DIST_TEXT[kind];
    local str = t[n];
    if (str == nil) then
        str = string.format('%dy', n);
        if (kind == 'right') then str = '- ' .. str; elseif (kind == 'left') then str = str .. ' -'; end
        t[n] = str;
    end
    return str;
end

local function gdi_evict()
    if (gdi == nil or gdi_frame % 30 ~= 0) then return; end
    for k, e in pairs(gdi_cache) do
        if (gdi_frame - (e.frame or 0) > 60) then
            gdi_cache[k] = nil;
            if (gdi_free_n < GDI_FREE_MAX) then
                gdi_free_n = gdi_free_n + 1;
                gdi_free[gdi_free_n] = e;
            else
                pcall(gdi.destroy_object, gdi, e.obj);
            end
        end
    end
end

-- Zone-scoped names.
function renderer.clear_zone_text()
    if (gdi == nil) then return; end
    for k, e in pairs(gdi_zone) do
        pcall(gdi.destroy_object, gdi, e.obj);
        gdi_zone[k] = nil;
    end
end

function renderer.cleanup_gdi()
    if (gdi == nil) then return; end
    for k, e in pairs(gdi_cache) do
        pcall(gdi.destroy_object, gdi, e.obj);
        gdi_cache[k] = nil;
    end
    for k, e in pairs(gdi_perm) do
        pcall(gdi.destroy_object, gdi, e.obj);
        gdi_perm[k] = nil;
    end
    renderer.clear_zone_text();
    for i = 1, gdi_free_n do
        pcall(gdi.destroy_object, gdi, gdi_free[i].obj);
        gdi_free[i] = nil;
    end
    gdi_free_n = 0;
end

-- Destroy FontManager on unload.
function renderer.shutdown_gdi()
    if (gdi == nil) then return; end
    renderer.cleanup_gdi();
    pcall(gdi.destroy_interface, gdi);
    gdi = nil;
end

-- Depth-tested label quad.
local function draw_label_tex(device, tex, w, h, x, y, z, tint)
    local x0 = math.floor(x + 0.5);
    local y0 = math.floor(y + 0.5);
    local x1 = x0 + math.floor(w + 0.5);
    local y1 = y0 + math.floor(h + 0.5);
    local col = tint or 0xFFFFFFFF;  -- White tint.
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

-- Fixed label plane.
local FIX = { on = false, ax = 0, ay = 0, az = 0, rx = 1, rz = 0, k = 0.02 };
local FIX_U = { 0, 1, 0, 1, 1, 0 };   -- Corner u per vertex.
local FIX_V = { 0, 0, 1, 0, 1, 1 };   -- Corner v per vertex.

-- One label texture.
local function put_label(device, tex, w, h, x, y, z, tint)
    if (not FIX.on) then return draw_label_tex(device, tex, w, h, x, y, z, tint); end
    local k, col, v = FIX.k, tint or 0xFFFFFFFF, text_verts;
    for i = 1, 6 do
        local u, t = x + w * FIX_U[i], y + h * FIX_V[i];
        local p = v[i - 1];
        p.x, p.y, p.z, p.color, p.tu, p.tv = FIX.ax + FIX.rx * u * k, FIX.ay + t * k, FIX.az + FIX.rz * u * k, col, FIX_U[i], FIX_V[i];
    end
    device:SetTexture(0, ffi.cast('IDirect3DBaseTexture8*', tex));
    device:DrawPrimitiveUP(D3DPT_TRIANGLELIST, 2, text_verts, TEXTURED_VERTEX_SIZE);
end

-- Rebuild cached labels.
local function gdi_font_check()
    if (renderer.gdi_font_family ~= cache_family or renderer.gdi_bold ~= cache_bold
        or renderer.gdi_outline_width ~= cache_outline) then
        renderer.cleanup_gdi();
        cache_family, cache_bold, cache_outline = renderer.gdi_font_family, renderer.gdi_bold, renderer.gdi_outline_width;
    end
end

-- Sign idle cache.
signs.text_source = function(text)
    if (gdi == nil and ensure_gdi() == nil) then return nil, nil; end
    gdi_font_check();
    return gdi_get(text);
end

local function draw_text_pass(device, view, text_scale)
    local vp_w = renderer.cached_vp_w;
    local vp_h = renderer.cached_vp_h;

    if (frame_labels_n <= 0 or vp_w <= 0 or vp_h <= 0 or not renderer.have_proj or view == nil) then
        return;
    end
    if (ensure_gdi() == nil) then return; end
    gdi_font_check();

    device:SetVertexShader(D3DFVF_XYZ_DIFFUSE_TEX1);

    device:SetTextureStageState(0, D3DTSS_COLOROP, 2);    -- SELECTARG1
    device:SetTextureStageState(0, D3DTSS_COLORARG1, 2);  -- TEXTURE
    device:SetTextureStageState(0, D3DTSS_ALPHAOP, 4);    -- MODULATE
    device:SetTextureStageState(0, D3DTSS_ALPHAARG1, 2);  -- TEXTURE
    device:SetTextureStageState(0, D3DTSS_ALPHAARG2, 0);  -- DIFFUSE

    device:SetTextureStageState(0, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
    device:SetTextureStageState(0, D3DTSS_MINFILTER, D3DTEXF_LINEAR);
    device:SetTextureStageState(0, D3DTSS_ADDRESSU, D3DTADDRESS_CLAMP);
    device:SetTextureStageState(0, D3DTSS_ADDRESSV, D3DTADDRESS_CLAMP);

    device:SetTexture(1, nil);
    device:SetTextureStageState(1, D3DTSS_COLOROP, D3DTOP_DISABLE);
    device:SetTextureStageState(1, D3DTSS_ALPHAOP, D3DTOP_DISABLE);

    device:SetRenderState(D3DRS_ALPHATESTENABLE, 1);
    device:SetRenderState(D3DRS_ALPHAREF, 0x80);   -- Cut alpha edge bleed.
    device:SetRenderState(D3DRS_ALPHAFUNC, D3DCMP_GREATEREQUAL);

    device:SetTransform(D3DTS_WORLD, identity_matrix);
    device:SetTransform(2, identity_matrix);  -- View identity.

    ffi.fill(ortho_matrix, ffi.sizeof('D3DMATRIX'), 0);
    ortho_matrix._11 =  2.0 / vp_w;    -- X: [0,w] -> [-1,1]
    ortho_matrix._22 = -2.0 / vp_h;    -- Y flipped.
    ortho_matrix._33 =  1.0;            -- Z: pass through
    ortho_matrix._44 =  1.0;
    ortho_matrix._41 = -1.0;            -- X offset.
    ortho_matrix._42 =  1.0;            -- Y offset.
    device:SetTransform(3, ortho_matrix);  -- Projection ortho.

    local fixed = (renderer.d3d_labels_fixed == true);
    FIX.on = false;
    if (fixed) then   -- World vertices.
        device:SetTransform(2, view);
        device:SetTransform(3, cached_proj);
    end
    local ref_dist = 30.0;  -- Base scale distance.
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
                if (fixed) then   -- World size layout.
                    local fx, fz = lbl.fx or 1, lbl.fz or 0;
                    local ex, _, eok = project_with_z(view, cached_proj, vp_w, vp_h, lbl.x + fx, lbl.y, lbl.z + fz);
                    if (eok and ex < sx) then fx, fz = -fx, -fz; end   -- Reads left to right.
                    FIX.on, FIX.ax, FIX.ay, FIX.az, FIX.rx, FIX.rz = true, lbl.x, lbl.y, lbl.z, fx, fz;
                    sx, sy, dist_factor = 0, 0, 1;
                end
                local fs = base_s * dist_factor;
                if (lbl.fade ~= nil and lbl.fade < 1.0) then
                    fs = fs * lbl.fade;
                end
                local q = fs * 14.0 / GDI_FONT_HEIGHT;
                local line_height = fs * 14;
                local dpos = renderer.d3d_dist_position or 'bottom';
                local spacing = renderer.d3d_label_spacing or 2;

                local draw_dist_text = nil;
                if (lbl.dist_n ~= nil) then draw_dist_text = dist_text(lbl.dist_n, dpos); end

                local name_tex, name_rect = nil, nil;
                local name_tw, name_th = 0, 0;
                if (lbl.name ~= nil) then
                    name_tex, name_rect = gdi_get(lbl.name);
                    if (name_rect ~= nil) then name_tw = name_rect.right * q; name_th = name_rect.bottom * q; end
                end
                local dist_tex, dist_rect = nil, nil;
                local dist_tw, dist_th = 0, 0;
                if (draw_dist_text ~= nil) then
                    dist_tex, dist_rect = gdi_get(draw_dist_text, true);
                    if (dist_rect ~= nil) then dist_tw = dist_rect.right * q; dist_th = dist_rect.bottom * q; end
                end

                local extra = lbl.lines_n or 0;   -- Schedule lines under name.
                local has_both = ((lbl.name ~= nil or extra > 0) and draw_dist_text ~= nil);

                local ny, nx;  -- Name position.
                local crest_w = 0;  -- Crest row width.
                local dx, dy;  -- Distance position.

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

                local first = (lbl.name ~= nil) and 1 or 0;   -- Lines take name row.
                if (extra > 0 and ny ~= nil) then
                    ny = ny - (extra - 1 + first) * line_height;
                    if (dpos ~= 'bottom' and dy ~= nil) then dy = dy - (extra - 1 + first) * line_height; end
                end

                if (name_tex ~= nil and ny ~= nil) then
                    nx = sx - name_tw / 2;
                    put_label(device, name_tex, name_tw, name_th, nx, ny, ndcz, lbl.tint);
                    if (lbl.crest ~= nil) then
                        local ctex = crests.get(lbl.crest);
                        if (ctex ~= nil) then
                            put_label(device, ctex, name_th, name_th, nx - name_th - spacing, ny, ndcz, lbl.tint);
                            crest_w = name_th + spacing;
                        end
                    end
                end

                if (extra > 0 and ny ~= nil) then
                    for k = 1, extra do
                        local ltex, lrect = gdi_get(lbl.lines[k]);
                        if (ltex ~= nil) then
                            local ltw = lrect.right * q;
                            put_label(device, ltex, ltw, lrect.bottom * q, sx - ltw / 2, ny + (k - 1 + first) * line_height, ndcz, lbl.tint);
                        end
                    end
                end

                if (dist_tex ~= nil and dy ~= nil) then
                    if (dpos == 'bottom' or dpos == 'top') then
                        dx = sx - dist_tw / 2;
                    elseif (dpos == 'right') then
                        dx = sx + name_tw / 2 + spacing;
                    elseif (dpos == 'left') then
                        dx = sx - name_tw / 2 - dist_tw - spacing - crest_w;
                    else
                        dx = sx - dist_tw / 2;
                    end
                    put_label(device, dist_tex, dist_tw, dist_th, dx, dy, ndcz, lbl.tint);
                end
            end
        end
    end
end

-- Arch signs for late draw.
local function queue_signs(zone_lines, player_x, player_z, s, view)
    local range = signs.C.range;
    for _, zl in ipairs(zone_lines) do
        local ovr = zl.sign and (ZONELINE_OVERRIDES[zl.key] or EMPTY_OVR);
        if (ovr and ovr.hide ~= true) then
            local d = distance_xz(player_x, player_z, zl.x, zl.z);
            if (d <= range) then
                local fade = 1.0;
                if (DISTANCE_FADE and DISTANCE_FADE_ZONE > 0.001) then
                    local near = range * (1.0 - DISTANCE_FADE_ZONE);
                    if (d > near) then fade = math.clamp((range - d) / (range - near), 0.0, 1.0); end
                end
                signs.queue(zl, os.time(), fade, view, ovr.height);
            end
        end
    end
end

-- Camera right and up.
local function draw_body(device, zone_lines, player_x, player_y, player_z, s, rx, ry, rz, ux, uy, uz, view)
    local render_dist  = s.render_distance or 100.0;
    local want_labels  = renderer.d3d_show_labels;
    local want_dist    = renderer.d3d_show_distance;
    local text_scale   = renderer.d3d_text_scale;

    frame_labels_n = 0;
    batch_n = 0;
    local now = os.clock();
    gdi_frame = gdi_frame + 1;
    queue_signs(zone_lines, player_x, player_z, s, view);
    local npc_off = (s.show_signs ~= false and s.sign_npcs ~= true);   -- Arch signs carry times.
    local dots_on = (s.show_dots ~= false);

    local glow_pulse = 1.0;
    local glow_size_mult = 1.0;
    if (renderer.dot_glow_enabled) then
        local t = math.sin(os.clock() * renderer.dot_glow_speed);  -- -1 to 1
        local gmin = renderer.dot_glow_min or 0.4;
        local gmax = renderer.dot_glow_max or 1.0;
        local mid = (gmin + gmax) / 2;
        local half = (gmax - gmin) / 2;
        glow_pulse = mid + half * t;                     -- Alpha oscillation.
        glow_size_mult = 1.0 - (1.0 - glow_pulse) * 0.3; -- Size breathing.
    end

    -- Untextured markers first.

    for _, zl in ipairs(zone_lines) do
        local ovr = ZONELINE_OVERRIDES[zl.key] or EMPTY_OVR;
        -- Nearest edge, not centre.
        local display_dist = distance_to_zoneline(player_x, player_z, zl);
        -- Other-floor telepads stay hidden.
        local off_floor = data.floor_entry(zl) and math.abs(player_y - zl.y) > 8;
        if (display_dist <= render_dist and ovr.hide ~= true and not off_floor and not zl.sign and zl.kind ~= 'dock' and not (zl.map_only and npc_off)) then
            local label_y = zl.y;
            local face_x, face_z = nil, nil;   -- Fixed label direction.
            local label_x = zl.x;
            local label_z = zl.z;

            local fade = 1.0;
            if (DISTANCE_FADE and DISTANCE_FADE_ZONE > 0.001) then
                local fade_near = render_dist * (1.0 - DISTANCE_FADE_ZONE);
                if (display_dist > fade_near) then
                    fade = math.clamp((render_dist - display_dist) / (render_dist - fade_near), 0.0, 1.0);
                end
            end

            local curtain = zl.curtain;
            if (curtain == nil) then curtain = is_curtain_zoneline(zl); zl.curtain = curtain; end

            if (zl.label_only) then
                docks.keeper(zl, os.time(), s);
                label_y = zl.y - (zl.head or 1.8) - 0.4 - ((type(ovr.height) == 'number') and ovr.height or 0);   -- Above NPC head.
            elseif (curtain) then
                local core_col, glow_col = get_d3d_dot_colors(display_dist);

                if (renderer.dot_glow_enabled) then
                    local gr = math.floor(glow_col / 0x10000) % 0x100;
                    local gg = math.floor(glow_col / 0x100) % 0x100;
                    local gb = glow_col % 0x100;
                    local ga = math.floor(glow_col / 0x1000000) % 0x100;
                    ga = math.floor(ga * glow_pulse * renderer.dot_glow_intensity * GLOW_GAIN + 0.5);
                    if (ga > 255) then ga = 255; end
                    glow_col = ga * 0x1000000 + gr * 0x10000 + gg * 0x100 + gb;
                end

                if (zl.routes ~= nil) then
                    docks.update(zl, os.time());
                    if (zl.alpha < 1.0) then
                        core_col, glow_col = docks.dim(core_col, zl.alpha), docks.dim(glow_col, zl.alpha);
                    end
                end

                local cdata = compute_curtain_positions(zl.x, zl.y, zl.z,
                    zl.sx / 2, zl.sy / 2, zl.sz / 2,
                    zl.cr, zl.sr, player_x, player_z, zl.terrain_heights, zl.rect_id, ovr);
                label_y = cdata.hover_y;
                label_x = cdata.label_x;
                label_z = cdata.label_z;
                if (cdata.n > 1) then face_x, face_z = cdata.px[cdata.n] - cdata.px[1], cdata.pz[cdata.n] - cdata.pz[1]; end
                local dot_sz = D3D_DOT_GLOW_SIZE * glow_size_mult * fade;
                local mode = effects.line(device, zl, cdata, display_dist, now, rx, ry, rz, ux, uy, uz,
                    core_col, glow_col, dot_sz);
                if (not dots_on) then   -- Motes only.
                elseif (mode == 0) then
                    draw_d3d_style_dots(device, cdata, rx, ry, rz, ux, uy, uz, core_col, glow_col, dot_sz);
                else
                    draw_fx_dots(device, cdata, rx, ry, rz, ux, uy, uz);
                end
            else
                flush_dots(device);
                local fill_col = get_d3d_circle_color(display_dist);
                local has_box = (zl.sx ~= nil and zl.sx > 0 and zl.sz ~= nil and zl.sz > 0);
                local r;
                if (has_box) then
                    r = math.max(zl.sx or 8.0, zl.sz or 8.0) / 2;
                else
                    r = zl.sx or 8.0;
                end
                local npc = (zl.ident == 'npc');
                local pad = (zl.floor_label ~= nil);   -- Telepads: pole only.
                local mark = npc and (s.npc_markers ~= false) or (not npc and s.portal_markers ~= false);
                if (mark and not pad and not npc) then draw_d3d_circle(device, zl.x, zl.y, zl.z, r * fade, fill_col); end

                local core_col = get_d3d_dot_colors(display_dist);
                if (npc) then   -- Gem over head.
                    local lift = (type(ovr.height) == 'number') and ovr.height or 0;
                    if (mark) then
                        label_y = draw_d3d_pole(device, zl.x, zl.y - (zl.head or 1.8) - 0.5 - lift, zl.z, 0, rx, ry, rz,
                            core_col, ux, uy, uz, now, zl.rect_id or 0, fade) - 0.1;
                    else
                        label_y = zl.y - (zl.head or 1.8) - 0.4 - lift;   -- Above NPC head.
                    end
                else
                    local pole_h = (type(ovr.pole_height) == 'number' and ovr.pole_height > 0)
                        and ovr.pole_height or 4.0;
                    pole_h = pole_h * fade;
                    if (mark) then draw_d3d_pole(device, zl.x, zl.y, zl.z, pole_h, rx, ry, rz, core_col); end
                    label_y = zl.y - pole_h;  -- Label at pole top.
                end
            end

            local kp = zl.label_only;
            if ((want_labels or want_dist or kp) and fade >= 0.15) then
                local text_y = label_y - renderer.d3d_label_offset;
                local name = nil;
                local dist_n = nil;
                if (kp) then
                    if (s.keeper_route ~= false) then name = zl.display_name; end
                elseif (want_labels) then
                    name = zl.display_name;
                    if (name == nil or name == '') then name = 'Zone Line'; end
                end
                if (kp and s.keeper_distance ~= false or not kp and want_dist) then
                    -- Round halves to even.
                    dist_n = math.floor(display_dist + 0.5);
                    if (dist_n - display_dist == 0.5 and dist_n % 2 == 1) then dist_n = dist_n - 1; end
                end
                frame_labels_n = frame_labels_n + 1;
                local lbl = frame_labels[frame_labels_n];
                if (lbl == nil) then lbl = {}; frame_labels[frame_labels_n] = lbl; end
                lbl.x = label_x; lbl.y = text_y; lbl.z = label_z;
                -- Fixed labels follow line.
                local fx, fz = face_x, face_z;
                if (fx == nil and zl.heading ~= nil) then fx, fz = math.sin(zl.heading), math.cos(zl.heading); end   -- Across NPC facing.
                if (fx == nil or fx * fx + fz * fz < 1e-6) then fx, fz = label_z - player_z, player_x - label_x; end
                local fl = math.sqrt(fx * fx + fz * fz);
                if (fl < 1e-6) then fx, fz, fl = rx, rz, 1; end
                fx, fz = fx / fl, fz / fl;
                lbl.fx, lbl.fz = fx, fz;
                lbl.name = name; lbl.dist_n = dist_n; lbl.dist = display_dist;
                lbl.fade = fade;
                lbl.lines, lbl.lines_n, lbl.tint = zl.lines, kp and zl.lines_n or 0, zl.tint;   -- Docks: name only.
                lbl.crest = (name ~= nil and zl.to_zone ~= nil and zl.to_zone ~= zl.zone_id and s.show_crests ~= false) and crests.of(zl.to_zone) or nil;
            end
        end
    end

    flush_dots(device);
    renderer.labels, renderer.labels_n = frame_labels, frame_labels_n;

    draw_text_pass(device, view, text_scale);
    gdi_evict();
end

function renderer.draw_d3d(zone_lines, player_x, player_y, player_z, s)
    effects.frame();
    if (zone_lines == nil or #zone_lines == 0) then return; end

    local device = d3d8.get_device();
    if (device == nil) then return; end
    local vt = device.lpVtbl;

    local view = renderer.have_view and cached_view or nil;
    if (vt.GetTransform(device, 2, fresh_view) == 0) then view = fresh_view; end   -- View transform.
    if (view == nil) then return; end

    if (not settings_applied) then
        apply_settings(s);
    end

    local render_dist = s.render_distance or 100.0;
    local any_visible = false;
    for _, zl in ipairs(zone_lines) do
        if (distance_to_zoneline(player_x, player_z, zl) <= (zl.sign and signs.C.range or render_dist)) then
            any_visible = true;
            break;
        end
    end
    if (not any_visible) then return; end

    local rx, ry, rz = view._11, view._21, view._31;
    local ux, uy, uz = view._12, view._22, view._32;

    local rlen = math.sqrt(rx * rx + ry * ry + rz * rz);
    if (rlen > 0.001) then rx = rx / rlen; ry = ry / rlen; rz = rz / rlen; end
    local ulen = math.sqrt(ux * ux + uy * uy + uz * uz);
    if (ulen > 0.001) then ux = ux / ulen; uy = uy / ulen; uz = uz / ulen; end
    effects.view(rx, rz, view._13, view._33);

    -- Save states for restore.
    local save_light    = get_rs(device, D3DRS_LIGHTING);
    local save_zenable  = get_rs(device, D3DRS_ZENABLE);
    local save_zwrite   = get_rs(device, D3DRS_ZWRITEENABLE);
    local save_zfunc    = get_rs(device, D3DRS_ZFUNC);
    local save_zbias    = get_rs(device, D3DRS_ZBIAS);
    local save_ablend   = get_rs(device, D3DRS_ALPHABLENDENABLE);
    local save_srcblend = get_rs(device, D3DRS_SRCBLEND);
    local save_dstblend = get_rs(device, D3DRS_DESTBLEND);
    local save_cull     = get_rs(device, D3DRS_CULLMODE);
    local save_atest    = get_rs(device, D3DRS_ALPHATESTENABLE);
    local save_aref     = get_rs(device, D3DRS_ALPHAREF);   -- Game alpha-test.
    local save_afunc    = get_rs(device, D3DRS_ALPHAFUNC);
    local save_fog      = get_rs(device, D3DRS_FOGENABLE);  -- Zone fog.
    local save_fvf = (vt.GetVertexShader(device, out_dw) == 0) and out_dw[0] or nil;
    local save_sb = textures.hold(device);
    local save_tex = nil;
    if (save_sb == nil and vt.GetTexture(device, 0, out_tex) == 0) then save_tex = out_tex[0]; end
    local save_ps  = (vt.GetPixelShader(device, out_dw) == 0) and out_dw[0] or nil;
    -- Own transform buffers.
    local have_world = (vt.GetTransform(device, D3DTS_WORLD, restore_world) == 0);
    local have_view  = (vt.GetTransform(device, 2, restore_view) == 0);   -- Saved view.
    local have_proj  = (vt.GetTransform(device, 3, restore_proj) == 0);   -- Saved projection.
    local save_colorop   = get_tss(device, 0, D3DTSS_COLOROP);
    local save_colorarg1 = get_tss(device, 0, D3DTSS_COLORARG1);
    local save_colorarg2 = get_tss(device, 0, D3DTSS_COLORARG2);
    local save_alphaop   = get_tss(device, 0, D3DTSS_ALPHAOP);
    local save_alphaarg1 = get_tss(device, 0, D3DTSS_ALPHAARG1);
    local save_alphaarg2 = get_tss(device, 0, D3DTSS_ALPHAARG2);
    local save_magfilter = get_tss(device, 0, D3DTSS_MAGFILTER);
    local save_minfilter = get_tss(device, 0, D3DTSS_MINFILTER);
    local save_addru     = get_tss(device, 0, D3DTSS_ADDRESSU);
    local save_addrv     = get_tss(device, 0, D3DTSS_ADDRESSV);
    local save_s1_colorop = get_tss(device, 1, D3DTSS_COLOROP);
    local save_s1_alphaop = get_tss(device, 1, D3DTSS_ALPHAOP);

    device:SetTexture(0, nil);
    device:SetVertexShader(D3DFVF_XYZ_DIFFUSE);
    device:SetPixelShader(0);
    device:SetRenderState(D3DRS_LIGHTING, 0);
    device:SetRenderState(D3DRS_FOGENABLE, 0);           -- Fog off.
    device:SetRenderState(D3DRS_CULLMODE, 1);             -- Cull none.
    device:SetRenderState(D3DRS_ALPHABLENDENABLE, 1);
    device:SetRenderState(D3DRS_SRCBLEND, 5);             -- D3DBLEND_SRCALPHA
    device:SetRenderState(D3DRS_DESTBLEND, 6);            -- D3DBLEND_INVSRCALPHA
    device:SetRenderState(D3DRS_ZENABLE, 1);
    device:SetRenderState(D3DRS_ZWRITEENABLE, 1);
    device:SetRenderState(D3DRS_ZFUNC, D3DCMP_LESSEQUAL);
    device:SetRenderState(D3DRS_ZBIAS, 8);

    device:SetTextureStageState(0, D3DTSS_COLOROP, 2);    -- SELECTARG1
    device:SetTextureStageState(0, D3DTSS_COLORARG1, 0);  -- DIFFUSE
    device:SetTextureStageState(0, D3DTSS_ALPHAOP, 2);    -- SELECTARG1
    device:SetTextureStageState(0, D3DTSS_ALPHAARG1, 0);  -- DIFFUSE

    device:SetTransform(D3DTS_WORLD, identity_matrix);

    effects.set_atest(save_atest);
    local draw_ok, draw_err = pcall(draw_body, device, zone_lines, player_x, player_y, player_z, s,
        rx, ry, rz, ux, uy, uz, view);

    if (have_world) then device:SetTransform(D3DTS_WORLD, restore_world); end
    if (have_view) then device:SetTransform(2, restore_view); end
    if (have_proj) then device:SetTransform(3, restore_proj); end
    if (save_sb ~= nil) then textures.restore(device, save_sb);
    else
        device:SetTexture(0, save_tex);
        if (save_tex ~= nil) then save_tex:Release(); end   -- Release the texture ref.
    end
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
    device:SetRenderState(D3DRS_ALPHAREF, save_aref);    -- Restore alpha test.
    device:SetRenderState(D3DRS_ALPHAFUNC, save_afunc);
    device:SetVertexShader(save_fvf);
    if (save_ps ~= nil) then device:SetPixelShader(save_ps); end
    device:SetTextureStageState(0, D3DTSS_COLOROP, save_colorop);
    device:SetTextureStageState(0, D3DTSS_COLORARG1, save_colorarg1);
    device:SetTextureStageState(0, D3DTSS_COLORARG2, save_colorarg2);
    device:SetTextureStageState(0, D3DTSS_ALPHAOP, save_alphaop);
    device:SetTextureStageState(0, D3DTSS_ALPHAARG1, save_alphaarg1);
    device:SetTextureStageState(0, D3DTSS_ALPHAARG2, save_alphaarg2);
    device:SetTextureStageState(0, D3DTSS_MAGFILTER, save_magfilter);
    device:SetTextureStageState(0, D3DTSS_MINFILTER, save_minfilter);
    device:SetTextureStageState(0, D3DTSS_ADDRESSU, save_addru);
    device:SetTextureStageState(0, D3DTSS_ADDRESSV, save_addrv);
    device:SetTextureStageState(1, D3DTSS_COLOROP, save_s1_colorop);
    device:SetTextureStageState(1, D3DTSS_ALPHAOP, save_s1_alphaop);

    if (not draw_ok) then error(draw_err, 0); end   -- State restored; caller reports.
end

-- Cache camera and viewport.
function renderer.cache_camera()
    local dev = d3d8.get_device();
    if (dev == nil) then return; end
    local vt = dev.lpVtbl;
    if (vt.GetTransform(dev, 2, cached_view) == 0) then renderer.have_view = true; end   -- View transform.
    if (vt.GetTransform(dev, 3, cached_proj) == 0) then renderer.have_proj = true; end   -- Projection transform.
    if (vt.GetViewport(dev, out_vp) == 0) then
        renderer.cached_vp_w = out_vp[0].Width;
        renderer.cached_vp_h = out_vp[0].Height;
    end
end

return renderer;
