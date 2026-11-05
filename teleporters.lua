-- NPC markers anchored to entities.
local P = require 'world';
local client = require 'client';

local TICK = 1.0;          -- Seconds between scans.
local CHUNKS = { { 0, 0x2FF }, { 0x300, 0x3FF, 0x700, 0x8FF } };   -- Entity slot ranges per tick.
local NEAR = 40;           -- Yalms.
local MISS_TICKS = 4;      -- Ticks near without NPC.
local CIRCLE = 3;          -- Circle diameter.
local EMPTY = {};
local KEEPER_NAME = { ferry = 'Ferry times', airship = 'Airship times', barge = 'Barge times', manaclipper = 'Manaclipper times' };

local run_by_name = nil;
local function runs_of(names)
    if (run_by_name == nil) then
        run_by_name = {};
        for _, run in ipairs(P.RUNS) do run_by_name[run.name] = run; end
    end
    local out = {};
    for _, n in ipairs(names) do
        local run = run_by_name[n];
        if (run ~= nil and client.run_ok(run)) then out[#out + 1] = run; end
    end
    return out;
end

local function teleporter_entry(zone_id, k, def)
    local at = def.at or EMPTY;
    return {
        x = at[1] or 0, y = at[2] or 0, z = at[3] or 0, sx = CIRCLE, sy = 2, sz = CIRCLE, ry = 0,
        rect_id = 930000 + zone_id * 10 + k,
        ident = 'npc', shape = 'circle',
        to_zone = def.to_zone, display_name = def.label,
    };
end

-- Dock keeper per zone.
local dock_keeper = {};   -- Dock-door NPC defs.
for zone, defs in pairs(P.TIMEKEEPERS) do
    for _, run in ipairs(P.RUNS) do
        if (run.zone == zone) then
            local best, bd = nil, math.huge;
            for _, def in ipairs(defs) do
                local at = def.at;
                for _, n in ipairs(def.runs) do
                    if (n == run.name and at ~= nil) then
                        local d = (at[1] - run.door[1]) ^ 2 + (at[2] - run.door[2]) ^ 2 + (at[3] - run.door[3]) ^ 2;
                        if (d < bd) then best, bd = def, d; end
                    end
                end
            end
            if (best ~= nil) then dock_keeper[best] = true; end
        end
    end
end

local function keeper_entry(zone_id, k, def)
    local routes = runs_of(def.runs);
    local first = routes[1] or EMPTY;
    local at = def.at or EMPTY;
    return {
        x = at[1] or 0, y = at[2] or 0, z = at[3] or 0, sx = CIRCLE, sy = 2, sz = CIRCLE, ry = 0,
        rect_id = 950000 + zone_id * 20 + k,
        ident = 'npc', shape = 'circle', label_only = true, routes = routes, npc = def.npc,
        map_only = (P.SIGNS[zone_id] ~= nil) or nil,   -- Arch signs show times.
        map_skip = (not dock_keeper[def] and #routes > 0 and routes[1].zone == zone_id) or nil,   -- Dock NPC shows times.
        display_name = (#routes > 1) and KEEPER_NAME[first.vessel] or first.label,
    };
end

-- Head bone x name scale.
local function head_raw(ents, i)
    local m = ashita.memory;
    local rf, ru32, ru16 = m.read_float, m.read_uint32, m.read_uint16;
    local a = ents:GetActorPointer(i);
    if (a == nil or a < 0x10000) then return nil; end
    local p = ru32(a + 0x6B8);
    if (p == nil or p < 0x10000) then return nil; end
    p = ru32(p + 0x0C);
    if (p == nil or p < 0x10000) then return nil; end
    local skel = ru32(p);
    if (skel == nil or skel < 0x10000) then return nil; end
    local bones = ru16(skel + 0x32);
    if (bones == nil or bones < 3 or bones > 512) then return nil; end
    local gen = skel + 0x30 + 0x04 + 0x1E * bones + 4;
    return -rf(gen + 2 * 0x1A + 0x0E + 0x4) * rf(a + 0x69C);
end

local head_logged = {};
local function head_of(ents, i)
    local ok, h = pcall(head_raw, ents, i);
    local good = ok and type(h) == 'number' and h > 0.4 and h < 8;
    local name = ents:GetName(i);
    if (name ~= nil and not head_logged[name]) then
        head_logged[name] = true;
        pcall(function() require('textures').log(string.format('npc: %s head %s heading %.3f', name, good and string.format('%.2f', h) or ('unread (' .. tostring(h) .. ')'), ents:GetHeading(i) or -1)); end);
    end
    return good and h or nil;
end

-- Entity Y/Z swapped from DAT.
local function read_pos(ents, i, e)
    local x, y, z = ents:GetLocalPositionX(i), ents:GetLocalPositionZ(i), ents:GetLocalPositionY(i);
    if (x == 0 and y == 0 and z == 0) then return false; end
    local moved = (e.x ~= x or e.y ~= y or e.z ~= z);
    e.x, e.y, e.z = x, y, z;
    local h = head_of(ents, i);
    if (h ~= nil and (e.head == nil or math.abs(e.head - h) > 0.05)) then e.head = h; moved = true; end
    local hd = ents:GetHeading(i);   -- Heading in radians.
    if (type(hd) == 'number' and (e.heading == nil or math.abs(e.heading - hd) > 0.01)) then e.heading = hd; moved = true; end
    return true, moved;
end

-- Both NPC kinds, one scan.
local defs_by_zone = {};
for _, set in ipairs({ { P.TELEPORTERS, teleporter_entry }, { P.TIMEKEEPERS, keeper_entry } }) do
    for zone, defs in pairs(set[1]) do
        local list = defs_by_zone[zone];
        if (list == nil) then list = {}; defs_by_zone[zone] = list; end
        for j, def in ipairs(defs) do
            local toau = def.toau;
            if (def.runs ~= nil) then   -- ToAU-only schedule NPC.
                toau = #def.runs > 0;
                for _, n in ipairs(def.runs) do
                    for _, run in ipairs(P.RUNS) do if (run.name == n and not run.toau) then toau = false; end end
                end
            end
            list[#list + 1] = { npc = def.npc, def = def, make = set[2], key = j, fixed = (def.at ~= nil), at = def.at, toau = toau or nil };   -- Key: own list index.
        end
    end
end

local function tracker()
    local t = {};
    local state = {};          -- Per-zone scan state.
    local cur_zone = nil;      -- Live zone.

    -- Candidate NPCs for scan.
    local function rebuild(st)
        local defs, out, m = st.defs, st.out, 0;
        local toau = client.toau();
        for k = 1, #defs do
            local d = defs[k];
            local show = st.have[k] or st.seen[k] or (d.fixed and not st.gone[k]);
            if (show and (toau or not d.toau)) then m = m + 1; out[m] = st.entry[k]; end
        end
        for k = m + 1, #defs do out[k] = nil; end
    end

    local function zone_state(zone_id, defs)
        local st = state[zone_id];
        if (st == nil) then
            st = { defs = defs, entry = {}, idx = {}, have = {}, seen = {}, gone = {}, miss = {}, out = {}, n = 0, next = 0, chunk = 1 };
            for k, def in ipairs(defs) do
                st.entry[k] = def.make(zone_id, def.key, def.def);
                st.idx[k], st.have[k], st.seen[k], st.gone[k], st.miss[k] = -1, false, false, false, 0;
            end
            rebuild(st);
            state[zone_id] = st;
        end
        return st;
    end

    local function forget(st)
        for k = 1, #st.have do st.have[k], st.idx[k], st.miss[k] = false, -1, 0; end
        st.n, st.next = 0, 0;
        rebuild(st);
    end

    -- Re-check and find NPCs.
    function t.poll(zone_id, active)
        if (zone_id ~= cur_zone) then
            local old = state[cur_zone];
            if (old ~= nil) then forget(old); end
            cur_zone = zone_id;
        end
        local defs = defs_by_zone[zone_id];
        if (defs == nil or active == false) then return false; end
        local st = zone_state(zone_id, defs);
        local now = os.clock();
        if (now < st.next) then return false; end
        st.next = now + TICK;

        local mgr = AshitaCore:GetMemoryManager();
        local ents = mgr and mgr:GetEntity() or nil;
        if (ents == nil) then return false; end
        local changed = false;
        for k, def in ipairs(defs) do
            if (st.have[k]) then
                local i = st.idx[k];
                local ok, moved = false, false;
                if (ents:GetName(i) == def.npc and ents:GetRenderFlags0(i) ~= 0) then
                    ok, moved = read_pos(ents, i, st.entry[k]);
                end
                if (not ok) then
                    st.have[k], st.idx[k] = false, -1;
                    st.n = st.n - 1;
                    changed = true;
                elseif (moved) then
                    changed = true;
                end
            end
        end
        if (st.n < #defs) then
            local ch = CHUNKS[st.chunk];
            st.chunk = st.chunk % #CHUNKS + 1;
            for r = 1, #ch, 2 do
                for i = ch[r], ch[r + 1] do
                    local name = ents:GetName(i);
                    if (name ~= nil and name ~= '') then
                        for k, def in ipairs(defs) do
                            if (def.npc == name and not st.have[k] and ents:GetRenderFlags0(i) ~= 0 and read_pos(ents, i, st.entry[k])) then
                                st.have[k], st.idx[k], st.seen[k], st.miss[k] = true, i, true, 0;
                                if (st.gone[k]) then st.gone[k] = false; end
                                st.n = st.n + 1;
                                changed = true;
                            end
                        end
                    end
                end
            end
            -- No NPC here.
            local me = GetPlayerEntity and GetPlayerEntity() or nil;
            local lp = me and me.Movement and me.Movement.LocalPosition or nil;
            if (lp ~= nil) then
                local px, py, pz = lp.X, lp.Z, lp.Y;
                for k, def in ipairs(defs) do
                    local at = def.at;
                    if (at ~= nil and not st.have[k] and not st.gone[k] and not st.seen[k]) then
                        local d2 = (px - at[1]) ^ 2 + (py - at[2]) ^ 2 + (pz - at[3]) ^ 2;
                        if (d2 < NEAR * NEAR) then
                            st.miss[k] = st.miss[k] + 1;
                            if (st.miss[k] >= MISS_TICKS) then st.gone[k] = true; changed = true; end
                        else
                            st.miss[k] = 0;
                        end
                    end
                end
            end
        end
        if (changed) then rebuild(st); end
        return changed;
    end

    -- Entries on live NPCs.
    function t.entries(zone_id)
        t.poll(zone_id, true);
        local st = state[zone_id];
        if (st == nil) then return EMPTY; end
        return st.out;
    end

    -- Re-read routes, keep seen/gone.
    function t.refresh()
        for zone_id, st in pairs(state) do
            for k, d in ipairs(st.defs) do st.entry[k] = d.make(zone_id, d.key, d.def); end
            forget(st);
        end
        cur_zone = nil;
    end

    -- Test hook.
    function t.reset() state = {}; cur_zone = nil; end

    return t;
end

return tracker();
