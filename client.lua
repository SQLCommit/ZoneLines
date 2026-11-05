-- Reads from the game client.
local P = require 'world';
local bit = require 'bit';

local M = {};
local EPOCH = P.VANA_EPOCH;
local DAY = 86400;

local REGION_AOB = '8B4C240433C00FBF14C5????????3BD1740B403D92000000';     -- Zone to region.
local EXP_AOB    = '8B4C2404B801000000D3E08B0D????????8541147408854110';     -- Expansion check.
local TOAU_BIT   = 0x8;

local skew, skew_src = 0, 'built-in epoch';
local region, region_src = nil, nil;
local toau_ok, exp_words = true, nil;
local logged = {};

local function log(key, line)
    if (logged[key] == line) then return; end
    logged[key] = line;
    pcall(function() require('textures').log(line); end);
end

local function find(aob, off)
    local ok, p = pcall(ashita.memory.find, 'FFXiMain.dll', 0, aob, off or 0, 0);
    if (not ok or p == nil or p == 0) then return nil; end
    return p;
end

local function u8(a) return ashita.memory.read_uint8(a) or 0; end
local function u16(a) return ashita.memory.read_uint16(a) or 0; end
local function u32(a) return ashita.memory.read_uint32(a) or 0; end

-- Allowed clock skew.
local function take_skew(v, src)
    if (type(v) ~= 'number' or v ~= v or math.abs(v) > DAY) then return false; end
    skew, skew_src = math.floor(v + 0.5), src;
    log('clock', string.format('clock: %s, %+d s from the built-in epoch', src, skew));
    return true;
end

-- Zone-in game time.
function M.on_00a(data, now)
    if (type(data) ~= 'string' or #data < 0x40) then return; end
    local b1, b2, b3, b4 = data:byte(0x3D, 0x40);
    local gt = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216;
    if (gt >= 1e8) then take_skew(gt - (now - EPOCH), 'zone-in packet'); end
    M.read_expansions();
end

-- Server clock offset.
function M.skew() return skew; end
function M.skew_source() return skew_src; end

-- Client zone-region table.
local function read_regions()
    local p = find(REGION_AOB, 0x0A);
    if (p == nil) then return nil, 'signature not found'; end
    local base = u32(p) - 2;
    if (base < 0x10000) then return nil, 'table address invalid'; end
    local out, n = {}, 0;
    for r = 0, 145 do
        local a = base + r * 8;
        local key, zone, strict = u16(a), u16(a + 2), u16(a + 4);
        if (key >= 5 and key <= 23 and strict ~= 0xFFFF and zone > 0 and zone < 1024) then
            out[zone] = key - 5;
            n = n + 1;
        end
    end
    if (n < 100) then return nil, n .. ' rows'; end
    return out, n .. ' zones';
end

function M.region_of(zone)
    if (region == nil) then
        local ok, t, why = pcall(read_regions);
        if (ok and t ~= nil) then
            region, region_src = t, 'client table';
        else
            region, region_src = P.REGION_OF_ZONE, 'built-in';
        end
        log('region', 'regions: ' .. region_src .. ' (' .. tostring(ok and why or t) .. ')');
    end
    return region[zone];
end

-- Expansion words.
function M.read_expansions()
    local ok, a, b = pcall(function()
        local p = find(EXP_AOB, 13);
        if (p == nil) then return nil; end
        local g = u32(p);
        if (g < 0x10000) then return nil; end
        local obj = u32(g);
        if (obj < 0x10000) then return nil; end
        return u32(obj + 0x10), u32(obj + 0x14);
    end);
    if (not ok or a == nil) then
        toau_ok, exp_words = true, nil;
        log('exp', 'expansions: not read, ToAU assumed');
        return;
    end
    exp_words = { a, b };
    local any = bit.bor(a, b);
    toau_ok = (any == 0) or bit.band(any, TOAU_BIT) ~= 0;
    log('exp', string.format('expansions: %08X %08X, ToAU %s', a, b, toau_ok and 'on' or 'off'));
end

function M.toau() return toau_ok; end

-- Can this character ride.
function M.run_ok(run) return toau_ok or not run.toau; end

function M.init()
    log('clock', 'clock: built-in epoch until zone-in');
    M.region_of(0);
    M.read_expansions();
end

-- Test hook.
function M.reset()
    skew, skew_src, region, region_src, toau_ok, exp_words = 0, 'built-in epoch', nil, nil, true, nil;
    logged = {};
end

return M;
