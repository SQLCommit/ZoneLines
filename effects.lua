-- Dot wave, reveal, and motes.
-- Load after renderer.
local ffi      = require 'ffi';
local bit      = require 'bit';
local textures = require 'textures';
local ground   = require 'ground';

local effects = {};

local floor, sqrt, sin, cos, abs = math.floor, math.sqrt, math.sin, math.cos, math.abs;
local PI = math.pi;

local D3DPT_TRIANGLELIST = 4;
local FVF_TEX, FVF_PLAIN, VSIZE = 0x142, 0x042, 24;
local RS_ZWRITE, RS_ATEST, RS_SRC, RS_DST = 14, 15, 19, 20;
local TSS_COLOROP, TSS_COLORARG1, TSS_COLORARG2 = 1, 2, 3;
local TSS_ALPHAOP, TSS_ALPHAARG1, TSS_ALPHAARG2 = 4, 5, 6;
local TSS_ADDRU, TSS_ADDRV, TSS_MAG, TSS_MIN = 13, 14, 16, 17;
local TOP_DISABLE, TOP_SELECT1, TOP_MODULATE = 1, 2, 4;
local TA_DIFFUSE, TA_TEXTURE, TA_ALPHAREP = 0, 2, 0x20;

-- Mote size constants.
local SOFT_K      = 0.29;   -- Demo width to half-size.
local NEAR_FAR, REVEAL_EDGE = 40, 2;
local MOTES_MAX, MOTES_PER_Y = 48, 2.2;
local SLOTS_N, REENTER_S = 64, 0.25;
local GS, GROUND_BUDGET, GROUND_TRIES = 16, 32, 3;   -- Samples, queries per frame, tries.

-- Player tuning from sync.
local U = { wave_sp = 4, wave_d = 0.25, reveal = 0.6, mote_range = 35, mote_rate = 2.2, mote_cap = 24, mote_rise = 3.2,
    mote_start = 0.3, hover = 0.5 };

-- Sprite batch, fixed UVs.
local MAX_SPRITES = 512;
local verts = ffi.new('zl_d3d_textured_vertex_t[?]', MAX_SPRITES * 6);
local vf = ffi.cast('float*', verts);
local vi = ffi.cast('int32_t*', verts);
local CU = { 0, 1, 1, 0, 1, 0 };
local CV = { 1, 1, 0, 1, 0, 0 };
for s = 0, MAX_SPRITES - 1 do
    for c = 0, 5 do
        local b = (s * 6 + c) * 6;
        vf[b + 4] = CU[c + 1]; vf[b + 5] = CV[c + 1];
    end
end

-- Fan dot sizes and colours.
effects.fs = ffi.new('double[?]', 513);
effects.fc = ffi.new('double[?]', 513);
effects.fg = ffi.new('double[?]', 513);
local fs, fc, fg = effects.fs, effects.fc, effects.fg;

effects.last_sprites, effects.last_motes = 0, 0;

local f_wave, f_reveal, f_motes = false, false, false;
local any_dot, any_slot = false, false;

local seed = 11;
local function rng()
    seed = (seed * 16807) % 2147483647;
    return seed / 2147483647;
end

-- Per-line state.
local slots = {};
for i = 1, SLOTS_N do
    local m = { l = {}, d = {}, s = {}, o = {} };
    for k = 1, MOTES_MAX do m.l[k] = 0; m.d[k] = 1; m.s[k] = 0; m.o[k] = 0; end
    local g = { y = {}, t = {}, x1 = 0, z1 = 0, n = 0 };
    for k = 1, GS do g.y[k] = false; g.t[k] = 0; end
    slots[i] = { owner = false, rev = 0, last = -1e9, seen = -10, motes = m, g = g };
end
local gq = 0;   -- Queries this frame.

-- Floor samples per line.
local function floor_of(sl, cpx, cpy, cpz, n, lx, lz)
    local g = sl.g;
    local gy, gt = g.y, g.t;
    if (g.x1 ~= cpx[1] or g.z1 ~= cpz[1] or g.n ~= n) then   -- New line or edge.
        g.x1, g.z1, g.n = cpx[1], cpz[1], n;
        for k = 1, GS do gy[k] = false; gt[k] = 0; end
    end
    for k = 1, GS do
        if (gy[k] == false and gt[k] < GROUND_TRIES and gq < GROUND_BUDGET) then
            gq = gq + 1;
            gt[k] = gt[k] + 1;
            local u = (k - 1) / (GS - 1);
            local di = floor(u * (n - 1) + 0.5) + 1;
            local v = ground.at(cpx[1] + lx * u, cpy[di] + U.hover, cpz[1] + lz * u);
            if (v ~= nil) then gy[k] = v; end
        end
    end
    return gy;
