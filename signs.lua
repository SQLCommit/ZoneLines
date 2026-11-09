-- Ship-time signs at the docks.
-- Load after renderer cdefs.
local ffi       = require 'ffi';
local bit       = require 'bit';
local d3d8      = require 'd3d8';
local effects   = require 'effects';
local textures  = require 'textures';
local transport = require 'transport';
local wintype   = require 'wintype';

local signs = {};

local floor, max = math.floor, math.max;
local D3DPT_TRIANGLELIST, FVF_TEX, VSIZE = 4, 0x142, 24;
local PAD, GAP, FACE, CORNER = 0.2, 0.09, 0.04, 0.22;   -- Yalms.
local TEXEL = 0.01;   -- Yalms per texel.
local CAP_H, TITLE_H, NAME_H, LINE_H = 0.2, 0.4, 0.3, 0.26;   -- Ink heights.
local MAX_SIGNS, MAX_RUNS = 8, 48;

-- Defaults until synced.
local C = { w = 4.4, up = 4.4, k = 1, sc = 1, range = 90, window = true, emblem = true, title = true, back = true,
    board = true, op = 1, title_c = 0xFFF2DC98, line_c = 0xFFFFFFFF, open_c = 0xFF9CF0A8, mask = 7 };
signs.C = C;

local function num(s, k, d, lo, hi)
    local v = tonumber(s[k]) or d;
    if (v < lo) then v = lo; elseif (v > hi) then v = hi; end
    return v;
end

-- RGB table to ARGB.
local function rgb(t, a, d)
    if (type(t) ~= 'table') then return a * 0x1000000 + d; end
    local c = 0;
    for i = 1, 3 do
        local v = tonumber(t[i]);
        if (v == nil) then return a * 0x1000000 + d; end
        if (v < 0) then v = 0; elseif (v > 1) then v = 1; end
        c = c * 0x100 + floor(v * 255 + 0.5);
    end
    return a * 0x1000000 + c;
end

function signs.sync(s)
    C.w, C.up = num(s, 'sign_width', 4.4, 2, 8), num(s, 'sign_height', 4.4, 2, 9);
    C.k, C.range = num(s, 'sign_text', 100, 60, 150) / 100, num(s, 'sign_range', 90, 10, 150);
    C.sc = num(s, 'sign_scale', 100, 50, 200) / 100;
    signs.band_state = 0;   -- Font may have changed.
    C.window, C.emblem = (s.sign_style ~= 'none'), (s.sign_emblem ~= false);
    C.title = (s.sign_title ~= false);
    C.back, C.board = (s.sign_back ~= false), (s.sign_boarding ~= false);
    C.op = num(s, 'sign_opacity', 100, 0, 100) / 100;
    C.title_c = rgb(s.sign_title_color, 0xFF, 0xF2DC98);
    C.line_c = rgb(s.sign_line_color, 0xFF, 0xFFFFFF);
    C.open_c = rgb(s.sign_board_color, 0xFF, 0x9CF0A8);
    C.mask = ((s.sign_status ~= false) and 1 or 0) + ((s.sign_clock ~= false) and 2 or 0) + ((s.sign_countdown ~= false) and 4 or 0);
end

-- Banner PNG, loaded on use.
local art = {};
local function banner(name)
    local t = art[name];
    if (t ~= nil) then return t or nil; end
    local dev = d3d8.get_device();
    if (dev == nil) then return nil; end
    local dir = signs.dir;
    if (dir == nil) then pcall(function() dir = addon.path .. '\\signs\\'; end); signs.dir = dir; end
    if (dir == nil) then return nil; end
    local path = dir .. 'emb_' .. name .. '.png';
    local ptr = ffi.new('IDirect3DTexture8*[1]');
    if (ashita.fs.exists(path) and ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) == ffi.C.S_OK and ptr[0] ~= nil) then
        art[name] = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
    else
        art[name] = false;
        textures.log('sign: cannot load ' .. path .. ', no banner');
    end
    return art[name] or nil;
