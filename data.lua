--[[
    ZoneLines v1.0.0 - Data Layer
    Loads pre-extracted zone line bounding boxes from zones_data.lua,
    supplemental trigger-area transitions from supplemental_zones.lua,
    and pre-computed terrain heights from terrain_heights.lua.

    Data sources (merged in order):
      1. zones_data.lua        — DAT-extracted zone line bounding boxes (auto-generated)
      2. supplemental_zones.lua — Hand-curated trigger-area transitions (e.g. palace gates)
      3. terrain_heights.lua   — Pre-computed ground heights from navmesh data
]]--

require 'common';

local data = {};

-- Pre-extracted zone line data (loaded from zones_data.lua)
data.static_data = nil;
data.static_total = 0;

-- Skip list: DAT entries to filter out (NPC interactions, not walk-through zone lines).
-- Key = zone_id, value = set of ident strings to remove.
local skip_entries = {
    [243] = { zmrm = true },  -- Ru'Lude Gardens Mog House (button interaction)
};

-- Pre-computed terrain heights (loaded from terrain_heights.lua)
data.terrain_data = nil;

-- Runtime zone name cache: resolved from FFXI client resource strings
-- The extraction script's hardcoded names are unreliable; always prefer the client.
local zone_name_cache = {};

-- Cache dirty flag: invalidated on any mutation
data.cache_dirty = true;
data.zone_cache = T{};
data.zone_cache_id = -1;


-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function data.init(addon_path)
    -- Load pre-extracted zone line data
    local addon_dir = addon_path:gsub('\\config\\addons\\zonelines$', '\\addons\\zonelines');
    local zones_file = addon_dir .. '\\zones_data.lua';

    local ok, static = pcall(dofile, zones_file);
    if (ok and static ~= nil) then
        data.static_data = static;
    else
        print(string.format('[zonelines] WARNING: Failed to load %s', zones_file));
    end

    -- Filter out skip-listed entries (NPC interactions, not zone lines)
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

    -- Record DAT entry counts per zone BEFORE supplemental merge.
    -- terrain_heights.lua is keyed by these indices; supplemental entries
    -- appended later must NOT use orphaned terrain data at higher indices.
    data.dat_entry_counts = {};
    if (data.static_data ~= nil) then
        for zone_id, entries in pairs(data.static_data) do
            data.dat_entry_counts[zone_id] = #entries;
        end
    end

    -- Load supplemental trigger-area transitions and merge into static data
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
    end

    -- Load pre-computed terrain heights from navmesh data
    local terrain_file = addon_dir .. '\\terrain_heights.lua';
    local ok3, terrain = pcall(dofile, terrain_file);
    if (ok3 and terrain ~= nil) then
        data.terrain_data = terrain;
    end

    -- Count total static entries (DAT + supplemental)
    data.static_total = 0;
    if (data.static_data ~= nil) then
        for _, entries in pairs(data.static_data) do
            data.static_total = data.static_total + #entries;
        end
    end

end

-------------------------------------------------------------------------------
-- Zone Name Resolution (runtime, from FFXI client resource strings)
-------------------------------------------------------------------------------

local function resolve_zone_name(zone_id)
    if (zone_id == nil or zone_id < 0) then return ''; end
    if (zone_id == 0) then return 'Mog House'; end

    -- Check cache first
    if (zone_name_cache[zone_id] ~= nil) then
        return zone_name_cache[zone_id];
    end

    -- Resolve from FFXI client resources (authoritative source)
    local rm = AshitaCore:GetResourceManager();
    if (rm == nil) then return string.format('Zone %d', zone_id); end
    local name = rm:GetString('zones.names', zone_id);
    if (name ~= nil and name ~= '') then
        zone_name_cache[zone_id] = name;
        return name;
    end

    -- Fallback: generic label
    local fallback = string.format('Zone %d', zone_id);
    zone_name_cache[zone_id] = fallback;
    return fallback;
end

-------------------------------------------------------------------------------
-- Display Name Resolution (shared helper — single source of truth)
-------------------------------------------------------------------------------

local function compute_display_name(entry)
    if (entry.label ~= nil and entry.label ~= '') then
        return entry.label;
    elseif (entry.to_zone ~= nil and entry.to_zone == 0) then
        return 'Mog House';
    elseif (entry.to_zone_name ~= nil and entry.to_zone_name ~= '') then
        return entry.to_zone_name;
    elseif (entry.to_zone ~= nil and entry.to_zone > 0) then
        return 'Zone ' .. tostring(entry.to_zone);
    end
    return '';
end

-------------------------------------------------------------------------------
-- Zone Line Access
-------------------------------------------------------------------------------

function data.get_zone_lines(zone_id)
    -- Return cached data if clean and same zone
    if (not data.cache_dirty and data.zone_cache_id == zone_id) then
        return data.zone_cache;
    end

    local results = T{};

    -- Add pre-extracted static data (from DAT files)
    if (data.static_data ~= nil and data.static_data[zone_id] ~= nil) then
        -- Look up terrain height data for this zone
        local zone_terrain = nil;
        if (data.terrain_data ~= nil and data.terrain_data[zone_id] ~= nil) then
            zone_terrain = data.terrain_data[zone_id];
        end

        for ei, entry in ipairs(data.static_data[zone_id]) do
            -- Resolve destination name at runtime from FFXI client resources
            -- (the extraction script's hardcoded names are unreliable)
            local dest_name = '';
            if (entry.to_zone ~= nil and entry.to_zone >= 0) then
                dest_name = resolve_zone_name(entry.to_zone);
            end

            -- Supplemental trigger-area entries use ident='trig'
            local src = (entry.ident == 'trig') and 'trigger' or 'dat';

            -- Attach pre-computed terrain heights (array index matches entry order).
            -- Only use terrain data for DAT entries (indices 1..dat_count).
            -- Supplemental entries appended beyond dat_count must not pick up
            -- orphaned terrain data from zone lines filtered during extraction.
            local heights = nil;
            local dat_count = data.dat_entry_counts[zone_id] or 0;
            if (zone_terrain ~= nil and zone_terrain[ei] ~= nil and ei <= dat_count) then
                heights = zone_terrain[ei];
            end

            -- Synthesize flat terrain for entries missing navmesh data.
            -- Ground level in FFXI zone line boxes sits ~2 yalms above the
            -- box floor: wy + sy/2 - 2. This formula matches real terrain
            -- within 0.1 yalms across tested zones (verified vs East Ronfaure,
            -- Jugner Forest entries with actual navmesh data).
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
                label = '',
                source = src,
                ident = entry.ident,
                shape = entry.shape,
                terrain_heights = heights,
            };
            zl_entry.display_name = compute_display_name(zl_entry);
            results:append(zl_entry);
        end
    end

    data.zone_cache = results;
    data.zone_cache_id = zone_id;
    data.cache_dirty = false;
    return results;
end

function data.get_total_count()
    return data.static_total;
end

function data.invalidate_cache()
    data.cache_dirty = true;
end

return data;
