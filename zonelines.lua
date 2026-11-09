-- Zone line markers addon.

addon.name    = 'zonelines';
addon.author  = 'SQLCommit';
addon.version = '1.4.2';
addon.desc    = 'Visualizes zone line boundaries with ground markers.';
addon.link    = 'https://github.com/SQLCommit/zonelines';

require 'common';

local chat     = require 'chat';
local d3d8     = require 'd3d8';
local settings = require 'settings';

-- Reload modules on addon reload.
package.loaded['data']     = nil;
package.loaded['renderer'] = nil;
package.loaded['ui']       = nil;
package.loaded['guard']    = nil;
package.loaded['world'] = nil;
package.loaded['client'] = nil;
package.loaded['transport'] = nil;
package.loaded['docks'] = nil;
package.loaded['teleporters'] = nil;
package.loaded['textures'] = nil;
package.loaded['effects'] = nil;
package.loaded['conquest'] = nil;
package.loaded['crests'] = nil;
package.loaded['mapoverlay'] = nil;
package.loaded['late'] = nil;
package.loaded['signs'] = nil;
package.loaded['wintype'] = nil;
package.loaded['ground'] = nil;

local data     = require 'data';
local renderer = require 'renderer';
local ui       = require 'ui';
local textures = require 'textures';
local ground   = require 'ground';
local conquest = require 'conquest';
local crests   = require 'crests';
local mapoverlay = require 'mapoverlay';
local late     = require 'late';
local client   = require 'client';
local transport = require 'transport';
local teleporters = require 'teleporters';
local docks    = require 'docks';

local default_settings = T{
    visible          = true,
    render_distance  = 90.0,
    dot_size         = 1.4,
    dot_spacing      = 0.3,
    dot_glow         = 1.0,
    hover_height     = 0.5,
    rise_distance    = 0.9,
    dot_color        = T{ 0.0, 1.0, 0.94 },
    use_dist_colors  = false,
    color_far        = T{ 0.0, 1.0, 0.0 },   -- 20y or more.
    color_mid        = T{ 1.0, 1.0, 0.0 },   -- Under 20y.
    color_close      = T{ 1.0, 0.0, 0.0 },   -- Under 10y.
    d3d_text_scale       = 0.9,
    d3d_label_offset     = 0.5,
    d3d_text_min_scale   = 0.7,
    d3d_text_max_scale   = 2.3,
    d3d_labels_fixed     = false,      -- Labels fixed in world.
    d3d_font_family      = 'Arial',    -- Label font family.
    d3d_outline_width    = 2,          -- label outline thickness
    d3d_bold             = true,       -- bold labels
    d3d_show_labels      = true,
    d3d_show_distance    = true,
    d3d_dist_position    = 'bottom',  -- 'bottom', 'top', 'left', 'right'
    d3d_label_spacing    = 8,         -- Name to distance gap.
    dot_glow_enabled     = true,      -- pulsating dots
    dot_glow_speed       = 4.0,       -- Pulse radians per second.
    dot_glow_intensity   = 2.0,       -- glow brightness multiplier
    dot_glow_min         = 0.69,      -- pulse minimum (0-1)
    dot_glow_max         = 1.0,       -- pulse maximum (0-1)
    distance_fade        = true,      -- Shrink dots near edge.
    distance_fade_zone   = 0.6,       -- Fade fraction, 0-1.
    zoneline_overrides   = T{},   -- User line overrides.
    show_dots            = true,      -- the dot line itself
    portal_markers       = true,      -- Portal circle and pole.
    npc_markers          = true,      -- NPC gem.
    fx_wave              = true,
    fx_reveal            = true,
    fx_motes             = true,
    fx_wave_speed        = 1.0,       -- Effect controls.
    fx_wave_depth        = 25,
    fx_reveal_time       = 0.6,
    fx_motes_range       = 35,
    fx_motes_amount      = 100,
    fx_motes_rise        = 3.2,
    fx_motes_start       = 0.3,       -- yalms above the ground
    show_zone_lines      = true,      -- Zone exits.
    show_travel          = true,      -- docks, signs and NPC times
    show_keepers         = true,      -- ship times over schedule NPCs
    keeper_route         = true,
    keeper_status        = true,
    keeper_clock         = true,
    keeper_countdown     = true,
    keeper_distance      = true,
    show_crests          = true,
    show_map_exits       = true,
    map_times            = true,      -- NPC ship times on /map.
    map_zone_lines       = true,      -- Zone lines on /map.
    map_portals          = true,
    map_docks            = true,
    map_npcs             = true,
    map_names            = true,
    map_dot_size         = 5,
    map_dot_color        = T{ 0.0, 1.0, 0.94 },
    map_text_color       = T{ 1.0, 1.0, 1.0 },
    show_signs           = true,      -- Signs in dock arches.
    sign_npcs            = false,     -- Signs over NPCs too.
    sign_style           = 'window',  -- 'window' or 'none'.
    sign_emblem          = true,
    sign_title           = true,
    sign_status          = true,
    sign_clock           = true,
    sign_countdown       = true,
    sign_range           = 90,
    sign_height          = 4.4,
    sign_width           = 4.4,
    sign_text            = 100,
    sign_scale           = 100,       -- whole sign, %
    sign_opacity         = 100,
    sign_back            = true,
    sign_boarding        = true,
    sign_title_color     = T{ 0.949, 0.863, 0.596 },
    sign_line_color      = T{ 1.0, 1.0, 1.0 },
    sign_board_color     = T{ 0.612, 0.941, 0.659 },
    show_teleporters     = true,
    conquest             = T{},       -- Per-character store.
};

