-- Conquest owners and tally timing.
local P        = require 'world';
local client   = require 'client';
local settings = require 'settings';
local textures = require 'textures';

local conquest = {};

local REQUEST_DELAY, WEEK, VANA_DAY, MAX_TRIES = 10, 604800, 3456, 2;
-- Conquest model setter.
local MODEL_AOB = '568B74240857B92C000000BF????????F3A5';

local c = nil;             -- Conquest state.
local armed, arm_at = false, 0;
local warned, tally_warned = false, false;

local function log(line) textures.log('conquest: ' .. line); end

local function save() pcall(settings.save); end

-- Owners are 1-based.
local function valid_owners(o)
    if (type(o) ~= 'table') then return false; end
    for i = 1, 19 do
        local v = rawget(o, i);
        if (type(v) ~= 'number' or v < 0 or v > 4) then return false; end
    end
    return true;
end

local function from_memory(now)
    local ok, why = pcall(function()
        local p = ashita.memory.find('FFXiMain.dll', 0, MODEL_AOB, 0x0C, 0);
        if (p == nil or p == 0) then return 'signature not found'; end
        local model = ashita.memory.read_uint32(p);
        if (model == nil or model < 0x10000) then return 'model address invalid'; end
        if (ashita.memory.read_uint8(model - 0x0C) ~= 1) then return 'model not loaded'; end
        local o = {};
        for r = 0, 18 do
            local v = ashita.memory.read_uint8(model + 0x19 + 4 * r);
            if (v == nil or v > 4) then return 'owner byte out of range'; end
            o[r + 1] = v;
        end
        c.owners = o;
        c.at = now;
        return nil;
    end);
    if (not ok) then why = 'read failed'; end
    if (why ~= nil) then log('client memory unused (' .. tostring(why) .. ')'); end
end

local function num(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge; end

-- Drop bad stored fields.
local function sanitize(now)
    if (not valid_owners(rawget(c, 'owners'))) then c.owners = nil; end
    if (not num(rawget(c, 'at'))) then c.at = nil; end
    local nt, ft, ru = rawget(c, 'next_tally'), rawget(c, 'first_try'), rawget(c, 'retry_until');
    if (not num(nt) or nt > now + WEEK) then c.next_tally = nil; end
    if (not num(ft) or ft > now) then c.first_try = nil; end
    if (not num(ru) or ru > now + WEEK) then c.retry_until = nil; end
    local tr = rawget(c, 'tries');
    if (not num(tr) or tr < 0 or tr ~= math.floor(tr) or c.retry_until == nil) then c.tries = 0; c.first_try = nil; c.retry_until = nil; end
end

-- Keep the character's store.
function conquest.bind(s)
    local t = (s ~= nil) and rawget(s, 'conquest') or nil;
    if (s ~= nil and type(t) ~= 'table') then t = T{}; s.conquest = t; end
    c = t;
    if (c ~= nil) then sanitize(os.time()); end
end

function conquest.init(s)
    conquest.bind(s);
    if (c ~= nil and c.owners == nil) then from_memory(os.time()); end
end

function conquest.on_05e(data, now)
    if (c == nil or type(data) ~= 'string' or #data < 0x8D) then return; end
    local o = {};
    for r = 0, 18 do
        local v = data:byte(0x1D + 4 * r + 1);
        if (v > 4) then
            if (not warned) then warned = true; log('0x05E owner byte out of range, ignored'); end
            return;
        end
        o[r + 1] = v;
    end
    -- Days to vana midnight.
    local rule = P.next_tally(now);
    local days = data:byte(0x8D);
    local nt = rule;
    if (days >= 1 and days <= 200) then
        local sk = client.skew();
        local vana = now - P.VANA_EPOCH + sk;
        nt = (math.floor(vana / VANA_DAY) + 1 + days - 1) * VANA_DAY + P.VANA_EPOCH - sk;
    end
    if (math.abs(nt + client.skew() - rule) > 60 and not tally_warned) then   -- Same clock as rule.
        tally_warned = true;
        log('tally days ' .. tostring(days) .. ' differs from the Monday rule (' .. tostring(math.ceil((rule - now) / VANA_DAY)) .. ')');
    end
    local changed = c.next_tally ~= nt or (c.tries or 0) ~= 0 or not valid_owners(c.owners);
    if (not changed) then
        for i = 1, 19 do if (c.owners[i] ~= o[i]) then changed = true; break; end end
    end
    c.owners, c.at, c.next_tally, c.tries, c.first_try, c.retry_until = o, now, nt, 0, nil, nil;
    if (changed) then save(); end
end

function conquest.on_zone_in(now)
    armed, arm_at = true, now + REQUEST_DELAY;
end

function conquest.tick(now, zoning)
    if (not armed or c == nil or zoning or now < arm_at) then return; end
    local ru = c.retry_until;
    if (ru ~= nil and now >= ru) then c.tries, c.first_try, c.retry_until = 0, nil, nil; end
    local tries = c.tries or 0;
    local nt = c.next_tally;
    local known = valid_owners(c.owners) and nt ~= nil and now < nt;
    if (known or tries >= MAX_TRIES) then armed = false; return; end
    if (tries == 0) then c.first_try, c.retry_until = now, P.next_tally(now); end
    c.tries = tries + 1;
    armed = false;
    pcall(function() AshitaCore:GetPacketManager():AddOutgoingPacket(0x5A, { 0x5A, 0x02, 0x00, 0x00 }); end);
    save();
end

-- Crest name for zone.
function conquest.crest(dest_zone)
    if (c == nil) then return nil; end
    local r = client.region_of(dest_zone);
    local o = c.owners;
    if (r == nil or o == nil) then return nil; end
    return P.CREST_OF_OWNER[o[r + 1]];
end

return conquest;