end

local serial = 0;
local nspr, frame_spr, frame_motes = 0, 0, 0;
local dev_ = nil;
local Rx, Ry, Rz, Ux, Uy, Uz = 1, 0, 0, 0, 1, 0;
local glow_tex, glow_base = nil, nil;
local dv, f_vs, f_tex, f_rs, f_tss, f_draw = nil, nil, nil, nil, nil, nil;

-- Cached vtable calls.
local function bind(device)
    if (dv ~= nil and dv == device) then return; end
    local vt = device.lpVtbl;
    f_vs, f_tex, f_rs, f_tss, f_draw = vt.SetVertexShader, vt.SetTexture, vt.SetRenderState,
        vt.SetTextureStageState, vt.DrawPrimitiveUP;
    dv = device;
end

function effects.sync(s)
    local was = f_reveal;
    f_wave    = (s.fx_wave ~= false);
    f_reveal  = (s.fx_reveal ~= false);
    f_motes   = (s.fx_motes ~= false);
    any_dot   = f_wave or f_reveal;
    any_slot  = f_reveal or f_motes;
    local function n(k, d, lo, hi)
        local v = tonumber(s[k]) or d;
        if (v < lo) then v = lo; elseif (v > hi) then v = hi; end
        return v;
    end
    U.wave_sp, U.wave_d = 4 * n('fx_wave_speed', 1, 0.25, 3), n('fx_wave_depth', 25, 0, 60) / 100;
    U.reveal = n('fx_reveal_time', 0.6, 0.2, 3);
    U.mote_range = n('fx_motes_range', 35, 10, 80);
    local amt = n('fx_motes_amount', 100, 25, 200) / 100;
    U.mote_rate, U.mote_cap = MOTES_PER_Y * amt, math.min(MOTES_MAX, floor(24 * amt + 0.5));
    U.mote_rise = n('fx_motes_rise', 3.2, 1, 8);
    U.mote_start = n('fx_motes_start', 0.3, 0, 3);
    U.hover = tonumber(s.hover_height) or 0.5;
    if (f_reveal and not was) then
        for i = 1, SLOTS_N do slots[i].seen = -10; end   -- Relight every line.
    end
end

-- Once per draw.
function effects.frame()
    serial = serial + 1;
    gq = 0;
    nspr = 0;
end

function effects.reset_zone()
    for i = 1, SLOTS_N do
        local sl = slots[i];
        sl.owner = false; sl.last = -1e9; sl.seen = -10;
    end
    nspr = 0;
    dv = nil;
end

-- Premultiplied additive colour.
local function pm(r, g, b, k)
    if (k > 1) then k = 1; end
    return bit.tobit(floor(255 * k + 0.5) * 0x1000000 + floor(r * k + 0.5) * 0x10000
        + floor(g * k + 0.5) * 0x100 + floor(b * k + 0.5));
end

-- Alpha-test value.
local game_atest = 0;
function effects.set_atest(v) game_atest = v or 0; end

-- Untextured marker state.
local function marker_state(device)
    f_rs(device, RS_ATEST, game_atest);
    f_vs(device, FVF_PLAIN);
    f_tex(device, 0, nil);
    f_rs(device, RS_SRC, 5);   -- SRCALPHA
    f_rs(device, RS_DST, 6);   -- INVSRCALPHA
    f_rs(device, RS_ZWRITE, 1);
    f_tss(device, 0, TSS_COLOROP, TOP_SELECT1);
    f_tss(device, 0, TSS_COLORARG1, TA_DIFFUSE);
    f_tss(device, 0, TSS_ALPHAOP, TOP_SELECT1);
    f_tss(device, 0, TSS_ALPHAARG1, TA_DIFFUSE);
end

local function draw_batch(device)
    if (nspr == 0) then return; end
    local tex = textures.get('glow');
    if (tex == nil) then nspr = 0; return; end
    if (tex ~= glow_tex) then glow_tex = tex; glow_base = ffi.cast('IDirect3DBaseTexture8*', tex); end
    bind(device);
    f_vs(device, FVF_TEX);
    f_tex(device, 0, glow_base);
    f_rs(device, RS_SRC, 2);   -- ONE
    f_rs(device, RS_DST, 2);   -- ONE
    f_rs(device, RS_ZWRITE, 0);
    f_rs(device, RS_ATEST, 0);
    f_tss(device, 0, TSS_COLOROP, TOP_MODULATE);
    f_tss(device, 0, TSS_COLORARG1, TA_TEXTURE + TA_ALPHAREP);   -- texture alpha as colour
    f_tss(device, 0, TSS_COLORARG2, TA_DIFFUSE);
    f_tss(device, 0, TSS_ALPHAOP, TOP_MODULATE);
    f_tss(device, 0, TSS_ALPHAARG1, TA_TEXTURE);
    f_tss(device, 0, TSS_ALPHAARG2, TA_DIFFUSE);
    f_tss(device, 0, TSS_MAG, 2);   -- LINEAR
    f_tss(device, 0, TSS_MIN, 2);
    f_tss(device, 0, TSS_ADDRU, 3);   -- CLAMP
    f_tss(device, 0, TSS_ADDRV, 3);
    f_tss(device, 1, TSS_COLOROP, TOP_DISABLE);
    f_tss(device, 1, TSS_ALPHAOP, TOP_DISABLE);
    f_draw(device, D3DPT_TRIANGLELIST, nspr * 2, verts, VSIZE);
    nspr = 0;
    marker_state(device);