local s = nil;           -- settings reference
local current_zone = 0;
local zone_name = '';
local zoning = false;    -- True while zoning.

local function msg(text)
    print(chat.header(addon.name):append(chat.message(text)));
end

local function msg_success(text)
    print(chat.header(addon.name):append(chat.success(text)));
end

local function msg_error(text)
    print(chat.header(addon.name):append(chat.error(text)));
end

local function get_zone_id()
    local mm = AshitaCore:GetMemoryManager();
    if (mm == nil) then return 0; end
    local party = mm:GetParty();
    if (party == nil) then return 0; end
    return party:GetMemberZone(0) or 0;
end

local function get_zone_name(zid)
    if (zid == nil or zid <= 0) then return '???'; end
    local rm = AshitaCore:GetResourceManager();
    if (rm == nil) then return string.format('Zone %d', zid); end
    return rm:GetString('zones.names', zid) or string.format('Zone %d', zid);
end

local function get_player_pos()
    local entity = GetPlayerEntity();
    if (entity == nil) then return nil; end
    -- DAT order (X, Z, Y).
    return entity.Movement.LocalPosition.X,
           entity.Movement.LocalPosition.Z,
           entity.Movement.LocalPosition.Y;
end

local function print_help()
    print(chat.header(addon.name):append(chat.message('Available commands:')));
    local cmds = T{
        { '/zl',                    'Toggle the settings window.' },
        { '/zl show / hide',        'Show or hide zone line markers.' },
        { '/zl list',               'Print zone lines for current zone.' },
        { '/zl resetui',            'Reset window size and position.' },
        { '/zl help',               'Show this help message.' },
    };
    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.success(v[1])):append(chat.message(' - ' .. v[2])));
    end);
end