end

-- Cancel finalizer first.
function signs.release()
    for name, t in pairs(art) do
        if (t) then ffi.gc(t, nil); pcall(function() t:Release(); end); end
        art[name] = nil;
    end
    wintype.release();
end

-- Backing quads, then window pieces.
local PV = ffi.new('zl_d3d_textured_vertex_t[?]', MAX_SIGNS * 6);
local pf, pi_ = ffi.cast('float*', PV), ffi.cast('int32_t*', PV);
local WV, WF, WI, wn = {}, {}, {}, {};
for k = 1, 9 do
    WV[k] = ffi.new('zl_d3d_textured_vertex_t[?]', MAX_SIGNS * 6);
    WF[k], WI[k], wn[k] = ffi.cast('float*', WV[k]), ffi.cast('int32_t*', WV[k]), 0;
end
local frame_skin = nil;
local RUNV, RUNF, RUNI, RUN_TEX, RUN_T = {}, {}, {}, {}, {};
for k = 1, MAX_RUNS do
    RUNV[k] = ffi.new('zl_d3d_textured_vertex_t[?]', 12);
    RUNF[k], RUNI[k] = ffi.cast('float*', RUNV[k]), ffi.cast('int32_t*', RUNV[k]);
    RUN_TEX[k], RUN_T[k] = false, 4;
end
signs.runs, signs.panel, signs.pieces = RUNF, pf, WF;
local base_of = setmetatable({}, { __mode = 'k' });
local npv, nrun = 0, 0;
local side = 0;   -- Camera-facing side.
signs.last_signs, signs.last_runs, signs.last_skin, signs.last_pv = 0, 0, nil, 0;
local frame_signs = 0;
-- Per-sign draw data.
local S_PV, S_SKIN, S_R0, S_R1, S_D, S_F, ORDER = {}, {}, {}, {}, {}, {}, {};
local EYE = { 0, 0, 0, false };   -- Camera position.

-- Colour scaled by k.
local function fade_col(c, k)
    local a = floor(c / 0x1000000) % 0x100;
    return bit.tobit(floor(a * k + 0.5) * 0x1000000 + c % 0x1000000);
end

-- Quad centred on a point.
local function quad(f, i, o, cx, cy, cz, ax, az, hw, hh, col, u0, v0, u1, v1)
    local lx, lz, rx, rz = cx - ax * hw, cz - az * hw, cx + ax * hw, cz + az * hw;
    local t, b = cy - hh, cy + hh;
    local p = o * 6;
    f[p] = lx; f[p + 1] = t; f[p + 2] = lz; i[p + 3] = col; f[p + 4] = u0; f[p + 5] = v0;
    f[p + 6] = rx; f[p + 7] = t; f[p + 8] = rz; i[p + 9] = col; f[p + 10] = u1; f[p + 11] = v0;
    f[p + 12] = rx; f[p + 13] = b; f[p + 14] = rz; i[p + 15] = col; f[p + 16] = u1; f[p + 17] = v1;
    f[p + 18] = lx; f[p + 19] = t; f[p + 20] = lz; i[p + 21] = col; f[p + 22] = u0; f[p + 23] = v0;
    f[p + 24] = rx; f[p + 25] = b; f[p + 26] = rz; i[p + 27] = col; f[p + 28] = u1; f[p + 29] = v1;
    f[p + 30] = lx; f[p + 31] = b; f[p + 32] = lz; i[p + 33] = col; f[p + 34] = u0; f[p + 35] = v1;
end

