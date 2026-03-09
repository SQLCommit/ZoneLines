--[[
    ZoneLines v1.1.0 - Zone Line Visualizer for Ashita v4

    Draws ground markers at zone line positions to help players see
    invisible zone transition boundaries. Zone lines are pre-extracted
    from FFXI DAT files.

    Commands:
        /zl              - Toggle the settings window
        /zl show | hide  - Show or hide markers
        /zl list         - Print zone lines for current zone
        /zl resetui      - Reset window size and position
        /zl help         - Show command help

    Author: SQLCommit
    Version: 1.1.0
]]--

addon.name    = 'zonelines';
addon.author  = 'SQLCommit';
addon.version = '1.1.0';
addon.desc    = 'Visualizes zone line boundaries with ground markers.';
addon.link    = 'https://github.com/SQLCommit/zonelines';

require 'common';

local chat     = require 'chat';
local d3d8     = require 'd3d8';
local settings = require 'settings';

local data     = require 'data';
local renderer = require 'renderer';
local ui       = require 'ui';

-------------------------------------------------------------------------------
-- Default Settings (saved per-character via Ashita settings)
-------------------------------------------------------------------------------
local default_settings = T{
    visible          = true,
    render_distance  = 300.0,
    dot_size         = 1.4,
    dot_spacing      = 0.3,
    dot_glow         = 0.8,
    hover_height     = 0.5,
    rise_distance    = 0.9,
    dot_color        = T{ 0.0, 1.0, 0.94 },  -- main dot color
    use_dist_colors  = false,                  -- use distance-based colors
    color_far        = T{ 0.0, 1.0, 0.0 },   -- green  (>= 20y)
    color_mid        = T{ 1.0, 1.0, 0.0 },   -- yellow (< 20y)
    color_close      = T{ 1.0, 0.0, 0.0 },   -- red    (< 10y)
    d3d_text_scale       = 0.9,
    d3d_label_offset     = 0.5,
    d3d_text_min_scale   = 0.7,
    d3d_text_max_scale   = 2.3,
    d3d_show_labels      = true,
    d3d_show_distance    = true,
    d3d_dist_position    = 'bottom',  -- 'bottom', 'top', 'left', 'right'
    d3d_label_spacing    = 8,         -- extra pixel gap between name and distance
    dot_glow_enabled     = true,      -- pulsating dots
    dot_glow_speed       = 2.0,       -- pulse speed (radians/sec)
    dot_glow_intensity   = 0.5,       -- glow brightness multiplier
    dot_glow_min         = 0.4,       -- pulse minimum (0-1)
    dot_glow_max         = 1.0,       -- pulse maximum (0-1)
    zoneline_overrides   = T{
        ['846018170']  = T{ trim = 1.5 },
        ['846083706']  = T{ trim = 1.3 },
        ['846214778']  = T{ height = 0.5 },
        ['812529274']  = T{ trim = 1.7 },
        ['813119098']  = T{ trim = 2.9 },
        ['879572602']  = T{ trim = 0.4 },
        ['879769210']  = T{ trim = 4.9 },
        ['946287482']  = T{ trim = 4.5 },
        ['946287738']  = T{ height = 0.5 },
        ['1634088570'] = T{ hide = true },           -- N.Sandy Carpenter's Landing (door)
        ['1634153338'] = T{ trim = 3.9, flatten = 0.1 },
        ['1869770106'] = T{ trim = 3.7 },            -- Mog House trim
        ['1936878970'] = T{ trim = 3.7 },            -- Mog House trim
        ['1970433402'] = T{ trim = 3.7 },            -- Mog House trim
        ['923901']     = T{ pole_height = 1.7 },     -- Windurst Walls → Heaven's Tower
        ['924201']     = T{ pole_height = 1.7 },     -- Heaven's Tower → Windurst Walls
    },
};

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local s = nil;           -- settings reference
local current_zone = 0;
local zone_name = '';

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

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
    -- Entity position_t field order is X, Z, Y in memory:
    --   .X = east/west,  .Z = elevation,  .Y = north/south
    -- DAT data uses: x=east/west, y=elevation, z=north/south
    -- Return in DAT order so coordinates align for distance + projection.
    return entity.Movement.LocalPosition.X,
           entity.Movement.LocalPosition.Z,
           entity.Movement.LocalPosition.Y;
