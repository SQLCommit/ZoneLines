-- Floor query for motes.
local ffi      = require 'ffi';
local bit      = require 'bit';
local textures = require 'textures';

local ground = {};

local mem = ashita.memory;
local abs = math.abs;

-- Query signature.
local SIG = 'D9442408538B442414568B5C2414578B7C242057' ..
    '50D91FD944241CD825????????53518BF18B4C2420D91C24518BCEE84CFFFFFF84C07521D9442414D805????????' ..
    '8B5424105768000070C153518BCED91C2452E827FFFFFF5F5E5BC21400';
local CONST_A, CONST_B, CALL_AT = 0x1D, 0x3E, 0x2F;
local CALLEE_HEAD = { 0x83, 0xEC, 0x24, 0x8B, 0x44, 0x24, 0x28, 0x81, 0xC1, 0x78, 0x01, 0x00, 0x00 };
local MGR, HIT_PTR, HIT_META, META_N = 0x178, 0x1807C, 0x3413C, 0x24;
local LEN = 50.0;                    -- Query length.
local RAISE, REACH, FAR = 3.0, 2.0, 6.0;   -- Raise, near step, give up.

pcall(ffi.cdef, 'typedef int32_t (__thiscall* zl_ground_f)(void*, float, float, float, float, float*);');

local fn, zone_var = nil, 0;
local SETTLE = 1.0;                  -- Seconds after player shows.
local held, shown_at = false, nil;   -- Zone loading hold.
local state = 0;                     -- Unresolved, ready, off.
local out = ffi.new('float[1]');
local keep = ffi.new('uint8_t[?]', META_N);

local function off(why)
    state = -1;
    textures.log('ground: ' .. why .. '; motes keep the line height');
end

-- Zone pointer from callers.
local function zone_scan(base, size, fn_off)
    local p = ffi.cast('const uint8_t*', base);
    local var, agree, other = 0, 0, 0;
    for i = 6, size - 5 do
        if (p[i] == 0xE8) then
            local rel = ffi.cast('const int32_t*', p + i + 1)[0];
            if (i + 5 + rel == fn_off) then
                for j = i - 6, math.max(0, i - 40), -1 do
                    if (p[j] == 0x8B and p[j + 1] == 0x0D) then
                        local imm = ffi.cast('const uint32_t*', p + j + 2)[0];
                        if (agree == 0) then var = imm; end
                        if (imm == var) then agree = agree + 1; else other = other + 1; end
                        break;
                    end
                end
            end
        end
    end
    return var, agree, other;
end

local function resolve()
    local base, size = mem.get_base('FFXiMain.dll') or 0, mem.get_size('FFXiMain.dll') or 0;
    if (base == 0 or size == 0) then return off('FFXiMain.dll not found'); end
    local hit = mem.find('FFXiMain.dll', 0, SIG, 0, 0);
    if (hit == 0) then return off('floor query not found'); end
    if (mem.find('FFXiMain.dll', 0, SIG, 0, 1) ~= 0) then return off('floor query not unique'); end
    local o = hit - base;
    local rel = mem.read_int32(hit + CALL_AT + 1);
    local callee = hit + CALL_AT + 5 + rel;
    if (callee < base or callee + #CALLEE_HEAD > base + size) then return off('floor callee outside the image'); end
    for k = 1, #CALLEE_HEAD do
        if (mem.read_uint8(callee + k - 1) ~= CALLEE_HEAD[k]) then return off('floor callee differs'); end
    end
    local ca, cb = mem.read_uint32(hit + CONST_A), mem.read_uint32(hit + CONST_B);
    if (ca ~= cb or ca < base or ca + 4 > base + size or abs(mem.read_float(ca) - 0.51) > 1e-6) then
        return off('floor constant differs');
    end
    local var, agree, other = zone_scan(base, size, o);
    if (agree < 3 or other ~= 0 or var < base or var + 4 > base + size) then
        return off(string.format('zone pointer unclear (%d agree, %d differ)', agree, other));
    end
    fn = ffi.cast('zl_ground_f', hit);
    zone_var = var;
    state = 1;
    textures.log(string.format('ground: query RVA %X, zone pointer RVA %X (%d calls agree)', o, var - base, agree));
end

-- One floor query.
local function query(zone, x, start, z)
    local m = zone + MGR;
    local hp = ffi.cast('uint32_t*', m + HIT_PTR);
    local kp = hp[0];
    ffi.copy(keep, ffi.cast('void*', m + HIT_META), META_N);
    local r = fn(ffi.cast('void*', zone), x, start, z, LEN, out);
    hp[0] = kp;
    ffi.copy(ffi.cast('void*', m + HIT_META), keep, META_N);
    if (bit.band(r, 0xFF) == 0) then return nil; end
    return out[0];
end

-- Hold until zone loads.
function ground.hold() held, shown_at = true, nil; end

function ground.settled()
    if (not held) then return true; end
    local mm = AshitaCore:GetMemoryManager();
    local idx = mm and mm:GetParty():GetMemberTargetIndex(0) or 0;
    if (idx == 0 or (mm:GetEntity():GetRenderFlags0(idx) or 0) == 0) then shown_at = nil; return false; end
    local now = os.clock();
    if (shown_at == nil) then shown_at = now; end
    if (now - shown_at < SETTLE) then return false; end
    held = false;
    return true;
end

-- Floor height under point.
function ground.at(x, expect, z)
    if (state == 0) then resolve(); end
    if (state ~= 1 or not ground.settled()) then return nil; end
    local zone = mem.read_uint32(zone_var);
    if (zone < 0x10000) then return nil; end
    local yl = query(zone, x, expect - 0.5, z);
    if (yl ~= nil and abs(yl - expect) <= REACH) then return yl; end
    local yh = query(zone, x, expect - RAISE, z);
    local y = yl;
    if (yh ~= nil and (yl == nil or abs(yh - expect) < abs(yl - expect))) then y = yh; end
    if (y == nil or abs(y - expect) > FAR) then return nil; end
    return y;
end

function ground.ready() return state == 1; end

return ground;
