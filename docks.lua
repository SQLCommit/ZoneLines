-- Dock markers with live schedules.
local P = require 'world';
local transport = require 'transport';
local client = require 'client';

local docks = {};

local LINE_LEN, LINE_DEPTH, FLOOR_SY = 7, 0.5, 4;   -- Floor at door height.
local DIM = 0.3;
local TEXT_DIM = 0x8CFFFFFF;   -- Closed label colour.
local floor = math.floor;
local by_zone = nil;   -- Zone id to entries.
local DOOR_NAME = { ferry = 'Ferry dock', airship = 'Airship dock', barge = 'Barge dock', manaclipper = 'Manaclipper dock' };

-- Zone has schedule NPC.
local function keeper_for(zone, n)
    for _, def in ipairs(P.TIMEKEEPERS[zone] or {}) do
        for _, m in ipairs(def.runs) do if (m == n) then return true; end end
    end
    return false;
end

-- Zone has sign.
local function signed(zone, n)
    for _, d in ipairs(P.SIGNS[zone] or {}) do
        for _, m in ipairs(d.runs) do if (m == n) then return true; end end
    end
    return false;
end

local function build()
    by_zone = {};
    local doors, order = {}, {};
    for _, run in ipairs(P.RUNS) do
        if (client.run_ok(run)) then
            local key = run.zone .. ':' .. run.door_npc;
            local d = doors[key];
            if (d == nil) then
                d = { zone = run.zone, routes = {} };
                doors[key] = d;
                order[#order + 1] = d;
            end
            d.routes[#d.routes + 1] = run;
        end
    end
    for _, d in ipairs(order) do
        local list = by_zone[d.zone];
        if (list == nil) then list = {}; by_zone[d.zone] = list; end
        local run = d.routes[1];
        local kept, sg = true, true;   -- Schedule NPC / sign here.
        for _, r in ipairs(d.routes) do
            if (not keeper_for(d.zone, r.name)) then kept = false; end
            if (not signed(d.zone, r.name)) then sg = false; end
        end
        local dx, dz = run.berth[1] - run.door[1], run.berth[3] - run.door[3];
        list[#list + 1] = {
            x = run.door[1], y = run.door[2], z = run.door[3],
            sx = LINE_LEN, sy = FLOOR_SY, sz = LINE_DEPTH,
            ry = math.atan2(-dx, -dz),   -- Door to berth angle.
            rect_id = 910000 + d.zone * 10 + #list + 1,
            ident = 'dock', kind = 'dock',
            display_name = (#d.routes > 1) and DOOR_NAME[run.vessel] or run.label, routes = d.routes,
            map_skip = kept or nil,   -- NPC shows times.
            signed = sg or nil,       -- Sign shows times.
        };
    end
end

-- Dock entries for zone.
local EMPTY = {};
function docks.entries(zone_id)
    if (by_zone == nil) then build(); end
    return by_zone[zone_id] or EMPTY;
end

-- Arch sign entries.
local signs_by_zone = {};
function docks.signs(zone_id)
    local list = signs_by_zone[zone_id];
    if (list ~= nil) then return list; end
    list = {};
    for k, d in ipairs(P.SIGNS[zone_id] or EMPTY) do
        local routes = {};
        for _, name in ipairs(d.runs) do
            for _, run in ipairs(P.RUNS) do if (run.name == name and client.run_ok(run)) then routes[#routes + 1] = run; end end
        end
        if (#routes > 0) then
            list[#list + 1] = {
                x = d.at[1], y = d.at[2], z = d.at[3], nx = d.face[1], nz = d.face[2],
                rect_id = 970000 + zone_id * 10 + k, ident = 'sign', sign = true,
                display_name = routes[1].label, routes = routes, emblem = d.emblem, slot = d.slot,
                swap = d.swap, emblems = d.emblems, spot = d.spot, slim = d.slim, up = d.up, width = d.width,
            };
        end
    end
    signs_by_zone[zone_id] = list;
    return list;
end

-- Rebuild after expansion change.
function docks.refresh() by_zone = nil; signs_by_zone = {}; end

-- Colour scaled by k.
function docks.dim(col, k)
    local a = floor(col / 0x1000000) % 0x100;
    return floor(a * k + 0.5) * 0x1000000 + col % 0x1000000;
end

-- Fill label lines for now.
function docks.update(zl, now)
    local routes = zl.routes;
    local n = #routes;
    local lines = zl.lines;
    if (lines == nil) then
        lines = {};
        zl.lines, zl.raw = lines, {};
        zl.lines_n = n;
    end
    local raw = zl.raw;
    local any_open = false;
    for i = 1, n do
        local str, open = transport.text(routes[i], now);
        if (open) then any_open = true; end
        if (raw[i] ~= str) then
            raw[i] = str;
            lines[i] = (n > 1) and (routes[i].label .. ': ' .. str) or str;
        end
    end
    zl.alpha = any_open and 1.0 or DIM;
    zl.tint = (not any_open) and TEXT_DIM or nil;
end

-- Schedule NPC lines.
function docks.keeper(zl, now, s)
    local mask = ((s.keeper_status ~= false) and 1 or 0) + ((s.keeper_clock ~= false) and 2 or 0)
        + ((s.keeper_countdown ~= false) and 4 or 0);
    local sec = floor(now);
    if (zl.k_sec == sec and zl.k_mask == mask) then return; end
    zl.k_sec, zl.k_mask = sec, mask;
    local routes = zl.routes;
    local n = #routes;
    local lines = zl.lines;
    if (lines == nil) then lines = {}; zl.lines = lines; end
    local m = 0;
    for i = 1, n do
        local str = transport.compose(routes[i], sec, mask);
        if (str ~= nil) then
            m = m + 1;
            lines[m] = (n > 1) and (routes[i].label .. ': ' .. str) or str;
        end
    end
    for i = m + 1, #lines do lines[i] = nil; end
    zl.lines_n = m;
end

return docks;