end

-- One camera-facing quad.
local function push(x, y, z, h, col)
    if (nspr >= MAX_SPRITES) then return; end   -- full: drop
    local rx, ry, rz, ux, uy, uz = Rx * h, Ry * h, Rz * h, Ux * h, Uy * h, Uz * h;
    local ax, ay, az = x - rx - ux, y - ry - uy, z - rz - uz;
    local bx, by, bz = x + rx - ux, y + ry - uy, z + rz - uz;
    local cx, cy, cz = x + rx + ux, y + ry + uy, z + rz + uz;
    local dx, dy, dz = x - rx + ux, y - ry + uy, z - rz + uz;
    local b = nspr * 36;
    vf[b]      = ax; vf[b + 1]  = ay; vf[b + 2]  = az; vi[b + 3]  = col;
    vf[b + 6]  = bx; vf[b + 7]  = by; vf[b + 8]  = bz; vi[b + 9]  = col;
    vf[b + 12] = cx; vf[b + 13] = cy; vf[b + 14] = cz; vi[b + 15] = col;
    vf[b + 18] = ax; vf[b + 19] = ay; vf[b + 20] = az; vi[b + 21] = col;
    vf[b + 24] = cx; vf[b + 25] = cy; vf[b + 26] = cz; vi[b + 27] = col;
    vf[b + 30] = dx; vf[b + 31] = dy; vf[b + 32] = dz; vi[b + 33] = col;
    nspr = nspr + 1;
    frame_spr = frame_spr + 1;
end

local function slot_of(zl)
    local id = zl.key;   -- stable across rebuilds
    if (id == nil) then id = zl; end
    local i = zl.fx_slot;
    if (i ~= nil and slots[i].owner == id) then return slots[i]; end
    for k = 1, SLOTS_N do
        if (slots[k].owner == id) then zl.fx_slot = k; return slots[k]; end
    end
    local best, bt = 1, 1e30;
    for k = 1, SLOTS_N do
        local sl = slots[k];
        if (sl.owner == false) then best = k; break; end
        if (sl.last < bt) then best, bt = k, sl.last; end
    end
    local sl = slots[best];
    sl.owner = id; sl.last = -1e9; sl.seen = -10; sl.g.n = -1;
    local m = sl.motes;
    for k = 1, MOTES_MAX do m.l[k] = rng() * 3; m.d[k] = 2 + rng() * 2.5; m.s[k] = rng(); m.o[k] = rng(); end
    zl.fx_slot = best;
    return sl;
end

-- One soft glow sprite.
function effects.glow(device, x, y, z, h, rgb, k, rx, ry, rz, ux, uy, uz)
    dev_ = device;
    Rx, Ry, Rz, Ux, Uy, Uz = rx, ry, rz, ux, uy, uz;
    push(x, y, z, h, pm(floor(rgb / 0x10000) % 0x100, floor(rgb / 0x100) % 0x100, rgb % 0x100, k));
end