end

-------------------------------------------------------------------------------
-- Help
-------------------------------------------------------------------------------
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

-------------------------------------------------------------------------------
-- Sync settings to renderer fields
-------------------------------------------------------------------------------
local function sync_renderer(settings_ref)
    renderer.d3d_text_scale     = settings_ref.d3d_text_scale or 1.0;
    renderer.d3d_label_offset   = settings_ref.d3d_label_offset or 0.6;
    renderer.d3d_text_min_scale = settings_ref.d3d_text_min_scale or 0.5;
    renderer.d3d_text_max_scale = settings_ref.d3d_text_max_scale or 3.0;
    renderer.d3d_show_labels    = (settings_ref.d3d_show_labels ~= false);
    renderer.d3d_show_distance  = (settings_ref.d3d_show_distance ~= false);
    renderer.d3d_dist_position  = settings_ref.d3d_dist_position or 'bottom';
    renderer.d3d_label_spacing  = settings_ref.d3d_label_spacing or 2;
    renderer.dot_glow_enabled   = (settings_ref.dot_glow_enabled ~= false);
    renderer.dot_glow_speed     = settings_ref.dot_glow_speed or 2.0;
    renderer.dot_glow_intensity = settings_ref.dot_glow_intensity or 0.5;
    renderer.dot_glow_min       = settings_ref.dot_glow_min or 0.4;
    renderer.dot_glow_max       = settings_ref.dot_glow_max or 1.0;
end

-------------------------------------------------------------------------------
-- Event: Load
-------------------------------------------------------------------------------
ashita.events.register('load', 'zonelines_load', function()
    s = settings.load(default_settings);

    -- D3D depth-tested rendering is always on
    renderer.hide_behind_walls = true;
    sync_renderer(s);

    -- Initialize data layer (loads zone line data from DAT files)
    local config_path = AshitaCore:GetInstallPath() .. '\\config\\addons\\zonelines';
    data.init(config_path);

    -- Initialize UI
    ui.init(data, s, default_settings);

    local static_count = data.static_total or 0;
    print(chat.header(addon.name):append(chat.message('v' .. addon.version .. ' loaded. '))
        :append(chat.success(tostring(static_count))):append(chat.message(' zone lines from DAT data. '))
        :append(chat.message('Use ')):append(chat.success('/zl'))
        :append(chat.message(' to toggle window.')));
end);

-------------------------------------------------------------------------------
-- Event: Unload
-------------------------------------------------------------------------------
ashita.events.register('unload', 'zonelines_unload', function()
    ui.sync_settings();
    pcall(settings.save);
end);

