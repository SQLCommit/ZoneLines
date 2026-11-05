-- Nation and beastmen crest textures.
local ffi      = require 'ffi';
local d3d8     = require 'd3d8';
local textures = require 'textures';
local conquest = require 'conquest';

local crests = {};

local FILE_ID, D3DFMT_DXT1, D3DPOOL_MANAGED = 39542, 0x31545844, 1;
local HD = 128;                   -- HD PNG size.
local WANT = { scre = true, bcre = true, wcre = true, mcre = true };

local tex, tw, th = {}, {}, {};   -- Name to texture.
local state = 0;                  -- Load state.

local function log(line) textures.log('crest: ' .. line); end

local function u32(s, o)
    local a, b, c, d = s:byte(o + 1, o + 4);
    return a + b * 256 + c * 65536 + d * 16777216;
end

-- Crests from DAT chunks.
local function parse(fh, want)
    local len = fh:seek('end');
    local found, p, depth = {}, 0, 0;
    while (p + 16 <= len) do
        fh:seek('set', p);
        local head = fh:read(16);
        if (head == nil or #head < 16) then return nil, 'short read'; end
        local v = u32(head, 4);
        local ty, size = v % 128, (math.floor(v / 128) % 524288) * 16;
        if (ty == 0) then
            depth = depth - 1;
            if (depth <= 0) then
                if (p + size ~= len) then return nil, 'END chunk not at end of file'; end
                return found;
            end
        elseif (ty == 1) then
            depth = depth + 1;
        elseif (ty == 32 and size >= 16 + 0x45) then
            local pl = fh:read(0x45);
            if (pl ~= nil and #pl == 0x45 and pl:byte(1) == 0xA1 and pl:sub(2, 9) == 'menu    ') then
                local name = pl:sub(10, 17):gsub(' +$', '');
                if (want[name]) then
                    local w, h, dsize = u32(pl, 0x15), u32(pl, 0x19), u32(pl, 0x3D);
                    if (pl:sub(0x3A, 0x3D) ~= '1TXD') then return nil, name .. ' is not DXT1'; end
                    if (w < 4 or h < 4 or w > 256 or h > 256 or w % 4 ~= 0 or h % 4 ~= 0
                        or dsize ~= w / 4 * h / 4 * 8 or u32(pl, 0x41) ~= w / 4 * 8 or size < 16 + 0x45 + dsize) then
                        return nil, name .. ' has an unexpected layout';
                    end
                    local blocks = fh:read(dsize);
                    if (blocks == nil or #blocks ~= dsize) then return nil, 'short read'; end
                    found[name] = { w = w, h = h, data = blocks };
                end
            end
        end
        if (size < 16) then return nil, 'chunk size 0'; end
        p = p + size;
    end
    return nil, 'no END chunk';
end

-- DXT1 blocks into texture.
local function make(c)
    local dev = d3d8.get_device();
    if (dev == nil) then return nil, 'no device'; end
    local res, t = dev:CreateTexture(c.w, c.h, 1, 0, D3DFMT_DXT1, D3DPOOL_MANAGED);
    if (res ~= 0 or t == nil) then return nil, 'CreateTexture failed'; end
    local lres, lock = t:LockRect(0, nil, 0);
    if (lres ~= 0 or lock == nil or lock.pBits == nil) then
        t:Release();
        return nil, 'LockRect failed';
    end
    local row = c.w / 4 * 8;
    local src = ffi.cast('const uint8_t*', c.data);
    local dest = ffi.cast('uint8_t*', lock.pBits);
    for y = 0, c.h / 4 - 1 do
        ffi.copy(dest + y * lock.Pitch, src + y * row, row);
    end
    t:UnlockRect(0);
    return d3d8.gc_safe_release(t);
end

-- HD crest PNG, if present.
local function load_hd(dev, name)
    local dir = crests.dir;
    if (dir == nil) then pcall(function() dir = addon.path .. '\\crests\\'; end); crests.dir = dir; end
    if (dir == nil) then return nil; end
    local path = dir .. name .. '.png';
    if (not ashita.fs.exists(path)) then return nil; end
    local ptr = ffi.new('IDirect3DTexture8*[1]');
    if (ffi.C.D3DXCreateTextureFromFileA(dev, path, ptr) ~= ffi.C.S_OK or ptr[0] == nil) then
        return nil, 'cannot load ' .. path;
    end
    return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
end

local function load()
    local dev = d3d8.get_device();
    if (dev == nil) then return; end
    state = 2;
    local missing, any = {}, false;
    for name in pairs(WANT) do
        local t, err = load_hd(dev, name);
        if (t ~= nil) then
            tex[name], tw[name], th[name] = t, HD, HD;
        else
            if (err ~= nil) then log(err); end
            missing[name], any = true, true;
        end
    end
    if (not any) then state = 1; return; end
    local path = nil;
    pcall(function() path = AshitaCore:GetResourceManager():GetFilePath(FILE_ID); end);
    if (type(path) ~= 'string' or path == '') then log('no DAT path'); return; end
    local fh = io.open(path, 'rb');
    if (fh == nil) then log('cannot open ' .. path); return; end
    local ok, found, why = pcall(parse, fh, missing);
    fh:close();
    if (not ok) then log('parse error: ' .. tostring(found)); return; end
    if (found == nil) then log(tostring(why)); return; end
    for name in pairs(missing) do
        local c = found[name];
        if (c == nil) then
            log(name .. ' not in the DAT');
        else
            local t, err = make(c);
            if (t == nil) then
                if (err == 'no device') then state = 0; return; end
                log(name .. ': ' .. tostring(err));
            else
                tex[name], tw[name], th[name] = t, c.w, c.h;
            end
        end
    end
    state = 1;
end

-- Crest texture by name.
function crests.get(name)
    if (state == 0) then load(); end
    return tex[name], tw[name], th[name];
end

-- Crest name for zone.
function crests.of(zone) return conquest.crest(zone); end

-- Cancel finalizer first.
function crests.release()
    for name, t in pairs(tex) do
        ffi.gc(t, nil);
        pcall(function() t:Release(); end);
        tex[name], tw[name], th[name] = nil, nil, nil;
    end
    state = 0;
end

return crests;
