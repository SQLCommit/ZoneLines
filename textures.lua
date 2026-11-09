-- Procedural effect textures.
local ffi   = require 'ffi';
local d3d8  = require 'd3d8';

local textures = {};

local D3DFMT_A8R8G8B8, D3DPOOL_MANAGED = 21, 1;
local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max;

local cache  = {};    -- name -> texture
local failed = {};    -- Failed names, never retried.
local n_cached = 0;

-- Log one line.
local LOG_MAX, LOG_KEEP = 256 * 1024, 64 * 1024;   -- Trim size, kept tail.
local log_path, log_trimmed = nil, false;
function textures.log(line)
    pcall(function()
        if (log_path == nil) then log_path = AshitaCore:GetInstallPath() .. 'logs\\zonelines.log'; end
        if (not log_trimmed) then   -- Keep newest lines only.
            log_trimmed = true;
            local fh = io.open(log_path, 'rb');
            if (fh ~= nil) then
                local n = fh:seek('end');
                local tail = nil;
                if (n > LOG_MAX) then fh:seek('set', n - LOG_KEEP); tail = fh:read('*a'); end
                fh:close();
                if (tail ~= nil) then
                    local out = io.open(log_path, 'wb');
                    if (out ~= nil) then out:write((tail:gsub('^[^\n]*\n', ''))); out:close(); end
                end
            end
        end
        local fh = io.open(log_path, 'ab');
        if (fh ~= nil) then fh:write(os.date('%Y-%m-%d %H:%M:%S '), line, '\n'); fh:close(); end
    end);
end

-- Stage-0 texture held by D3D.
local sb_tok = ffi.new('DWORD[1]');
function textures.hold(dev)
    local vt = dev.lpVtbl;
    if (vt.BeginStateBlock(dev) ~= 0) then return nil; end
    vt.SetTexture(dev, 0, nil);   -- Recorded, not applied.
    if (vt.EndStateBlock(dev, sb_tok) ~= 0) then return nil; end
    local sb = sb_tok[0];
    if (vt.CaptureStateBlock(dev, sb) ~= 0) then vt.DeleteStateBlock(dev, sb); return nil; end
    return sb;
end

function textures.restore(dev, sb)
    dev.lpVtbl.ApplyStateBlock(dev, sb);
    dev.lpVtbl.DeleteStateBlock(dev, sb);
end

local function log_once(name, why)
    failed[name] = true;
    textures.log('texture ' .. name .. ': ' .. why);
end

-- Recipes write alpha per pixel.
local function smooth(t) if (t <= 0) then return 0; elseif (t >= 1) then return 1; end return t * t * (3 - 2 * t); end

local function glow(w, h, put)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local dx, dy = (x + 0.5 - w / 2) / (w / 2), (y + 0.5 - h / 2) / (h / 2);
            local q = 1 - (dx * dx + dy * dy);
            put(x, y, (q > 0) and (q * q) or 0);
        end
    end
end

-- Tileable value noise.
local function cloud(w, h, put)
    local seed = 12345;
    local octs, amp_sum = {}, 0;
    for o = 0, 3 do
        local g, amp, lat = 4 * 2 ^ o, 0.5 ^ o, {};
        for i = 0, g * g - 1 do
            seed = (seed * 16807) % 2147483647;
            lat[i] = seed / 2147483647;
        end
        octs[o + 1] = { g = g, amp = amp, lat = lat };
        amp_sum = amp_sum + amp;
    end
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local v = 0;
            for _, o in ipairs(octs) do
                local g = o.g;
                local fx, fy = x / w * g, y / h * g;
                local x0, y0 = floor(fx), floor(fy);
                local tx, ty = smooth(fx - x0), smooth(fy - y0);
                local x1, y1 = (x0 + 1) % g, (y0 + 1) % g;
                x0, y0 = x0 % g, y0 % g;
                local lat = o.lat;
                local a = lat[y0 * g + x0] + (lat[y0 * g + x1] - lat[y0 * g + x0]) * tx;
                local b = lat[y1 * g + x0] + (lat[y1 * g + x1] - lat[y1 * g + x0]) * tx;
                v = v + (a + (b - a) * ty) * o.amp;
            end
            put(x, y, v / amp_sum);
        end
    end
end

-- Distance to a segment.
local function seg_dist(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay;
    local t = max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)));
    local dx, dy = px - (ax + vx * t), py - (ay + vy * t);
    return sqrt(dx * dx + dy * dy);
end