-- One text or banner row.
local function pic(tex, tw, th, x, y, z, nx, nz, rx, rz, off, col, v0, v1)
    v0, v1 = v0 or 0, v1 or 1;
    if (side == -1 and not C.back) then return true; end
    if (nrun >= MAX_RUNS) then return false; end
    nrun = nrun + 1;
    RUN_TEX[nrun] = tex;
    local f, i = RUNF[nrun], RUNI[nrun];
    RUN_T[nrun] = 2;
    if (side == -1) then
        quad(f, i, 0, x - nx * FACE - rx * off, y, z - nz * FACE - rz * off, -rx, -rz, tw / 2, th / 2, col, 0, v0, 1, v1);
        return true;
    end
    quad(f, i, 0, x + nx * FACE + rx * off, y, z + nz * FACE + rz * off, rx, rz, tw / 2, th / 2, col, 0, v0, 1, v1);
    if (side == 0 and C.back) then
        quad(f, i, 6, x - nx * FACE - rx * off, y, z - nz * FACE - rz * off, -rx, -rz, tw / 2, th / 2, col, 0, v0, 1, v1);
        RUN_T[nrun] = 4;
    end
    return true;
end

-- Quad with corner colours.
local function quad4(f, i, o, cx, cy, cz, ax, az, hw, hh, c1, c2, c3, c4, u0, v0, u1, v1)
    quad(f, i, o, cx, cy, cz, ax, az, hw, hh, c1, u0, v0, u1, v1);
    local p = o * 6;
    i[p + 9] = c2; i[p + 15] = c4; i[p + 27] = c4; i[p + 33] = c3;
end

-- Skin in nine pieces.
local XS, YS, PW, PH = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, {}, {};
local function window(skin, x, cy, z, rx, rz, w, h, px, k)
    local cs, es = skin.corner * px, skin.edge * px;
    XS[1], XS[2], XS[3], XS[4] = -w / 2, -w / 2 + cs, w / 2 - cs, w / 2;
    YS[1], YS[2], YS[3], YS[4] = -h / 2, -h / 2 + cs, h / 2 - cs, h / 2;
    for n = 1, 9 do
        local q = skin.piece[n];
        local a, b = (n - 1) % 3 + 1, floor((n - 1) / 3) + 1;
        local x0, x1, y0, y1 = XS[a], XS[a + 1], YS[b], YS[b + 1];
        if (n == 5) then x0, x1, y0, y1 = XS[1], XS[4], YS[1], YS[4];
        elseif (n == 2) then y1 = y0 + es;
        elseif (n == 8) then y0 = y1 - es;
        elseif (n == 4) then x1 = x0 + es;
        elseif (n == 6) then x0 = x1 - es; end
        local sw, sh = q.w, q.h;
        if (a == 2) then sw = (x1 - x0) / px; end   -- Edges and background repeat.
        if (b == 2) then sh = (y1 - y0) / px; end
        local tw, th = skin.tw[q.tex], skin.th[q.tex];
        local mx, my = (x0 + x1) / 2, (y0 + y1) / 2;
        local c = q.col;
        quad4(WF[n], WI[n], wn[n], x + rx * mx, cy + my, z + rz * mx, rx, rz, (x1 - x0) / 2, (y1 - y0) / 2,
            fade_col(c[1], k), fade_col(c[2], k), fade_col(c[3], k), fade_col(c[4], k),
            q.u / tw, q.v / th, (q.u + sw) / tw, (q.v + sh) / th);
        wn[n] = wn[n] + 6;
    end
end

-- Ink rows of the font.
signs.band_state, signs.band0, signs.band1 = 0, 0, 1;
local function measure_band(get)
    signs.band_state, signs.band0, signs.band1 = 1, 0, 1;
    local tex, rect = get('Hg');   -- A capital and descender.
    if (tex == nil or rect == nil or rect.right <= 0 or rect.bottom <= 2) then return; end
    local w, h = rect.right, rect.bottom;
    local ok, lres, lock = pcall(tex.LockRect, tex, 0, nil, 0x10);   -- Read only.
    if (not ok or lres ~= 0 or lock == nil or lock.pBits == nil or lock.Pitch < w * 4) then return; end
    local bits = ffi.cast('uint8_t*', lock.pBits);
    local top, bot = nil, nil;
    for y = 0, h - 1 do
        local row = bits + y * lock.Pitch;
        for x = 0, w - 1 do
            if (row[x * 4 + 3] > 24) then
                top = top or y; bot = y;
                break;
            end
        end
    end
    pcall(tex.UnlockRect, tex, 0);
    if (top ~= nil and bot > top) then signs.band0, signs.band1 = top / h, (bot + 1) / h; end
