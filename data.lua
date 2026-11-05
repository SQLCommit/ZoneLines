-- Zone line bounds and heights.

require 'common';

local chat = require 'chat';
local docks = require 'docks';
local teleporters = require 'teleporters';

local data = {};

-- Kinds built from settings.
local show_docks = true;
local show_zone_lines = true;
local show_teleporters = true;
local show_keepers = true;
local show_signs = true;
local WORLD = { zone = true, portal = true, dock = true, sign = true, keeper = true };
local MAP = { zone = true, portal = true, dock = true, sign = false, keeper = true };
local feat_sig = '';

data.static_data = nil;
data.static_total = 0;   -- DAT + supplemental
data.dat_total = 0;      -- DAT only

-- Built-in per-line tweaks.
data.BUILTIN_OVERRIDES = {
    ['846018170']  = { trim = 1.5 },
    ['846083706']  = { trim = 1.3 },
    ['846214778']  = { height = 0.5 },
    ['846737530']  = { trim = 0.1, flatten = 0.1, height = 4.1 },
    ['812529274']  = { trim = 1.7 },
    ['813119098']  = { trim = 2.9 },
    ['879572602']  = { trim = 0.4 },
    ['879769210']  = { trim = 4.9 },
    ['946287482']  = { trim = 4.5 },
    ['946287738']  = { height = 0.5 },
    ['1634088570'] = { hide = true },           -- N.Sandy Carpenter's Landing (door)
    ['1634153338'] = { trim = 3.9, flatten = 0.1 },
    ['1869770106'] = { trim = 3.7 },            -- Mog House trim
    ['1936878970'] = { trim = 3.7 },
    ['1970433402'] = { trim = 3.7 },
    ['923901']     = { pole_height = 1.7 },     -- Windurst Walls -> Heaven's Tower
    ['924201']     = { pole_height = 1.7 },     -- Heaven's Tower -> Windurst Walls
};
local OVR_FIELDS = { 'trim', 'flatten', 'height', 'hide', 'pole_height' };
data.OVERRIDE_FIELDS = OVR_FIELDS;

local function same_value(a, b)
    if (type(a) == 'number' and type(b) == 'number') then return math.abs(a - b) < 1e-4; end
    return a == b;
end
data.same_value = same_value;

-- Merged built-in and user values.
function data.effective_override(user, key)
    local e = {};
    local b = data.BUILTIN_OVERRIDES[key];
    local u = (type(user) == 'table') and user[key] or nil;
    for _, f in ipairs(OVR_FIELDS) do
        local v;
        if (type(u) == 'table') then v = rawget(u, f); end
        if (v == nil and b ~= nil) then v = b[f]; end
        e[f] = v;
    end
    return e;
end

function data.effective_overrides(user)
    local out = {};
    for key in pairs(data.BUILTIN_OVERRIDES) do out[key] = data.effective_override(user, key); end
    if (type(user) == 'table') then
        for key, u in pairs(user) do
            if (type(u) == 'table' and out[key] == nil) then out[key] = data.effective_override(user, key); end
        end
    end
    return out;
end

