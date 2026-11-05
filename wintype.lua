-- Window Type setting and skin.
local ffi      = require 'ffi';
local d3d8     = require 'd3d8';
local textures = require 'textures';

local wintype = {};

local FILE0, D3DPOOL_MANAGED = 14, 1;
local FMT = { [0x44585431] = 0x31545844, [0x44585433] = 0x33545844 };   -- DAT '1TXD' -> D3DFMT_DXT1, DXT3
local SIG = '8B0D????????85C974108B4424088B5424045052E8????????C383C8FFC3';
local NAMES = { ['newtex  '] = 1, ['hfr1    '] = 2, ['corner  '] = 3, ['vfr1    '] = 4 };
local ORDER = { 5, 1, 2, 3, 4, 6, 7, 8, 9 };   -- File order to piece.
local RECHECK = 2;                             -- seconds between setting reads

local skins = {};          -- type to skin, or false.
local slot = nil;          -- Config pointer slot.
local cur, read_at = 0, -1e9;

local function log(line) textures.log('wintype: ' .. line); end

local function u16(s, o) local a, b = s:byte(o + 1, o + 2); return a + b * 256; end
local function u32(s, o)
    local a, b, c, d = s:byte(o + 1, o + 4);
    return a + b * 256 + c * 65536 + d * 16777216;
end

-- DAT vertex colour to ARGB.
local function vcol(c)
    local a, b, g, r = math.floor(c / 16777216), math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256;
    r, g, b = math.min(255, r + 1), math.min(255, g + 1), math.min(255, b + 1);
    if (a ~= 0 and a ~= 255) then a = math.min(255, math.floor((a + 1) * 3 / 2)); end
    return ((a * 256 + r) * 256 + g) * 256 + b;
end

-- Current type, 0 to 7.
function wintype.current(now)
    if (now ~= nil and now - read_at < RECHECK) then return cur; end
    read_at = now or 0;
    pcall(function()
        if (slot == nil) then
            slot = false;
            local m = ashita.memory.find('FFXiMain.dll', 0, SIG, 0, 0);
            if (m ~= nil and m ~= 0 and ashita.memory.find('FFXiMain.dll', 0, SIG, 0, 1) == 0) then
                slot = ashita.memory.read_uint32(m + 2);
            end
            if (not slot or slot == 0) then slot = false; log('setting not found, Type 1'); end
        end
        if (not slot) then return; end
        local cfg = ashita.memory.read_uint32(slot);
        if (cfg == nil or cfg < 0x10000) then return; end
        local tab = ashita.memory.read_uint32(cfg + 4);
        if (tab == nil or tab < 0x10000) then return; end
        local r = tab + 0x12 * 44;
        local id, t = ashita.memory.read_uint32(r + 4), ashita.memory.read_uint32(r + 8);
        if (id == 0x12 and t ~= nil and t < 8 and ashita.memory.read_uint32(r + 24) == 0 and ashita.memory.read_uint32(r + 28) == 7) then
            cur = t;
        end
    end);
    return cur;
end