end

-- Routes grouped by label.
local function groups(zl)
    local g = zl.s_groups;
    if (g ~= nil) then return g; end
    g = {};
    if (zl.swap) then   -- Swap sign, one group.
        g[1] = { label = zl.routes[1].label };
        for i, r in ipairs(zl.routes) do g[1][i] = r; end
        zl.s_groups = g;
        return g;
    end
    local at = {};
    for _, r in ipairs(zl.routes) do
        local k = at[r.label];
        if (k == nil) then k = { label = r.label }; g[#g + 1] = k; at[r.label] = k; end
        k[#k + 1] = r;
    end
    zl.s_groups = g;
    return g;
end

-- Next run to dock.
local function next_of(grp, sec)
    local best, bk, run = nil, nil, nil;
    for _, r in ipairs(grp) do
        local b = transport.brief(r, sec);
        local k = b.near and b.left - 1e6 or b.left;
        if (bk == nil or k < bk) then best, bk, run = b, k, r; end
    end
    return best, run;
end

local function status(b)
    local st = nil;
    if (C.mask % 2 == 1) then st = b.word; end
    if (floor(C.mask / 2) % 2 == 1) then st = st and (st .. ' ' .. b.clock) or b.clock; end
    return st;
end

-- Sign rows for a second.
local ROW_S, ROW_H, ROW_C = {}, {}, {};
local function rows(zl, sec)
    local g = groups(zl);
    if (zl.s_sec ~= sec or zl.s_mask ~= C.mask) then
        zl.s_sec, zl.s_mask = sec, C.mask;
        zl.s_line, zl.s_cd, zl.s_open = zl.s_line or {}, zl.s_cd or {}, zl.s_open or {};
        for i, grp in ipairs(g) do
            local b, run = next_of(grp, sec);
            if (zl.swap and zl.s_run ~= run) then   -- Sign turns to other ship.
                zl.s_run, zl.s_cap = run, nil;
                grp.label = run.label;
                zl.s_emb = zl.emblems and zl.emblems[run.name] or zl.emblem;
            end
            local st, cd = status(b), (C.mask >= 4) and b.cd or nil;
            if ((#g > 1 or zl.slim) and cd ~= nil) then st, cd = st and (st .. '  ' .. cd) or cd, nil; end
            zl.s_line[i], zl.s_cd[i], zl.s_open[i] = st or false, cd or false, b.open;
        end
    end
    if (zl.s_cap == nil) then
        local cap, dest = g[1].label:match('^(.- to) (.+)$');
        zl.s_cap, zl.s_dest = cap or '', dest or g[1].label;
    end
    local n = 0;
    for i, grp in ipairs(g) do
        local lc = (zl.s_open[i] and C.board) and C.open_c or C.line_c;
        if (C.title) then
            if (#g > 1) then
                n = n + 1; ROW_S[n], ROW_H[n], ROW_C[n] = grp.label, NAME_H, C.title_c;
            else
                if (zl.s_cap ~= '' and not zl.slim) then n = n + 1; ROW_S[n], ROW_H[n], ROW_C[n] = zl.s_cap, CAP_H, C.title_c; end
                n = n + 1; ROW_S[n], ROW_H[n], ROW_C[n] = zl.s_dest, TITLE_H, C.title_c;
            end
        end
        if (zl.s_line[i]) then n = n + 1; ROW_S[n], ROW_H[n], ROW_C[n] = zl.s_line[i], LINE_H, lc; end
        if (zl.s_cd[i]) then n = n + 1; ROW_S[n], ROW_H[n], ROW_C[n] = zl.s_cd[i], LINE_H, lc; end
    end
    return n;
end

-- Queue a sign for drawing.
function signs.queue(zl, sec, fade, view, lift)
    local get = signs.text_source;
    if (get == nil or frame_signs >= MAX_SIGNS) then return; end
    local n = rows(zl, sec);
    if (n == 0) then return; end
    local skin = C.window and wintype.skin(os.clock()) or nil;
    if (frame_skin ~= nil and skin ~= frame_skin) then skin = nil; end   -- One skin per frame.
    local sc = C.sc;   -- Whole-sign size.
    local kt, gap, pad, cn = C.k * sc, GAP * sc, PAD * sc, CORNER * sc;
    local text_h = (n - 1) * gap;
    for j = 1, n do text_h = text_h + ROW_H[j] * kt; end
    local h = text_h + 2 * pad;
    if (skin) then h = max(h, 2 * skin.corner * TEXEL * sc + 0.1 * sc); end
    local w = zl.width or C.w * sc;   -- Fixed width ignores scale.
    local hand = effects.handed();
    local nx, nz = zl.nx, zl.nz;
    local rx, rz = -hand * nz, hand * nx;   -- Reader's right.
    local x, z, cy = zl.x, zl.z, zl.y - (zl.up or C.up) - (lift or 0);
    if (zl.slot ~= nil) then   -- One of a door pair.
        local o = zl.slot * (w / 2 + 0.15 * sc);
        x, z = x + rx * o, z + rz * o;
    end
    side = 0;
    local i = frame_signs + 1;
    S_D[i], S_PV[i], S_SKIN[i], S_R0[i], S_F[i] = 0, false, false, nrun + 1, fade;
    EYE[4] = view ~= nil;
    if (view ~= nil) then
        local ex = -(view._41 * view._11 + view._42 * view._12 + view._43 * view._13);   -- Camera position.
        local ez = -(view._41 * view._31 + view._42 * view._32 + view._43 * view._33);
        EYE[1], EYE[3] = ex, ez;
        EYE[2] = -(view._41 * view._21 + view._42 * view._22 + view._43 * view._23);
        side = ((ex - x) * nx + (ez - z) * nz >= 0) and 1 or -1;
        S_D[i] = (ex - x) * (ex - x) + (ez - z) * (ez - z);
    end
    if (C.window or side == 0) then
        S_PV[i] = npv;
        local backing = C.window and floor(255 * C.op * fade + 0.5) or 0;   -- Backing alpha.
        quad(pf, pi_, npv, x, cy, z, rx, rz, w / 2, h / 2, bit.tobit(backing * 0x1000000), 0, 0, 1, 1);
        npv = npv + 6;
    end
    if (skin) then
        frame_skin, S_SKIN[i] = skin, wn[1];
        window(skin, x, cy, z, rx, rz, w, h, TEXEL * sc, C.op * fade);
    end
    local inset, eg = cn + 0.06 * sc, 0.12 * sc;
    local area, off = w - 2 * inset, 0;
    local en = zl.swap and zl.s_emb or zl.emblem;
    local emb = C.emblem and en and banner(en) or nil;
    if (emb) then
        local es = math.min(h - 2 * cn - 0.1 * sc, w * 0.3);   -- Leaves room for text.
        pic(emb, es, es, x, cy, z, nx, nz, rx, rz, -w / 2 + inset + es / 2, fade_col(0xFFFFFFFF, fade));
        area = w - 2 * inset - es - eg;
        off = -w / 2 + inset + es + eg + area / 2;
    end
    frame_signs = i;
    if (signs.band_state == 0) then measure_band(get); end
    local v0, v1 = signs.band0, signs.band1;
    local y = cy - text_h / 2;
    local refs = zl.s_ref;
    if (refs == nil) then refs = {}; zl.s_ref = refs; end
    for j = 1, n do
        local th = ROW_H[j] * kt;
        local str = ROW_S[j];
        local tex, rect = get(str);
        if (tex ~= nil and rect ~= nil and rect.right > 0 and rect.bottom > 0) then
            local tw = th * rect.right / (rect.bottom * (v1 - v0));   -- Ink band fills row.
            local rw = tw;   -- Width with digits as 0, so ticking digits keep the row still.
            local ref = refs[j];
            if (ref == nil or ref.s ~= str) then ref = { s = str, t = (str:gsub('%d', '0')) }; refs[j] = ref; end
            if (ref.t ~= str) then
                local _, rr = get(ref.t);
                if (rr ~= nil and rr.right > 0 and rr.bottom > 0) then rw = th * rr.right / (rr.bottom * (v1 - v0)); end
            end
            local k = (rw > area) and area / rw or 1;   -- Each row fits.
            local o = off + (tw - rw) * k / 2;   -- Left edge pinned to the box.
            if (not pic(tex, tw * k, th * k, x, y + th / 2, z, nx, nz, rx, rz, o, fade_col(ROW_C[j], fade), v0, v1)) then break; end
        end
        y = y + th + gap;
    end
    S_R1[i] = nrun;
end

function signs.pending() return frame_signs > 0; end

-- Nothing drawn this frame.
function signs.idle() signs.last_signs, signs.last_runs, signs.last_pv, signs.last_skin = 0, 0, 0, nil; end

function signs.discard()
    npv = 0;
    for k = 1, nrun do RUN_TEX[k] = false; end
    for k = 1, 9 do wn[k] = 0; end
    nrun, frame_signs, frame_skin = 0, 0, nil;
end

-- Texture times diffuse.
local function modulate(vt, device)
    vt.SetTextureStageState(device, 0, 1, 4);
    vt.SetTextureStageState(device, 0, 2, 2);
    vt.SetTextureStageState(device, 0, 3, 0);
    vt.SetTextureStageState(device, 0, 4, 4);
    vt.SetTextureStageState(device, 0, 5, 2);
    vt.SetTextureStageState(device, 0, 6, 0);
end

local function bind(vt, device, tex)
    local base = base_of[tex];
    if (base == nil) then base = ffi.cast('IDirect3DBaseTexture8*', tex); base_of[tex] = base; end
    vt.SetTexture(device, 0, base);
end

local PIECE_ORDER = { 5, 1, 2, 3, 4, 6, 7, 8, 9 };

-- Backing, frame, words; then depth.
local function plain(vt, device)
    vt.SetTexture(device, 0, nil);
    vt.SetTextureStageState(device, 0, 1, 2);   -- Colour = diffuse.
    vt.SetTextureStageState(device, 0, 2, 0);
    vt.SetTextureStageState(device, 0, 4, 2);   -- Alpha = diffuse.
    vt.SetTextureStageState(device, 0, 5, 0);
end

local function paint(vt, device, i, skin)
    if (S_PV[i]) then
        plain(vt, device);
        vt.DrawPrimitiveUP(device, D3DPT_TRIANGLELIST, 2, PV + S_PV[i], VSIZE);
    end
    if (S_SKIN[i] and skin ~= nil) then
        modulate(vt, device);
        vt.SetTextureStageState(device, 0, 1, 5);   -- Texture x diffuse x 2.
        vt.SetTextureStageState(device, 0, 4, 5);
        for _, n in ipairs(PIECE_ORDER) do
            local q = skin.piece[n];
            bind(vt, device, skin.tex[q.tex]);
            vt.SetTextureStageState(device, 0, 13, ((n - 1) % 3 == 1) and 1 or 3);   -- Wrap where repeating.
            vt.SetTextureStageState(device, 0, 14, (floor((n - 1) / 3) == 1) and 1 or 3);
            vt.SetRenderState(device, 20, q.add and 2 or 6);   -- ONE when additive.
            vt.DrawPrimitiveUP(device, D3DPT_TRIANGLELIST, 2, WV[n] + S_SKIN[i], VSIZE);
        end
        vt.SetRenderState(device, 20, 6);
        vt.SetTextureStageState(device, 0, 13, 3);
        vt.SetTextureStageState(device, 0, 14, 3);
    end
    if (S_R1[i] >= S_R0[i]) then
        modulate(vt, device);
        for k = S_R0[i], S_R1[i] do
            bind(vt, device, RUN_TEX[k]);
            vt.DrawPrimitiveUP(device, D3DPT_TRIANGLELIST, RUN_T[k], RUNV[k], VSIZE);
        end
    end
end

-- Push vertices away from camera.
local function push(f, o, n, k)
    local ex, ey, ez = EYE[1], EYE[2], EYE[3];
    for v = o, o + n - 1 do
        local p = v * 6;
        f[p] = ex + (f[p] - ex) / k; f[p + 1] = ey + (f[p + 1] - ey) / k; f[p + 2] = ez + (f[p + 2] - ez) / k;
    end
end

-- Depth fades with sign.
local function fade_depth()
    if (not EYE[4]) then return; end
    for i = 1, frame_signs do
        local k = max(S_F[i], 0.01);
        if (k < 1) then
            if (S_PV[i]) then push(pf, S_PV[i], 6, k); end
            for r = S_R0[i], S_R1[i] do push(RUNF[r], 0, RUN_T[r] * 3, k); end
        end
    end
end

function signs.flush(device)
    if (frame_signs == 0) then signs.last_signs, signs.last_runs, signs.last_pv, signs.last_skin = 0, 0, 0, nil; return; end
    local vt = device.lpVtbl;
    vt.SetVertexShader(device, FVF_TEX);
    vt.SetRenderState(device, 15, 0);   -- Alpha test.
    vt.SetRenderState(device, 19, 5);   -- SRCALPHA.
    vt.SetRenderState(device, 20, 6);   -- INVSRCALPHA.
    vt.SetRenderState(device, 14, 0);   -- No z write.
    vt.SetTextureStageState(device, 1, 1, 1);
    vt.SetTextureStageState(device, 1, 4, 1);
    vt.SetTextureStageState(device, 0, 16, 2);   -- Linear, mipmapped.
    vt.SetTextureStageState(device, 0, 17, 2);
    vt.SetTextureStageState(device, 0, 18, 2);
    vt.SetTextureStageState(device, 0, 13, 3);   -- Clamp.
    vt.SetTextureStageState(device, 0, 14, 3);
    for i = 1, frame_signs do   -- Far to near.
        local j, d = i, S_D[i];
        while (j > 1 and S_D[ORDER[j - 1]] < d) do ORDER[j] = ORDER[j - 1]; j = j - 1; end
        ORDER[j] = i;
    end
    local skin = frame_skin;
    for o = 1, frame_signs do paint(vt, device, ORDER[o], skin); end
    fade_depth();
    plain(vt, device);
    vt.SetRenderState(device, 14, 1);      -- Depth only.
    vt.SetRenderState(device, 19, 1);
    vt.SetRenderState(device, 20, 2);
    if (npv > 0) then vt.DrawPrimitiveUP(device, D3DPT_TRIANGLELIST, npv / 3, PV, VSIZE); end
    modulate(vt, device);
    vt.SetRenderState(device, 15, 1);      -- Solid pixels only.
    vt.SetRenderState(device, 24, 0x60);
    vt.SetRenderState(device, 25, 7);      -- GREATEREQUAL.
    for k = 1, nrun do
        bind(vt, device, RUN_TEX[k]);
        vt.DrawPrimitiveUP(device, D3DPT_TRIANGLELIST, RUN_T[k], RUNV[k], VSIZE);
        RUN_TEX[k] = false;
    end
    vt.SetRenderState(device, 15, 0);
    vt.SetRenderState(device, 14, 0);
    vt.SetRenderState(device, 19, 5);
    vt.SetRenderState(device, 20, 6);
    vt.SetTexture(device, 0, nil);
    signs.last_signs, signs.last_runs, signs.last_skin, signs.last_pv, signs.last_depth = frame_signs, nrun, skin, npv, nrun;
    for k = 1, 9 do wn[k] = 0; end
    npv, nrun, frame_signs, frame_skin = 0, 0, 0, nil;
end

return signs;