-- Drop values equal to built-in.
function data.migrate_overrides(user)
    if (type(user) ~= 'table') then return false; end
    local changed = false;
    local keys = {};
    for key in pairs(user) do keys[#keys + 1] = key; end
    for _, key in ipairs(keys) do
        local u, b = user[key], data.BUILTIN_OVERRIDES[key];
        if (type(u) == 'table') then
            if (b ~= nil) then
                for _, f in ipairs(OVR_FIELDS) do
                    local v = rawget(u, f);
                    if (v ~= nil and b[f] ~= nil and same_value(v, b[f])) then u[f] = nil; changed = true; end
                end
            end
            if (next(u) == nil) then user[key] = nil; changed = true; end
        end
    end
    return changed;
end

-- DAT entries to skip.
local skip_entries = {
    [243] = { zmrm = true },  -- Ru'Lude Gardens Mog House
};

data.terrain_data = nil;

local zone_name_cache = {};

data.cache_dirty = true;
data.zone_cache = T{};
data.zone_cache_id = -1;

function data.init(addon_path)
    local addon_dir = addon_path:gsub('\\config\\addons\\zonelines$', '\\addons\\zonelines');
    local zones_file = addon_dir .. '\\zones_data.lua';

    local ok, static = pcall(dofile, zones_file);
    if (ok and static ~= nil) then
        data.static_data = static;
    else
        print(chat.header('zonelines'):append(chat.error('Zone line data file missing - no markers will be shown.')));
    end

    if (data.static_data ~= nil) then
        for zone_id, skip_set in pairs(skip_entries) do
            if (data.static_data[zone_id] ~= nil) then
                local filtered = {};
                for _, entry in ipairs(data.static_data[zone_id]) do
                    if (not skip_set[entry.ident]) then
                        table.insert(filtered, entry);
                    end
                end
                data.static_data[zone_id] = filtered;
            end
        end
    end

    -- DAT counts per zone.
    data.dat_entry_counts = {};
    if (data.static_data ~= nil) then
        for zone_id, entries in pairs(data.static_data) do
            data.dat_entry_counts[zone_id] = #entries;
        end
    end

    local supp_file = addon_dir .. '\\supplemental_zones.lua';
    local ok2, supp = pcall(dofile, supp_file);
    if (ok2 and supp ~= nil) then
        if (data.static_data == nil) then data.static_data = {}; end
        for zone_id, entries in pairs(supp) do
            if (data.static_data[zone_id] == nil) then
                data.static_data[zone_id] = entries;
            else
                for _, entry in ipairs(entries) do
                    table.insert(data.static_data[zone_id], entry);
                end
            end
        end
    else
        print(chat.header('zonelines'):append(chat.message('Supplemental zone data missing - some trigger-based zone lines won\'t appear.')));
    end

    local terrain_file = addon_dir .. '\\terrain_heights.lua';
    local ok3, terrain = pcall(dofile, terrain_file);
    if (ok3 and terrain ~= nil) then
        data.terrain_data = terrain;
    else
        print(chat.header('zonelines'):append(chat.message('Terrain height data missing - dots will use estimated ground height.')));
    end

    data.dat_total = 0;
    for _, n in pairs(data.dat_entry_counts) do data.dat_total = data.dat_total + n; end

    data.static_total = 0;
    if (data.static_data ~= nil) then
        for _, entries in pairs(data.static_data) do
            data.static_total = data.static_total + #entries;
        end
    end

end

-- Zone name resolution

local function resolve_zone_name(zone_id, fallback_name)
    if (zone_id == nil or zone_id < 0) then return ''; end
    if (zone_id == 0) then return 'Mog House'; end

    if (zone_name_cache[zone_id] ~= nil) then
        return zone_name_cache[zone_id];
    end

    local rm = AshitaCore:GetResourceManager();
    if (rm == nil) then return fallback_name or string.format('Zone %d', zone_id); end
    local name = rm:GetString('zones.names', zone_id);
    if (name ~= nil and name ~= '') then
        zone_name_cache[zone_id] = name;
        return name;
    end

    -- Data file name wins.
    if (fallback_name ~= nil and fallback_name ~= '') then return fallback_name; end
    local fallback = string.format('Zone %d', zone_id);
    zone_name_cache[zone_id] = fallback;
    return fallback;
end

local function compute_display_name(entry)
    if (entry.to_zone ~= nil and entry.to_zone == 0) then
        return 'Mog House';
    elseif (entry.to_zone_name ~= nil and entry.to_zone_name ~= '') then
        return entry.to_zone_name;
    elseif (entry.to_zone ~= nil and entry.to_zone > 0) then
        return 'Zone ' .. tostring(entry.to_zone);
    end
    return '';
end

-- Feature switches from settings.
function data.set_features(s)
    local travel = (s.show_travel ~= false);
    WORLD.zone = (s.show_zone_lines ~= false);
    WORLD.portal = (s.show_teleporters ~= false);
    WORLD.dock = travel;
    WORLD.sign = travel and (s.show_signs ~= false);
    WORLD.keeper = travel and (s.show_keepers ~= false);
    local map = (s.show_map_exits ~= false);
    MAP.zone = map and (s.map_zone_lines ~= false);
    MAP.portal = map and (s.map_portals ~= false);
    MAP.dock = map and (s.map_docks ~= false);
    MAP.keeper = map and (s.map_npcs ~= false);
    local sig = string.format('%s%s%s%s%s%s%s%s%s', tostring(WORLD.zone), tostring(WORLD.portal), tostring(WORLD.dock),
        tostring(WORLD.sign), tostring(WORLD.keeper), tostring(MAP.zone), tostring(MAP.portal), tostring(MAP.dock), tostring(MAP.keeper));
    if (sig == feat_sig) then return; end
    feat_sig = sig;
    show_zone_lines = WORLD.zone or MAP.zone;
    show_teleporters = WORLD.portal or MAP.portal;
    show_docks = WORLD.dock or MAP.dock;
    show_keepers = WORLD.keeper or MAP.keeper;
    show_signs = WORLD.sign;
    data.cache_dirty = true;
end

-- Switch for an entry.
local function kind_of(e, src)
    if (e.floor_label ~= nil) then return 'portal'; end
    if (src == 'dock') then return 'dock'; end
    if (src == 'sign') then return 'sign'; end
    if (src == 'npc') then return e.label_only and 'keeper' or 'portal'; end
    return 'zone';
end

-- Floor-labelled telepad check.
function data.floor_entry(zl)
    return zl.floor_label ~= nil;
end

-- Build all marker kinds.
local function zone_entries(zone_id)
    local list = data.static_data and data.static_data[zone_id] or nil;
    local dk = show_docks and docks.entries(zone_id) or nil;
    local tp = (show_teleporters or show_keepers) and teleporters.entries(zone_id) or nil;
    local sg = show_signs and docks.signs(zone_id) or nil;
    local has_dk, has_tp, has_sg = (dk ~= nil and #dk > 0), (tp ~= nil and #tp > 0), (sg ~= nil and #sg > 0);
    if (not has_dk and not has_tp and not has_sg and ((show_teleporters and show_zone_lines) or list == nil)) then return list; end
    local merged = {};
    for _, e in ipairs(list or merged) do
        if (e.floor_label ~= nil and show_teleporters or e.floor_label == nil and show_zone_lines) then merged[#merged + 1] = e; end
    end
    if (has_dk) then for _, e in ipairs(dk) do merged[#merged + 1] = e; end end
    if (has_sg) then for _, e in ipairs(sg) do merged[#merged + 1] = e; end end
    if (has_tp) then
        for _, e in ipairs(tp) do
            if (e.label_only and show_keepers or not e.label_only and show_teleporters) then merged[#merged + 1] = e; end
        end
    end
    return merged;
end

function data.get_zone_lines(zone_id)
    if (not data.cache_dirty and data.zone_cache_id == zone_id) then
        if (not teleporters.poll(zone_id, show_teleporters or show_keepers)) then return data.zone_cache; end
    end

    local results = T{};

    local entries = zone_entries(zone_id);
    if (entries ~= nil) then
        local zone_terrain = nil;
        if (data.terrain_data ~= nil and data.terrain_data[zone_id] ~= nil) then
            zone_terrain = data.terrain_data[zone_id];
        end

        for ei, entry in ipairs(entries) do
            local dest_name = '';
            if (entry.to_zone ~= nil and entry.to_zone >= 0) then
                dest_name = resolve_zone_name(entry.to_zone, entry.to_zone_name);
            end

            local src = (entry.ident == 'trig') and 'trigger' or (entry.ident == 'dock') and 'dock' or (entry.ident == 'npc') and 'npc' or (entry.ident == 'sign') and 'sign' or 'dat';

            -- Heights for DAT entries.
            local heights = nil;
            local dat_count = data.dat_entry_counts[zone_id] or 0;
            if (zone_terrain ~= nil and zone_terrain[ei] ~= nil and ei <= dat_count) then
                heights = zone_terrain[ei];
            end

            if (heights == nil and entry.sx ~= nil and entry.sz ~= nil) then
                local wall_len = math.max(entry.sx, entry.sz);
                local num_samples = math.max(2, math.floor(wall_len / 2.0) + 1);
                local ground_y = entry.y + (entry.sy or 10) / 2 - 2;
                local flat = {};
                for hi = 1, num_samples do
                    flat[hi] = ground_y;
                end
                heights = { heights = flat, pos_adj = 0, neg_adj = 0, synthesized = true };
            end

            local zl_entry = {
                id = entry.rect_id,
                zone_id = zone_id,
                rect_id = entry.rect_id,
                x = entry.x,
                y = entry.y,
                z = entry.z,
                sx = entry.sx,
                sy = entry.sy,
                sz = entry.sz,
                ry = entry.ry,
                to_zone = entry.to_zone,
                to_zone_name = dest_name,
                source = src,
                ident = entry.ident,
                kind = entry.kind,
                cat = kind_of(entry, src),
                floor_label = entry.floor_label,
                routes = entry.routes,
                label_only = entry.label_only,
                map_only = entry.map_only,
                map_skip = entry.map_skip,
                signed = show_signs and entry.signed or nil,
                sign = entry.sign,
                emblem = entry.emblem,
                slot = entry.slot,
                swap = entry.swap,
                emblems = entry.emblems,
                spot = entry.spot,
                npc = entry.npc,
                head = entry.head,
                heading = entry.heading,
                nx = entry.nx,
                nz = entry.nz,
                shape = entry.shape,
                terrain_heights = heights,
                key = tostring(entry.rect_id),
                cr = math.cos(-(entry.ry or 0)),
                sr = math.sin(-(entry.ry or 0)),
            };
            zl_entry.display_name = entry.display_name or entry.floor_label or compute_display_name(zl_entry);
            results:append(zl_entry);
        end
    end

    data.zone_cache = results;
    data.zone_cache_id = zone_id;
    data.cache_dirty = false;
    return results;
end

-- Cached view of zone lines.
local function view(flags)
    return { src = nil, sig = nil, out = T{}, flags = flags };
end
local W_VIEW, M_VIEW = view(WORLD), view(MAP);
local function filtered(v, all)
    if (all ~= v.src or v.sig ~= feat_sig or v.n ~= #all or v.first ~= all[1]) then
        v.src, v.sig, v.n, v.first = all, feat_sig, #all, all[1];
        local out = T{};
        for _, zl in ipairs(all) do if (zl.cat == nil or v.flags[zl.cat]) then out:append(zl); end end
        v.out = out;
    end
    return v.out;
end

-- Drawn in the world.
function data.get_world_lines(zone_id) return filtered(W_VIEW, data.get_zone_lines(zone_id)); end

-- Drawn on the /map.
function data.get_map_lines(zone_id) return filtered(M_VIEW, data.get_zone_lines(zone_id)); end

function data.get_total_count()
    return data.static_total;
end

function data.invalidate_cache()
    data.cache_dirty = true;
end

return data;