-- Chevron per tile.
local function chevron(w, h, put)
    local ax, ay = w / 2, 3.5;
    local lx, rx, ey = 6, w - 6, h - 3.5;
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local px, py = x + 0.5, y + 0.5;
            local d = min(seg_dist(px, py, ax, ay, lx, ey), seg_dist(px, py, ax, ay, rx, ey));
            local a = 1 - smooth((d - 1.5) / 2);
            put(x, y, a * (1 - 0.45 * abs(px - ax) / (w / 2 - 6)));
        end
    end
end

-- Vertical fade, clear to solid.
local function sheet(w, h, put)
    for y = 0, h - 1 do
        local a = (y / (h - 1)) ^ 1.5;
        for x = 0, w - 1 do put(x, y, a); end
    end
end

-- Aurora streaks.
local function aurora(w, h, put)
    local seed = 4242;
    local function r() seed = (seed * 16807) % 2147483647; return seed / 2147483647; end
    local v = ffi.new('double[?]', w * h);
    for _ = 1, 90 do
        local x0, wd, a, top = r() * w, 1 + r() * 5, 0.15 + r() * 0.6, h * r() * 0.25;
        for y = 0, h - 1 do
            local k = (y + 0.5 - top) / (h - top);   -- 0 top, 1 bottom.
            if (k > 0) then
                for xi = floor(x0), math.ceil(x0 + wd) - 1 do
                    local cov = min(xi + 1, x0 + wd) - max(xi, x0);
                    if (cov > 0) then
                        local i = y * w + xi % w;
                        v[i] = v[i] + a * k * cov * (1 - v[i]);   -- white over black
                    end
                end
            end
        end
    end
    local wt, ws = {}, 0;
    for d = -6, 6 do wt[d] = math.exp(-d * d / 12.5); ws = ws + wt[d]; end
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local acc = 0;
            for d = -6, 6 do acc = acc + v[y * w + (x + d) % w] * wt[d]; end
            put(x, y, acc / ws);
        end
    end
end

-- Ribbon band.
local BAND = { { 0, 1 }, { 0.09, 1 }, { 0.12, 70 / 255 }, { 0.5, 28 / 255 }, { 0.88, 70 / 255 }, { 0.91, 150 / 255 }, { 1, 0 } };
local function band(w, h, put)
    for y = 0, h - 1 do
        local t, a = (y + 0.5) / h, 0;
        for i = 1, #BAND - 1 do
            local p, q = BAND[i], BAND[i + 1];
            if (t >= p[1] and t <= q[1]) then a = p[2] + (q[2] - p[2]) * (t - p[1]) / (q[1] - p[1]); break; end
        end
        for x = 0, w - 1 do put(x, y, a); end
    end
end

local RECIPES = {
    glow    = { 64, 64, glow },
    cloud   = { 128, 128, cloud },
    chevron = { 64, 16, chevron },
    sheet   = { 16, 64, sheet },
    aurora  = { 256, 128, aurora },
    band    = { 4, 128, band },
};

local function build(name)
    local r = RECIPES[name];
    if (r == nil) then return nil; end
    local w, h, fill = r[1], r[2], r[3];
    local dev = d3d8.get_device();
    if (dev == nil) then log_once(name, 'no device'); return nil; end
    local res, tex = dev:CreateTexture(w, h, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED);
    if (res ~= 0 or tex == nil) then log_once(name, 'CreateTexture failed'); return nil; end
    local lres, lock = tex:LockRect(0, nil, 0);
    if (lres ~= 0 or lock == nil or lock.pBits == nil) then
        tex:Release();
        log_once(name, 'LockRect failed');
        return nil;
    end
    local buf = ffi.new('uint8_t[?]', w * h * 4);
    fill(w, h, function(x, y, a)
        local i = (y * w + x) * 4;
        buf[i] = 255; buf[i + 1] = 255; buf[i + 2] = 255;
        buf[i + 3] = floor(max(0, min(1, a)) * 255 + 0.5);
    end);
    local dest = ffi.cast('uint8_t*', lock.pBits);
    for y = 0, h - 1 do
        ffi.copy(dest + y * lock.Pitch, buf + y * w * 4, w * 4);
    end
    tex:UnlockRect(0);
    return d3d8.gc_safe_release(tex);
end

function textures.get(name)
    local t = cache[name];
    if (t ~= nil) then return t; end
    if (failed[name]) then return nil; end
    t = build(name);
    if (t ~= nil) then cache[name] = t; n_cached = n_cached + 1; end
    return t;
end

function textures.count() return n_cached; end

-- Explicit texture release.
function textures.release_all()
    for name, t in pairs(cache) do
        ffi.gc(t, nil);
        pcall(function() t:Release(); end);
        cache[name] = nil;
    end
    n_cached = 0;
end

return textures;