-- 0 plain, 1 fan dots.
function effects.line(device, zl, cdata, dist, now, rx, ry, rz, ux, uy, uz, core, glow, size)
    if (not any_dot and not (f_motes and dist < U.mote_range)) then return 0; end
    local n = cdata.n;
    if (n < 1) then return 0; end
    dev_ = device;
    Rx, Ry, Rz, Ux, Uy, Uz = rx, ry, rz, ux, uy, uz;
    local cpx, cpy, cpz = cdata.px, cdata.py, cdata.pz;
    local rk = 1;
    if (zl.routes ~= nil and zl.alpha ~= nil) then rk = zl.alpha; end   -- Dimmed dock.
    local cr, cg, cb = floor(core / 0x10000) % 0x100, floor(core / 0x100) % 0x100, core % 0x100;
    local lx, lz = cpx[n] - cpx[1], cpz[n] - cpz[1];
    local len = sqrt(lx * lx + lz * lz);
    local step = (n > 1) and (len / (n - 1)) or 0;
    local mid = (n + 1) / 2;

    local sl, dt = nil, 0;
    if (any_slot) then
        sl = slot_of(zl);
        if (sl.seen ~= serial - 1 or now - sl.last > REENTER_S) then
            sl.rev = now;   -- Came into range.
        else
            dt = now - sl.last;
            if (dt > 0.05) then dt = 0.05; elseif (dt < 0) then dt = 0; end
        end
        sl.seen, sl.last = serial, now;
    end

    local mode = 0;
    if (any_dot) then
        mode = 1;
        local front = 1e9;
        if (f_reveal) then
            local p = (now - sl.rev) / U.reveal;
            if (p > 1) then p = 1; elseif (p < 0) then p = 0; end
            front = p * (len / 2 + REVEAL_EDGE);
        end
        local ca, ga = floor(core / 0x1000000) % 0x100, floor(glow / 0x1000000) % 0x100;
        local crgb, grgb = core % 0x1000000, glow % 0x1000000;
        for i = 1, n do
            local dc = abs(i - mid) * step;
            local a = 1;
            if (f_wave) then a = 1 - U.wave_d + U.wave_d * sin(now * U.wave_sp - dc * 0.9); end
            local s = 1;
            if (f_reveal) then
                local rv = (front - dc) / REVEAL_EDGE;
                if (rv <= 0) then rv = 0; elseif (rv >= 1) then rv = 1; else s = s * 1.6; end
                a = a * rv;
            end
            if (a > 1) then a = 1; end
            fs[i] = size * s;
            fc[i] = floor(ca * a + 0.5) * 0x1000000 + crgb;
            fg[i] = floor(ga * a + 0.5) * 0x1000000 + grgb;
        end
    end

    if (f_motes and dist < U.mote_range) then
        local m = sl.motes;
        local ml, md, ms, mo = m.l, m.d, m.s, m.o;
        local cnt = floor(len * U.mote_rate + 0.5);
        if (cnt > U.mote_cap) then cnt = U.mote_cap; end
        local near = 1 - dist / NEAR_FAR;
        if (near < 0) then near = 0; end
        local ma = (0.35 + 0.65 * near) * rk;
        local gy = floor_of(sl, cpx, cpy, cpz, n, lx, lz);
        for k = 1, cnt do
            local life = ml[k] + dt;
            if (life > md[k]) then life = 0; ms[k] = rng(); mo[k] = rng(); md[k] = 2 + rng() * 2.5; end
            ml[k] = life;
            local q, o, sk = life / md[k], mo[k], ms[k];
            local a = sin(PI * q) * ma;
            if (a > 0.002) then
                local f = sk * (GS - 1);
                local g0 = floor(f) + 1;
                local g1 = (g0 < GS) and g0 + 1 or GS;
                local a0, a1 = gy[g0], gy[g1];
                local fy;
                if (a0 and a1) then fy = a0 + (a1 - a0) * (f - g0 + 1);
                elseif (a0) then fy = a0;
                elseif (a1) then fy = a1;
                else fy = cpy[floor(sk * (n - 1) + 0.5) + 1] + U.hover; end   -- Floor unknown.
                push(cpx[1] + lx * sk + sin(now * 1.3 + o * 9) * 0.25,
                     fy - U.mote_start - q * U.mote_rise,
                     cpz[1] + lz * sk + cos(now * 1.1 + o * 7) * 0.25,
                     (0.35 + 0.25 * o) * SOFT_K, pm(cr, cg, cb, a));
                frame_motes = frame_motes + 1;
            end
        end
    end

    return mode;
end

local hand = 1;

-- Handedness, once per draw.
function effects.view(rx, rz, fx, fz)
    local c = rx * fz - rz * fx;   -- D3D is left-handed.
    if (c > 0.1) then hand = -1; elseif (c < -0.1) then hand = 1; end
end

-- Handedness: 1 or -1.
function effects.handed() return hand; end

-- Draw queued effects.
function effects.flush(device)
    draw_batch(device);
    effects.last_sprites, effects.last_motes = frame_spr, frame_motes;
    frame_spr, frame_motes = 0, 0;
end

-- Anything queued.
function effects.pending()
    return nspr > 0;
end

-- Drop the queue.
function effects.discard()
    nspr = 0;
    frame_spr, frame_motes = 0, 0;
end

-- Reveal fraction, 0..1.
function effects.reveal_fraction(zl, now)
    local i = zl.fx_slot;
    local id = zl.key;
    if (id == nil) then id = zl; end
    if (i == nil or slots[i].owner ~= id) then return nil; end
    local p = (now - slots[i].rev) / U.reveal;
    if (p > 1) then return 1; elseif (p < 0) then return 0; end
    return p;
end

return effects;