-- Parse textures and pieces.
local function parse(s)
    local tex, piece, p = {}, nil, 0;
    while (p + 16 <= #s) do
        local v = u32(s, p + 4);
        local ty, size = v % 128, (math.floor(v / 128) % 1048576) * 16;
        if (size < 16 or p + size > #s) then return nil, 'bad chunk size'; end
        local st = p + 16;
        if (ty == 0x20 and size >= 16 + 0x45) then
            local i = NAMES[s:sub(st + 10, st + 17)];
            if (i ~= nil) then
                if (s:byte(st + 1) ~= 0xA1) then return nil, 'texture header'; end
                local w, h, fmt = u32(s, st + 0x15), u32(s, st + 0x19), FMT[u32(s, st + 0x39)];
                local bs = (fmt == 0x33545844) and 16 or 8;
                if (fmt == nil or w < 4 or h < 4 or w > 512 or h > 512 or w % 4 ~= 0 or h % 4 ~= 0) then
                    return nil, 'texture format';
                end
                local n = w / 4 * h / 4 * bs;
                if (st + 0x45 + n > p + size) then return nil, 'texture size'; end
                tex[i] = { w = w, h = h, fmt = fmt, bs = bs, data = s:sub(st + 0x46, st + 0x45 + n) };
            end
        elseif (ty == 0x31 and size >= 33) then
            local ca = st + 17 + s:byte(st + 17) * 16;
            if (ca + 2 > p + size or u16(s, ca) < 9 or ca + 2 + 9 * 62 > p + size) then return nil, 'window definition'; end
            piece = {};
            for k = 1, 9 do
                local at = ca + 2 + (k - 1) * 62;
                local c = {};
                for j = 1, 4 do c[j] = vcol(u32(s, at + 26 + (j - 1) * 4)); end
                local q = { tex = NAMES[s:sub(at + 55, at + 62)], w = u16(s, at + 17), h = u16(s, at + 19),
                    u = u16(s, at + 21), v = u16(s, at + 23), add = s:byte(at + 45) == 2, col = c };
                if (q.tex == nil or q.w == 0 or q.h == 0 or q.w > 512 or q.h > 512) then return nil, 'window piece'; end
                piece[ORDER[k]] = q;
            end
        end
        p = p + size;
    end
    if (piece == nil) then return nil, 'no window definition'; end
    for i = 1, 4 do if (tex[i] == nil) then return nil, 'missing texture'; end end
    return tex, piece;
end

local function upload(dev, t)
    local res, out = dev:CreateTexture(t.w, t.h, 1, 0, t.fmt, D3DPOOL_MANAGED);
    if (res ~= 0 or out == nil) then return nil; end
    local lres, lock = out:LockRect(0, nil, 0);
    if (lres ~= 0 or lock == nil or lock.pBits == nil) then out:Release(); return nil; end
    local row = t.w / 4 * t.bs;
    local src, dst = ffi.cast('const uint8_t*', t.data), ffi.cast('uint8_t*', lock.pBits);
    for y = 0, t.h / 4 - 1 do ffi.copy(dst + y * lock.Pitch, src + y * row, row); end
    out:UnlockRect(0);
    return d3d8.gc_safe_release(out);
end

local function load(n)
    local dev = d3d8.get_device();
    if (dev == nil) then return nil; end
    skins[n] = false;
    local path = nil;
    pcall(function() path = AshitaCore:GetResourceManager():GetFilePath(FILE0 + n); end);
    if (type(path) ~= 'string' or path == '') then log('no DAT path for type ' .. (n + 1)); return nil; end
    local fh = io.open(path, 'rb');
    if (fh == nil) then log('cannot open ' .. path); return nil; end
    local s = fh:read('*a');
    fh:close();
    local ok, tex, piece = pcall(parse, s or '');
    if (not ok or tex == nil) then log('type ' .. (n + 1) .. ': ' .. tostring(piece or tex)); return nil; end
    -- Type 7 right edge.
    local r, l = piece[6], piece[4];
    if (n == 6 and r.add and not l.add and r.col[1] == 0xC0808080 and l.col[1] == 0x91616161) then
        r.col, r.add = { l.col[1], l.col[2], l.col[3], l.col[4] }, false;
    end
    local skin = { tex = {}, tw = {}, th = {}, piece = piece, corner = piece[1].w, edge = piece[2].h };
    for i = 1, 4 do
        skin.tex[i] = upload(dev, tex[i]);
        if (skin.tex[i] == nil) then log('type ' .. (n + 1) .. ': texture failed'); return nil; end
        skin.tw[i], skin.th[i] = tex[i].w, tex[i].h;
    end
    skins[n] = skin;
    return skin;
end

-- Skin of the player's type.
function wintype.skin(now)
    local n = wintype.current(now);
    local k = skins[n];
    if (k == nil) then k = load(n); end
    return k or nil;
end

-- Release skin textures.
function wintype.release()
    for n, k in pairs(skins) do
        if (k) then
            for i = 1, 4 do
                local t = k.tex[i];
                if (t ~= nil) then ffi.gc(t, nil); pcall(function() t:Release(); end); end
            end
        end
        skins[n] = nil;
    end
end

-- Forget scan and last read.
function wintype.reset() slot, cur, read_at = nil, 0, -1e9; wintype.release(); end

return wintype;