-------------------------------------------------------------------------------
-- Event: Command
-------------------------------------------------------------------------------
ashita.events.register('command', 'zonelines_command', function(e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/zl', '/zonelines', '/zoneline')) then
        return;
    end

    e.blocked = true;

    local cmd = (#args >= 2) and args[2]:lower() or 'toggle';

    -- /zl - Toggle window
    if (cmd == 'toggle') then
        ui.is_open[1] = not ui.is_open[1];
        return;
    end

    -- /zl show
    if (cmd == 'show') then
        s.visible = true;
        settings.save();
        msg_success('Zone line markers visible.');
        return;
    end

    -- /zl hide
    if (cmd == 'hide') then
        s.visible = false;
        settings.save();
        msg('Zone line markers hidden.');
        return;
    end

    -- /zl help
    if (cmd == 'help') then
        print_help();
        return;
    end

    -- /zl resetui
    if (cmd:any('resetui', 'reset_ui')) then
        ui.reset_pending = true;
        ui.is_open[1] = true;
        msg_success('Window position and size reset.');
        return;
    end

    -- /zl list
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

-------------------------------------------------------------------------------
-- Event: Incoming Packet (zone change detection)
-------------------------------------------------------------------------------
ashita.events.register('packet_in', 'zonelines_packet_in', function(e)
    -- 0x000A: Zone Enter — refresh cache for new zone
    if (e.id == 0x000A) then
        data.invalidate_cache();
    end
end);

-------------------------------------------------------------------------------
-- Event: d3d_beginscene (D3D8 depth-tested marker rendering)
-- Draws markers as 3D primitives on pass 2 (before game renders world).
-- Game geometry naturally occludes our markers via the depth buffer.
-------------------------------------------------------------------------------
ashita.events.register('d3d_beginscene', 'zonelines_beginscene', function()
    renderer.d3d_pass = renderer.d3d_pass + 1;
    if (renderer.d3d_pass ~= 2) then return; end
    if (not renderer.hide_behind_walls) then return; end
    if (s == nil or not s.visible) then return; end

    local zid = get_zone_id();
    if (zid == nil or zid <= 0) then return; end

    local px, py, pz = get_player_pos();
    if (px == nil) then return; end

    local zone_lines = data.get_zone_lines(zid);
    renderer.draw_d3d(zone_lines, px, py, pz, s);
end);

-------------------------------------------------------------------------------
-- Event: d3d_present (ImGui rendering + UI window)
-- Draws text labels and the settings window.
-- Also caches view matrix and resets pass counter for next frame.
-------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'zonelines_present', function()
    -- Reset pass counter for next frame
    renderer.d3d_pass = 0;

    -- Cache view matrix for billboard orientation in next frame's beginscene
    if (s ~= nil and renderer.hide_behind_walls and s.visible) then
        local dev = d3d8.get_device();
        if (dev ~= nil) then
            local _, v = dev:GetTransform(2);  -- D3DTS_VIEW
            if (v ~= nil) then
                local ok, tbl = pcall(renderer.copy_matrix, v);
                if (ok and type(tbl._11) == 'number') then renderer.cached_view = tbl; end
            end
            local _, p = dev:GetTransform(3);  -- D3DTS_PROJECTION
            if (p ~= nil) then
                local ok, tbl = pcall(renderer.copy_matrix, p);
                if (ok and type(tbl._11) == 'number') then renderer.cached_proj = tbl; end
            end
            local _, vp = dev:GetViewport();
            if (vp ~= nil) then
                renderer.cached_vp_w = vp.Width;
                renderer.cached_vp_h = vp.Height;
            end
        end

        -- Initialize font atlas for D3D text (deferred — ImGui ready at d3d_present)
        if (not renderer.is_font_atlas_ready()) then
            pcall(renderer.init_font_atlas);
        end
    end

    -- Character login gate
    local zid = get_zone_id();
    if (zid == nil or zid <= 0) then return; end

    -- Track zone changes
    if (zid ~= current_zone) then
        current_zone = zid;
        zone_name = get_zone_name(zid);
        data.invalidate_cache();
    end

    -- Save settings if UI flagged a change
    if (ui.settings_dirty) then
        ui.settings_dirty = false;
        ui.sync_settings();
        renderer.mark_settings_dirty();
        settings.save();
    end

    -- Sync settings and initialize font atlas for D3D text
    local px, py, pz = get_player_pos();
    if (s ~= nil and s.visible and px ~= nil) then
        local zone_lines = data.get_zone_lines(current_zone);
        renderer.render(zone_lines, px, py, pz, s);
    end

    -- Draw UI window
    ui.render(current_zone, zone_name);
end);

-------------------------------------------------------------------------------
-- Event: Settings changed externally
-------------------------------------------------------------------------------
settings.register('settings', 'zonelines_settings_update', function(new_s)
    if (new_s ~= nil) then
        s = new_s;
        sync_renderer(s);
        renderer.mark_settings_dirty();
        ui.apply_settings(s);
    end
end);
