-- Markers drawn over /map.
local chat = require 'chat';
local ffi = require 'ffi';
local imgui = require 'imgui';
local textures = require 'textures';
local docks = require 'docks';

local mapoverlay = { ok = false };

local mem = ashita.memory;
local floor, abs = math.floor, math.abs;

local MAP_FAMILY = { 'mapframe', 'map0', 'maplist', 'scanlist', 'mapscan', 'mapv2', 'mapv3' };
local PEERS = { 'map0', 'maplist', 'scanlist' };
local REQUIRED = { mapframe = true, map0 = true, maplist = true, scanlist = true };
local FOCUS_SIG = '8B480C85C974??8B510885D274??3B05';   -- cmp eax,[mgr+0x54] at +16
local TABLE_SIG = '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9';   -- table at +0x1C
local FLOOR_FN_SIG = '8B542408568D4424108BF18B4C2410508B44240C';
local FLOOR_THIS_SIG = '8B7424148B4424108B7C240C8B0D';
local REC_SIZE, MAX_REC = 0x0E, 4096;
local FLOOR_YALMS = 8;
local DOT_R, SHADOW = 5, 0xC0000000;
local TEXT_COL = 0xFFFFFFFF;

pcall(ffi.cdef, 'typedef int32_t (__thiscall* zl_floor_f)(void*, float, float, float);');

local slots = {};          -- name -> gslot address
local family = {};         -- Map family gslots.
local peers = {};          -- Side panel gslots.
local focus_slot, mgr, table_ptr = 0, 0, 0;
local floor_fn, floor_this = nil, 0;
local coll_addr, coll_ptr = 0, nil;   -- collision manager and its cast
local tried = false;
local floors_zone, floors_n = -1, 0;
local logged_floor = false;
local dead = false;        -- Off after an error.
local live = false;        -- gates passed last frame
local fl_zone, fl_bx, fl_by, fl_bz, fl_at, fl_val = -1, 0, 0, 0, -1, -1;   -- floor cache
local FLOOR_EVERY = 0.25;
local WEAK = { __mode = 'k' };
local function marks() return setmetatable({}, WEAK), setmetatable({}, WEAK); end
local mk_floor, mk_miss = marks();   -- Floor per marker.
local MISS_RETRY = 1.0;

local V = { scroll_x = 0, scroll_y = 0, zoom = 0, ox = 0, oy = 0, s = 0, kx = 1, ky = 1 };
local POS, POS2 = { 0, 0 }, { 0, 0 };
local RECT = { 0, 0, 0, 0 };   -- Peer rects, 4 each.
local rect_n = 0;

-- Truncate toward zero.
local function T(v)
    if (v >= 0) then return floor(v); end
    return -floor(-v);
end

local function log(line) textures.log('map: ' .. line); end

-- One chat warning per session.
local warned = false;
local function warn()
    if (warned) then return; end
    warned = true;
    print(chat.header('zonelines'):append(chat.warning('Map markers are off this session (logs\\zonelines.log).')));
end