-- Drop stale saved keys.
local function clean_saved(t)
    -- Old height overrides.
    local old = rawget(t, 'height_overrides');
    if (type(old) == 'table') then
        if (rawget(t, 'zoneline_overrides') == nil) then t.zoneline_overrides = T{}; end
        local ovr = t.zoneline_overrides;
        for key, val in pairs(old) do
            if (type(val) == 'number' and val ~= 0) then
                if (ovr[key] == nil) then ovr[key] = T{}; end
                if (rawget(ovr[key], 'height') == nil) then ovr[key].height = val; end
            end
        end
    end
    local dead = {};
    for k in pairs(t) do
        if (rawget(default_settings, k) == nil) then dead[#dead + 1] = k; end
    end
    for _, k in ipairs(dead) do t[k] = nil; end
    local moved = data.migrate_overrides(rawget(t, 'zoneline_overrides'));
    return #dead > 0 or moved;
end

ashita.events.register('load', 'zonelines_load', function()
    textures.log('---- loaded v' .. addon.version .. ' ----');
    s = settings.load(default_settings);
    if (clean_saved(s)) then pcall(settings.save); end

    pcall(renderer.scan_fonts);   -- Scan and load fonts.
    renderer.sync(s, default_settings);

    local config_path = AshitaCore:GetInstallPath() .. '\\config\\addons\\zonelines';
    data.init(config_path);
    data.set_features(s);

    ui.init(data, s, default_settings);
    pcall(client.init);
    conquest.init(s);

    local static_count = data.dat_total or 0;
    print(chat.header(addon.name):append(chat.message('v' .. addon.version .. ' loaded. '))
        :append(chat.success(tostring(static_count))):append(chat.message(' zone lines from DAT data. '))
        :append(chat.message('Use ')):append(chat.success('/zl'))
        :append(chat.message(' to toggle window.')));
end);

ashita.events.register('unload', 'zonelines_unload', function()
    pcall(late.release);
    pcall(ui.sync_settings);
    pcall(settings.save);
    pcall(renderer.shutdown_gdi);   -- Destroy native FontManager.
    pcall(textures.release_all);
    pcall(crests.release);
    pcall(function() require('signs').release(); end);
end);

ashita.events.register('command', 'zonelines_command', function(e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:lower():any('/zl', '/zonelines', '/zoneline')) then
        return;
    end

    e.blocked = true;

    local cmd = (#args >= 2) and args[2]:lower() or 'toggle';

    if (cmd == 'toggle') then
        ui.is_open[1] = not ui.is_open[1];
        return;
    end

    if (cmd == 'show') then
        s.visible = true;
        ui.apply_settings(s);
        pcall(settings.save);
        msg_success('All ZoneLines markers visible.');
        return;
    end

    if (cmd == 'hide') then
        s.visible = false;
        ui.apply_settings(s);
        pcall(settings.save);
        msg('All ZoneLines markers hidden. /zl show brings them back.');
        return;
    end

    if (cmd == 'help') then
        print_help();
        return;
    end

    if (cmd:any('resetui', 'reset_ui')) then
        ui.reset_pending = true;
        ui.is_open[1] = true;
        msg_success('Window position and size reset.');
        return;
    end

    if (cmd == 'list') then
        local zid = get_zone_id();
        if (zid == nil or zid <= 0) then
            msg_error('Not in a zone.');
            return;
        end

        local zone_lines = data.get_zone_lines(zid);
        local zn = get_zone_name(zid);
        msg(string.format('Zone lines for %s (%d):', zn, zid));

        if (#zone_lines == 0) then
            msg('  (none recorded)');
        else
            for _, zl in ipairs(zone_lines) do
                local dest = zl.display_name or '';
                if (dest ~= '') then
                    dest = '-> ' .. dest;
                end
                print(chat.header(addon.name):append(chat.message(
                    string.format('  #%d: (%.1f, %.1f, %.1f) [%s] %s',
                        zl.id, zl.x, zl.y, zl.z,
                        zl.source or '?',
                        dest)
                )));
            end
        end
        return;
    end

    msg_error('Unknown command. Use /zl help for usage.');
end);

-- Guarded conquest calls.
local conquest_err = false;
local function conquest_call(fn, a, b)
    local ok, err = pcall(fn, a, b);
    if (not ok and not conquest_err) then
        conquest_err = true;
        textures.log('conquest: ' .. tostring(err));
        print(chat.header(addon.name):append(chat.warning('Conquest crests hit an error and may be missing (logs\\zonelines.log).')));
    end
end

-- Hide markers while zoning.
ashita.events.register('packet_in', 'zonelines_pkt_in', function(e)
    if (e.id == 0x00B) then
        ground.hold();
        zoning = true;
        current_zone = 0;
        data.invalidate_cache();
        renderer.invalidate_curtain_cache();
    elseif (e.id == 0x00A) then
        ground.hold();
        if (pcall(client.on_00a, e.data, os.time())) then
            pcall(teleporters.refresh); pcall(docks.refresh); data.invalidate_cache();
        end
        zoning = false;
        conquest_call(conquest.on_zone_in, os.time());
    elseif (e.id == 0x05E) then
        conquest_call(conquest.on_05e, e.data, os.time());
    end
end);

-- Retry failures, then stop.
local RETRY_S, MAX_FAILS, CLEAR_S = 5, 3, 30;
local parts = {
    markers = { fails = 0, retry_at = 0, off = false, last = 0 },
    window  = { fails = 0, retry_at = 0, off = false, last = 0 },
};

local function part_ready(part)
    local p = parts[part];
    return not p.off and os.clock() >= p.retry_at;
end

local function part_ok(part)
    local p = parts[part];
    if (p.fails > 0 and os.clock() - p.last > CLEAR_S) then p.fails = 0; end
end

local function part_failed(part, what, err)
    local p = parts[part];
    local now = os.clock();
    p.fails = p.fails + 1;
    p.last = now;
    pcall(textures.log, what .. ' error: ' .. tostring(err));
    err = tostring(err):match('^[^\n]*');   -- First line in chat.
    if (p.fails >= MAX_FAILS) then
        p.off = true;
        print(chat.header(addon.name):append(chat.error(what .. ' stopped after repeated errors (' .. tostring(err) .. ').'))
            :append(chat.message(' Use ')):append(chat.success('/addon reload zonelines'))
            :append(chat.message(' to restart it.')));
    else
        p.retry_at = now + RETRY_S;
        if (p.fails == 1) then
            print(chat.header(addon.name):append(chat.error(what .. ' hit an error (' .. tostring(err) .. ').'))
                :append(chat.message(' Retrying in ' .. RETRY_S .. ' seconds.')));
        end
    end
end

-- Zone id shared per frame.
local frame_no, zone_stamp, zone_cached = 0, -1, 0;

local function draw_markers()
    if (s == nil or not s.visible) then return; end
    if (zoning or client.in_mog()) then return; end

    local zid = get_zone_id();
    zone_cached, zone_stamp = zid, frame_no;
    if (zid == nil or zid <= 0) then return; end

    local px, py, pz = get_player_pos();
    if (px == nil) then return; end

    local zone_lines = data.get_world_lines(zid);
    renderer.draw_d3d(zone_lines, px, py, pz, s);
    local dev = d3d8.get_device();
    if (dev ~= nil) then pcall(late.arm, dev); end
end

ashita.events.register('d3d_beginscene', 'zonelines_beginscene', function()
    renderer.d3d_pass = renderer.d3d_pass + 1;
    if (renderer.d3d_pass ~= 2 or not part_ready('markers')) then return; end
    local ok, err = pcall(draw_markers);
    if (ok) then part_ok('markers'); else part_failed('markers', 'Zone line markers', err); end
end);

-- Camera matrices and viewport.
local function cache_view()
    if (s == nil or not s.visible) then return; end
    renderer.cache_camera();
end

-- Zone tracking and settings.
local function update_window(fno)
    local zid = (zone_stamp == fno) and zone_cached or get_zone_id();
    if (zid == nil or zid <= 0) then return; end

    if (zid ~= current_zone) then
        current_zone = zid;
        zone_name = get_zone_name(zid);
        data.invalidate_cache();
        renderer.invalidate_curtain_cache();
    end

    if (ui.settings_dirty) then
        ui.settings_dirty = false;
        ui.sync_settings();
        data.set_features(s);
        renderer.mark_settings_dirty(ui.overrides_changed);
        ui.overrides_changed = false;
        ui.note_change();
    end

    if (not zoning) then pcall(transport.observe, current_zone, os.time()); end
    ui.render(current_zone, zone_name);
    if (s.visible and s.show_map_exits and not zoning and not client.in_mog()) then
        mapoverlay.draw(current_zone, data.get_map_lines(current_zone), s);
    end
    if (ui.save_due()) then pcall(settings.save); end
end

ashita.events.register('d3d_present', 'zonelines_present', function()
    local fno = frame_no;
    frame_no = fno + 1;
    renderer.d3d_pass = 0;
    pcall(late.cancel);
    conquest_call(conquest.tick, os.time(), zoning);
    if (part_ready('markers')) then
        local ok, err = pcall(cache_view);
        if (not ok) then part_failed('markers', 'Zone line markers', err); end
    end
    if (not part_ready('window')) then return; end
    local ok, err = pcall(update_window, fno);
    if (ok) then part_ok('window'); else part_failed('window', 'The Zone Lines window', err); end
end);

settings.register('settings', 'zonelines_settings_update', function(new_s)
    if (new_s ~= nil) then
        s = new_s;
        if (clean_saved(s)) then pcall(settings.save); end
        conquest.bind(s);
        renderer.sync(s, default_settings);
        data.set_features(s);
        renderer.mark_settings_dirty(true);
        ui.apply_settings(s);
    end
end);
