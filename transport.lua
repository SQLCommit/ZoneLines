-- Ship phases and dock text.
local P = require 'world';
local client = require 'client';
local M = {};

local floor, ceil = math.floor, math.ceil;
local fmt = string.format;
local EPOCH = P.VANA_EPOCH;
local cache = {};
local corr = {};           -- Run to seconds correction.
local CORR_MAX, LOOK_S = 60, 2;

-- Seconds into run cycle.
local function into_of(run, now)
    return (now - EPOCH + client.skew() - run.offset - (corr[run.name] or 0)) % run.every;
end

-- Phase and its length.
local function find(run, into)
    local t, ph = 0, run.phases;
    for i = 1, #ph do
        local len = ph[i].s;
        if (len == nil or into < t + len) then return ph[i].state, len, t; end
        t = t + len;
    end
    return ph[#ph].state, nil, t;
end

-- State, elapsed, length.
function M.phase(run, now)
    local into = into_of(run, now);
    local state, len, t = find(run, into);
    return state, into - t, len;
end

-- Vana'diel HH:MM.
function M.vana_hhmm(unix)
    local m = floor((unix - EPOCH + client.skew()) / 2.4);
    return fmt('%02d:%02d', floor(m / 60) % 24, m % 60);
end

local function mss(sec)
    return fmt('%d:%02d', floor(sec / 60), sec % 60);
end

-- Label line and open flag.
function M.text(run, now, out)
    local c = cache[run];
    if (c == nil) then c = {}; cache[run] = c; end
    local sec = floor(now);
    if (c.sec == sec) then
        if (out) then out.str, out.open = c.str, c.open; end
        return c.str, c.open;
    end
    local ph = run.phases;
    local into = into_of(run, sec);
    local state, len, start = find(run, into);
    local str, open = nil, false;
    if (state == 'arriving') then
        str = 'Docking - boards in ' .. mss(ceil(start + len - into));
    elseif (state == 'docked') then
        local left = ceil(start + len - into);
        str = 'Boarding - departs ' .. M.vana_hhmm(sec + left) .. ' - ' .. mss(left);
        open = true;
    else
        local left = ceil(run.every - into + ph[1].s);
        str = 'Next ' .. run.vessel .. ' docks ' .. M.vana_hhmm(sec + left) .. ' - in ' .. mss(left);
    end
    c.sec, c.str, c.open = sec, str, open;
    if (out) then out.str, out.open = str, open; end
    return str, open;
end

-- Status text for schedule NPCs.
local parts = {};
local function parts_of(run, sec)
    local c = parts[run];
    if (c == nil) then c = {}; parts[run] = c; end
    if (c.sec == sec) then return c; end
    local ph = run.phases;
    local into = into_of(run, sec);
    local state, len, start = find(run, into);
    local left;
    if (state == 'arriving') then
        left, c.status, c.word = ceil(start + len - into), 'Docking - boards', 'Boards at';
    elseif (state == 'docked') then
        left, c.status, c.word = ceil(start + len - into), 'Boarding - departs', 'Departs';
    else
        left, c.status, c.word = ceil(run.every - into + ph[1].s), 'Next ' .. run.vessel .. ' docks', 'Arrives';
    end
    c.near, c.open = state == 'arriving' or state == 'docked', state == 'docked';   -- Ship at dock.
    c.sec, c.left, c.clock, c.cd = sec, left, M.vana_hhmm(sec + left), 'in ' .. mss(left);
    return c;
end

-- One line from parts mask.
function M.compose(run, now, mask)
    local c = parts_of(run, floor(now));
    local t = nil;
    if (mask % 2 == 1) then t = c.status; end
    if (floor(mask / 2) % 2 == 1) then t = t and (t .. ' ' .. c.clock) or c.clock; end
    if (mask >= 4) then t = t and (t .. ' - ' .. c.cd) or c.cd; end
    return t;
end

-- Run time correction.
function M.correction(run) return corr[run.name] or 0; end

-- Run phase boundaries.
local function starts(run)
    local out, t = { 0 }, 0;
    for i = 1, #run.phases - 1 do
        t = t + (run.phases[i].s or 0);
        out[#out + 1] = t;
    end
    return out;
end

local runs_in = nil;   -- Zone to runs.
local next_look = 0;

-- Snap run to seen ship.
function M.observe(zone_id, now)
    if (runs_in == nil) then
        runs_in = {};
        for _, run in ipairs(P.RUNS) do
            local l = runs_in[run.zone];
            if (l == nil) then l = {}; runs_in[run.zone] = l; end
            l[#l + 1] = run;
        end
    end
    local runs = runs_in[zone_id];
    if (runs == nil) then return; end
    local clk = os.clock();
    if (clk < next_look) then return; end
    next_look = clk + LOOK_S;
    local mgr = AshitaCore:GetMemoryManager();
    local ents = mgr and mgr:GetEntity() or nil;
    if (ents == nil) then return; end
    local vnow = now - EPOCH + client.skew();
    for i = 0, 0x3FF do
        if (ents:GetType(i) == 5) then
            local ts = ents:GetModelStartTime(i) or 0;
            if (ts > 1e8 and math.abs(ts - vnow) < 2 * 3456) then
                local best, bd = nil, CORR_MAX + 1;
                for _, run in ipairs(runs) do
                    local half = run.every / 2;
                    for _, st in ipairs(starts(run)) do
                        local d = (ts - run.offset - (corr[run.name] or 0) - st + half) % run.every - half;
                        if (math.abs(d) < math.abs(bd)) then best, bd = run, d; end
                    end
                end
                if (best ~= nil and bd ~= 0) then
                    local first = corr[best.name] == nil;
                    corr[best.name] = (corr[best.name] or 0) + bd;
                    cache[best], parts[best] = nil, nil;
                    if (first) then
                        pcall(function() require('textures').log(string.format('ships: %s %+d s from the ship', best.name, corr[best.name])); end);
                    end
                elseif (best ~= nil and corr[best.name] == nil) then
                    corr[best.name] = 0;
                end
            end
        end
    end
end

-- Test hook.
function M.reset_corrections() corr = {}; next_look = 0; cache = {}; parts = {}; end

-- Short sign words.
function M.brief(run, now)
    return parts_of(run, floor(now));
end

return M;