-- Registry slot by name.
local function find_slot(name, base, size)
    local key = 'menu    ' .. name .. string.rep(' ', 8 - #name);
    local hex = key:gsub('.', function(c) return string.format('%02X', c:byte()); end);
    for n = 0, 7 do
        local hit = mem.find('FFXiMain.dll', 0, hex, 0, n);
        if (hit == nil or hit == 0) then return 0; end
        local slot = mem.read_uint32(hit + 0x20);
        if (slot >= base and slot < base + size) then return slot; end
    end
    return 0;
end

local function in_image(a, base, size) return a ~= nil and a >= base and a < base + size; end

-- Floor function 0x1811D0.
local function floor_resolve(base, size)
    local fa = mem.find('FFXiMain.dll', 0, FLOOR_FN_SIG, 0, 0);
    local ta = mem.find('FFXiMain.dll', 0, FLOOR_THIS_SIG, 0x0E, 0);
    if (fa == 0 or ta == 0) then return 'not found'; end
    if (mem.find('FFXiMain.dll', 0, FLOOR_FN_SIG, 0, 1) ~= 0 or mem.find('FFXiMain.dll', 0, FLOOR_THIS_SIG, 0x0E, 1) ~= 0) then
        return 'signature not unique';
    end
    -- Call site pattern.
    if (mem.read_uint8(ta + 7) ~= 0xE8) then return 'call site missing'; end
    local target = (ta + 0x0C + mem.read_int32(ta + 8)) % 0x100000000;
    if (target ~= fa % 0x100000000) then return 'call site mismatch'; end
    local g = mem.read_uint32(ta);
    if (not in_image(g, base, size)) then return 'global outside the image'; end
    floor_this = g;
    floor_fn = ffi.cast('zl_floor_f', fa);
    return nil;
end

-- Resolve addresses.
function mapoverlay.init()
    tried = true;
    mapoverlay.ok = false;
    floors_zone = -1;
    for k in pairs(slots) do slots[k] = nil; end
    for i = #family, 1, -1 do family[i] = nil; end
    for i = #peers, 1, -1 do peers[i] = nil; end
    local base, size = mem.get_base('FFXiMain.dll') or 0, mem.get_size('FFXiMain.dll') or 0;
    if (base == 0 or size == 0) then log('FFXiMain.dll not found; off'); return false; end

    local missing = nil;
    for _, name in ipairs(MAP_FAMILY) do
        local slot = find_slot(name, base, size);
        if (slot ~= 0) then
            slots[name] = slot;
            family[#family + 1] = slot;
        elseif (REQUIRED[name] and missing == nil) then
            missing = name;
        end
    end
    if (missing ~= nil) then log('window ' .. missing .. ' not in the registry; off'); return false; end
    for i, name in ipairs(PEERS) do peers[i] = slots[name]; end

    local hit = mem.find('FFXiMain.dll', 0, FOCUS_SIG, 0, 0);
    if (hit == 0 or mem.find('FFXiMain.dll', 0, FOCUS_SIG, 0, 1) ~= 0) then log('focus signature not unique; off'); return false; end
    focus_slot = mem.read_uint32(hit + 16);
    if (not in_image(focus_slot, base, size)) then log('focus slot outside the image; off'); return false; end
    mgr = focus_slot - 0x54;

    hit = mem.find('FFXiMain.dll', 0, TABLE_SIG, 0, 0);
    table_ptr = (hit ~= 0) and mem.read_uint32(hit + 0x1C) or 0;
    if (not in_image(table_ptr, base, size)) then log('map table signature not found; off'); return false; end

    floor_fn, floor_this, fl_zone = nil, 0, -1;
    mk_floor, mk_miss = marks();
    local why = floor_resolve(base, size);
    if (why ~= nil and not logged_floor) then
        logged_floor = true;
        log('floor function ' .. why .. '; multi-floor zones off');
    end
    mapoverlay.ok = true;
    return true;
end

-- Map view snapshot.
function mapoverlay.read_view(obj, s, kx, ky)
    V.scroll_x = mem.read_float(obj + 0x24);
    V.scroll_y = mem.read_float(obj + 0x28);
    V.zoom = mem.read_float(obj + 0x58);
    V.ox = mem.read_int16(obj + 0x6C);
    V.oy = mem.read_int16(obj + 0x6E);
    V.s, V.kx, V.ky = abs(s), kx, ky;
    return V;
end

-- World to canvas pixels.
local function to_canvas(x, z, v)
    local mx = T(x * v.s / 5 + 0.5);
    local my = -T(z * v.s / 5 + 0.5);
    return T((mx - v.ox - v.scroll_x) * v.zoom + 0.5), T((my - v.oy - v.scroll_y) * v.zoom + 0.5);
end

-- World to back-buffer px.
function mapoverlay.to_view(x, z, v)
    local cx, cy = to_canvas(x, z, v);
    return cx * v.kx, cy * v.ky;
end

-- Slot window, else 0.
local function open_window(gslot)
    local ctrl = mem.read_uint32(gslot);
    if (ctrl == 0) then return 0; end
    local win = mem.read_uint32(ctrl + 8);
    if (win == 0 or mem.read_uint8(win + 0x70) ~= 0 or mem.read_uint8(win + 0x6E) ~= 0) then return 0; end
    return win;
end

local function focus_on_map()
    local f = mem.read_uint32(focus_slot);
    if (f == 0) then return false; end
    for i = 1, #family do
        local ctrl = mem.read_uint32(family[i]);
        if (ctrl ~= 0 and mem.read_uint32(ctrl + 8) == f) then return true; end
    end
    return false;
end

-- Map records per zone.
local function zone_floors(zone_id)
    if (floors_zone == zone_id) then return floors_n; end
    local n = 0;
    for i = 0, MAX_REC - 1 do
        local a = table_ptr + i * REC_SIZE;
        if (mem.read_int8(a + 5) == 0) then break; end
        if (mem.read_int16(a) == zone_id) then n = n + 1; end
    end
    floors_zone, floors_n = zone_id, n;
    return n;
end

local function load_peers()
    rect_n = 0;
    for i = 1, #peers do
        local win = open_window(peers[i]);
        if (win ~= 0) then
            RECT[rect_n + 1] = mem.read_int16(win + 0x3A);
            RECT[rect_n + 2] = mem.read_int16(win + 0x3C);
            RECT[rect_n + 3] = mem.read_int16(win + 0x3E);
            RECT[rect_n + 4] = mem.read_int16(win + 0x40);
            rect_n = rect_n + 4;
        end
    end
end

local function under_peer(cx, cy)
    for i = 1, rect_n, 4 do
        if (cx >= RECT[i] and cx < RECT[i + 2] and cy >= RECT[i + 1] and cy < RECT[i + 3]) then return true; end
    end
    return false;
end

local function colour(c, def)
    if (c == nil) then return def; end
    local r = floor((c[1] or 0) * 255 + 0.5);
    local g = floor((c[2] or 0) * 255 + 0.5);
    local b = floor((c[3] or 0) * 255 + 0.5);
    return 0xFF000000 + b * 0x10000 + g * 0x100 + r;
end

local function text(dl, x, y, col, str)
    POS2[1], POS2[2] = x + 1, y + 1;
    dl:AddText(POS2, SHADOW, str);
    POS2[1], POS2[2] = x, y;
    dl:AddText(POS2, col, str);
end

-- Player floor, throttled.
local function player_floor(zone_id, fresh, x, y, z)
    local bx, by, bz = floor(x), floor(y), floor(z);
    local now = os.clock();
    if (fresh or zone_id ~= fl_zone or ((bx ~= fl_bx or by ~= fl_by or bz ~= fl_bz) and now - fl_at >= FLOOR_EVERY)) then
        fl_val = floor_fn(coll_ptr, x, y, z);
        fl_zone, fl_bx, fl_by, fl_bz, fl_at = zone_id, bx, by, bz, now;
    end
    return fl_val;
end

-- Marker floor, cached; 0 = miss.
local function marker_floor(zl, now)
    local f = mk_floor[zl];
    if (f ~= nil) then return f; end
    local at = mk_miss[zl];
    if (at ~= nil and now - at < MISS_RETRY) then return 0; end
    f = floor_fn(coll_ptr, zl.x, zl.y, zl.z);
    if (f ~= 0) then mk_floor[zl], mk_miss[zl] = f, nil; else mk_miss[zl] = now; end
    return f;
end

-- Hide markers on other floors.
local function other_floor(zl, shown, py, now)
    local f = marker_floor(zl, now);
    if (f ~= 0) then return f ~= shown; end
    return abs(py - zl.y) > FLOOR_YALMS;   -- Miss: height rule.
end

-- Draw when map is shown.
local function draw_body(zone_id, lines, s)
    local prev = live;
    live = false;
    if (not tried and not mapoverlay.init()) then warn(); end
    if (not mapoverlay.ok or lines == nil or #lines == 0) then return; end
    local obj = mem.read_uint32(slots.mapframe);
    local win = (obj ~= 0) and open_window(slots.mapframe) or 0;
    if (win == 0) then return; end
    -- Hidden window check.
    if (mem.read_uint8(win + 0x62) == 0 and mem.read_uint8(win + 0x69) == 0 and mem.read_uint8(win + 0x6A) == 0) then return; end
    if (mem.read_uint16(obj + 0xA6) ~= 0) then return; end
    if (mem.read_int16(obj + 0x100) ~= zone_id) then return; end
    local shown = mem.read_int16(obj + 0x102);
    if (not focus_on_map()) then return; end

    local idx = mem.read_uint32(obj + 0xFC);
    if (idx >= MAX_REC) then return; end
    local rec = table_ptr + idx * REC_SIZE;
    if (mem.read_int16(rec) ~= zone_id or mem.read_int8(rec + 2) ~= shown) then return; end
    local sc = mem.read_int8(rec + 5);
    if (sc == 0) then return; end
    live = true;

    -- Multi-floor check.
    local multi = zone_floors(zone_id) > 1;
    local py = 0;
    if (multi) then
        if (floor_fn == nil) then return; end
        local this = mem.read_uint32(floor_this);
        if (this == 0) then return; end
        local fresh = not prev;
        if (this ~= coll_addr) then coll_addr, coll_ptr, fresh = this, ffi.cast('void*', this), true; mk_floor, mk_miss = marks(); end
        local e = GetPlayerEntity();
        if (e == nil) then return; end
        local p = e.Movement.LocalPosition;
        py = p.Z;
        if (player_floor(zone_id, fresh, p.X, p.Z, p.Y) ~= shown) then return; end
    end

    local cw = mem.read_int16(mgr + 0x80) - mem.read_int16(mgr + 0x7C);
    local ch = mem.read_int16(mgr + 0x82) - mem.read_int16(mgr + 0x7E);
    if (cw < 240 or ch < 240 or cw > 16384 or ch > 16384) then return; end
    local ds = imgui.GetIO().DisplaySize;
    local v = mapoverlay.read_view(obj, sc, ds.x / cw, ds.y / ch);
    if (v.zoom <= 0) then return; end
    load_peers();

    local now = os.time();
    local clk = os.clock();
    local dl = nil;
    local dot = colour(s.map_dot_color, 0xFFF0FF00);
    local tcol = colour(s.map_text_color, TEXT_COL);
    local r = s.map_dot_size or DOT_R;
    local names = (s.map_names ~= false);
    local lh = imgui.GetFontSize();
    for i = 1, #lines do
        local zl = lines[i];
        local skip = zl.map_skip and ((zl.kind == 'dock') and s.map_npcs ~= false or (zl.kind ~= 'dock') and s.map_docks ~= false);   -- Other one shows.
        if (not zl.sign and not skip and not (multi and other_floor(zl, shown, py, clk))) then
            local cx, cy = to_canvas(zl.x, zl.z, v);
            if (cx >= 0 and cy >= 0 and cx < cw and cy < ch and not under_peer(cx, cy)) then
                if (dl == nil) then dl = imgui.GetBackgroundDrawList(); end
                local x, y = cx * v.kx, cy * v.ky;
                POS[1], POS[2] = x, y;
                dl:AddCircleFilled(POS, r + 1, SHADOW, 12);
                dl:AddCircleFilled(POS, r, dot, 12);
                local name = names and zl.display_name or nil;
                if (zl.label_only and s.keeper_route == false) then name = nil; end
                local top = y - lh * 0.5;
                if (name ~= nil and name ~= '') then text(dl, x + r + 4, top, tcol, name); top = top + lh; end
                if (zl.label_only and s.map_times ~= false) then   -- NPC times.
                    docks.keeper(zl, now, s);
                    for k = 1, zl.lines_n do text(dl, x + r + 4, top + lh * (k - 1), tcol, zl.lines[k]); end
                end
            end
        end
    end
end

-- Errors turn overlay off.
function mapoverlay.draw(zone_id, lines, s)
    if (dead) then return; end
    local ok, err = pcall(draw_body, zone_id, lines, s);
    if (not ok) then
        dead, mapoverlay.ok = true, false;
        log('error, off for this session: ' .. tostring(err));
        warn();
    end
end

return mapoverlay;
