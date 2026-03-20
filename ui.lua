--[[
    ZoneLines v1.2.3 - ImGui Settings & Status Window
    Sidebar + detail panel layout matching MobHUD pattern.
    Categories: Markers, Labels, Colors, Fade, Zone Lines, Overrides.
]]--

require 'common';

local imgui    = require 'imgui';
local renderer = require 'renderer';

local ui = {};

-- Shared references (set by init)
local data_ref = nil;
local settings_ref = nil;
local defaults_ref = nil;

-- UI state
ui.is_open = T{ false };
ui.settings_dirty = false;
ui.reset_pending = false;

-------------------------------------------------------------------------------
-- Widget buffers packed into single table (LuaJIT upvalue limit)
-------------------------------------------------------------------------------

local B = {
    visible              = { true },
    render_distance      = { 100.0 },
    dot_size             = { 6.0 },
    dot_spacing          = { 1.0 },
    dot_glow             = { 0.15 },
    hover_height         = { 1.0 },
    rise_distance        = { 2.0 },
    d3d_text_scale       = { 1.0 },
    d3d_label_offset     = { 0.6 },
    d3d_text_min_scale   = { 0.5 },
    d3d_text_max_scale   = { 3.0 },
    d3d_show_labels      = { true },
    d3d_show_distance    = { true },
    d3d_text_outline     = { false },
    d3d_dist_pos_idx     = { 0 },
    d3d_label_spacing    = { 2 },
    dot_glow_enabled     = { true },
    dot_glow_speed       = { 2.0 },
    dot_glow_intensity   = { 0.5 },
    dot_glow_min         = { 0.4 },
    dot_glow_max         = { 1.0 },
    distance_fade        = { false },
    distance_fade_zone   = { 30.0 },
    dot_color            = { 0.0, 1.0, 0.0 },
    use_dist_colors      = { false },
    color_far            = { 0.0, 1.0, 0.0 },
    color_mid            = { 1.0, 1.0, 0.0 },
    color_close          = { 1.0, 0.0, 0.0 },
};

local DIST_POS_NAMES = 'Bottom\0Top\0Left\0Right\0';
local DIST_POS_VALUES = { 'bottom', 'top', 'left', 'right' };

-- Per-zone-line override buffers (keyed by tostring(rect_id))
local override_bufs = {};

-------------------------------------------------------------------------------
-- Color theme
-------------------------------------------------------------------------------

local colors = {
    sub       = { 1.0, 0.65, 0.26, 1.0 },  -- orange
    dimmed    = { 0.5, 0.5,  0.5,  1.0 },  -- grey
    info      = { 0.4, 0.8,  1.0,  1.0 },  -- cyan
    cat_sel   = { 0.20, 0.45, 0.20, 1.0 }, -- green selected
    cat_hover = { 0.25, 0.50, 0.25, 1.0 }, -- green hover
};

-------------------------------------------------------------------------------
-- Category definitions
-------------------------------------------------------------------------------

local CATEGORIES = { 'Markers', 'Labels', 'Colors', 'Fade', 'Zone Lines', 'Overrides' };
local selected_cat = 1;
local SIDEBAR_W = 110;

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function sub_header(label)
    imgui.TextColored(colors.sub, label);
    imgui.Separator();
end

local function tip(text)
    if (imgui.IsItemHovered()) then
        imgui.BeginTooltip();
        imgui.PushTextWrapPos(300);
        imgui.Text(text);
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end
end

-- Push all renderer-cached fields from B buffers (after reset or bulk update)
local function sync_renderer_fields()
    renderer.d3d_show_labels    = B.d3d_show_labels[1];
    renderer.d3d_show_distance  = B.d3d_show_distance[1];
    renderer.d3d_text_outline   = B.d3d_text_outline[1];
    renderer.d3d_dist_position  = DIST_POS_VALUES[B.d3d_dist_pos_idx[1] + 1] or 'bottom';
    renderer.d3d_label_spacing  = B.d3d_label_spacing[1];
    renderer.d3d_text_scale     = B.d3d_text_scale[1];
    renderer.d3d_label_offset   = B.d3d_label_offset[1];
    renderer.d3d_text_min_scale = B.d3d_text_min_scale[1];
    renderer.d3d_text_max_scale = B.d3d_text_max_scale[1];
    renderer.dot_glow_enabled   = B.dot_glow_enabled[1];
    renderer.dot_glow_speed     = B.dot_glow_speed[1];
    renderer.dot_glow_intensity = B.dot_glow_intensity[1];
    renderer.dot_glow_min       = B.dot_glow_min[1];
    renderer.dot_glow_max       = B.dot_glow_max[1];
end

-------------------------------------------------------------------------------
-- Sync settings <-> ImGui buffers
-------------------------------------------------------------------------------

local function sync_from_settings()
    if (settings_ref == nil) then return; end
    B.render_distance[1]    = settings_ref.render_distance or 100.0;
    B.dot_size[1]           = settings_ref.dot_size or 1.4;
    B.dot_spacing[1]        = settings_ref.dot_spacing or 0.3;
    B.dot_glow[1]           = settings_ref.dot_glow or 0.15;
    B.hover_height[1]       = settings_ref.hover_height or 0.5;
    B.rise_distance[1]      = settings_ref.rise_distance or 0.9;
    B.visible[1]            = (settings_ref.visible ~= false);
    B.d3d_text_scale[1]     = settings_ref.d3d_text_scale or 1.0;
    B.d3d_label_offset[1]   = settings_ref.d3d_label_offset or 0.6;
    B.d3d_text_min_scale[1] = settings_ref.d3d_text_min_scale or 0.5;
    B.d3d_text_max_scale[1] = settings_ref.d3d_text_max_scale or 3.0;
    B.d3d_show_labels[1]    = (settings_ref.d3d_show_labels ~= false);
    B.d3d_show_distance[1]  = (settings_ref.d3d_show_distance ~= false);
    B.d3d_text_outline[1]   = (settings_ref.d3d_text_outline == true);
    local dp = settings_ref.d3d_dist_position or 'bottom';
    for i = 1, #DIST_POS_VALUES do
        if (DIST_POS_VALUES[i] == dp) then B.d3d_dist_pos_idx[1] = i - 1; break; end
    end
    B.d3d_label_spacing[1]  = settings_ref.d3d_label_spacing or 2;
    B.dot_glow_enabled[1]   = (settings_ref.dot_glow_enabled ~= false);
    B.dot_glow_speed[1]     = settings_ref.dot_glow_speed or 2.0;
    B.dot_glow_intensity[1] = settings_ref.dot_glow_intensity or 0.5;
    B.dot_glow_min[1]       = settings_ref.dot_glow_min or 0.4;
    B.dot_glow_max[1]       = settings_ref.dot_glow_max or 1.0;
    B.distance_fade[1]      = (settings_ref.distance_fade == true);
    B.distance_fade_zone[1] = (settings_ref.distance_fade_zone or 0.3) * 100;
    local dc = settings_ref.dot_color or { 0, 1, 0 };
    B.dot_color[1] = dc[1] or 0; B.dot_color[2] = dc[2] or 1; B.dot_color[3] = dc[3] or 0;
    B.use_dist_colors[1] = (settings_ref.use_dist_colors == true);
    local cf = settings_ref.color_far or { 0, 1, 0 };
    B.color_far[1] = cf[1] or 0; B.color_far[2] = cf[2] or 1; B.color_far[3] = cf[3] or 0;
    local cm = settings_ref.color_mid or { 1, 1, 0 };
    B.color_mid[1] = cm[1] or 1; B.color_mid[2] = cm[2] or 1; B.color_mid[3] = cm[3] or 0;
    local cc = settings_ref.color_close or { 1, 0, 0 };
    B.color_close[1] = cc[1] or 1; B.color_close[2] = cc[2] or 0; B.color_close[3] = cc[3] or 0;

    -- Migrate old height_overrides -> zoneline_overrides
    if (settings_ref.height_overrides ~= nil and settings_ref.zoneline_overrides == nil) then
        settings_ref.zoneline_overrides = T{};
        for key, val in pairs(settings_ref.height_overrides) do
            if (val ~= nil and val ~= 0) then
                settings_ref.zoneline_overrides[key] = T{ height = val };
            end
        end
        settings_ref.height_overrides = nil;
    end
    -- Ensure zoneline_overrides exists
    if (settings_ref.zoneline_overrides == nil) then
        settings_ref.zoneline_overrides = T{};
    end
end

local function sync_to_settings()
    if (settings_ref == nil) then return; end
    settings_ref.render_distance    = B.render_distance[1];
    settings_ref.dot_size           = B.dot_size[1];
    settings_ref.dot_spacing        = B.dot_spacing[1];
    settings_ref.dot_glow           = B.dot_glow[1];
    settings_ref.hover_height       = B.hover_height[1];
    settings_ref.rise_distance      = B.rise_distance[1];
    settings_ref.visible            = B.visible[1];
    settings_ref.d3d_text_scale     = B.d3d_text_scale[1];
    settings_ref.d3d_label_offset   = B.d3d_label_offset[1];
    settings_ref.d3d_text_min_scale = B.d3d_text_min_scale[1];
    settings_ref.d3d_text_max_scale = B.d3d_text_max_scale[1];
    settings_ref.d3d_show_labels    = B.d3d_show_labels[1];
    settings_ref.d3d_show_distance  = B.d3d_show_distance[1];
    settings_ref.d3d_text_outline   = B.d3d_text_outline[1];
    settings_ref.d3d_dist_position  = DIST_POS_VALUES[B.d3d_dist_pos_idx[1] + 1] or 'bottom';
    settings_ref.d3d_label_spacing  = B.d3d_label_spacing[1];
    settings_ref.dot_glow_enabled   = B.dot_glow_enabled[1];
    settings_ref.dot_glow_speed     = B.dot_glow_speed[1];
    settings_ref.dot_glow_intensity = B.dot_glow_intensity[1];
    settings_ref.dot_glow_min       = B.dot_glow_min[1];
    settings_ref.dot_glow_max       = B.dot_glow_max[1];
    settings_ref.distance_fade      = B.distance_fade[1];
    settings_ref.distance_fade_zone = B.distance_fade_zone[1] / 100;
    settings_ref.dot_color      = T{ B.dot_color[1],   B.dot_color[2],   B.dot_color[3] };
    settings_ref.use_dist_colors = B.use_dist_colors[1];
    settings_ref.color_far      = T{ B.color_far[1],   B.color_far[2],   B.color_far[3] };
    settings_ref.color_mid      = T{ B.color_mid[1],   B.color_mid[2],   B.color_mid[3] };
    settings_ref.color_close    = T{ B.color_close[1], B.color_close[2], B.color_close[3] };
    -- zoneline_overrides synced directly when slider changes (not via buffers)
end

-------------------------------------------------------------------------------
-- Public sync (called from main before settings.save, matching other addons)
-------------------------------------------------------------------------------

function ui.sync_settings()
    sync_to_settings();
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function ui.init(data, s, defaults)
    data_ref = data;
    settings_ref = s;
    defaults_ref = defaults;
    sync_from_settings();
end

-------------------------------------------------------------------------------
-- Settings sync (called when settings change externally)
-------------------------------------------------------------------------------

function ui.apply_settings(s)
    settings_ref = s;
    sync_from_settings();
    -- Clear cached override buffers so they re-read from settings
    override_bufs = {};
end

-------------------------------------------------------------------------------
-- Category: Markers
-------------------------------------------------------------------------------

local function render_cat_markers()
    local changed = false;
    local c;

    sub_header('Shape');

    c = imgui.SliderFloat('Dot Size', B.dot_size, 1.0, 20.0, '%.1f');
    if (c) then changed = true; end
    tip('Size of each dot in world units.');

    c = imgui.SliderFloat('Dot Spacing', B.dot_spacing, 0.1, 5.0, '%.1f yalms');
    if (c) then changed = true; end
    tip('Distance between dots along the zone line.');

    c = imgui.SliderFloat('Hover Height', B.hover_height, 0.0, 4.0, '%.1f yalms');
    if (c) then changed = true; end
    tip('How far above the ground dots hover.');

    c = imgui.SliderFloat('Cliff Flatten', B.rise_distance, 0.5, 5.0, '%.1f yalms');
    if (c) then changed = true; end
    tip('Max height change per dot before flattening. Lower = flatter on slopes.');

    imgui.Spacing();
    sub_header('Glow Pulse');

    c = imgui.Checkbox('Enabled##glow_pulse', B.dot_glow_enabled);
    if (c) then
        changed = true;
        renderer.dot_glow_enabled = B.dot_glow_enabled[1];
    end
    tip('Enable glowing pulsating halos around dots.');

    if (B.dot_glow_enabled[1]) then
        imgui.SameLine();
        imgui.PushItemWidth(100);
        c = imgui.SliderFloat('Speed##glow', B.dot_glow_speed, 0.5, 20.0, '%.1f');
        if (c) then
            changed = true;
            renderer.dot_glow_speed = B.dot_glow_speed[1];
        end
        imgui.PopItemWidth();
        tip('Pulse speed (radians/sec). Higher = faster.');

        c = imgui.SliderFloat('Pulse Min', B.dot_glow_min, 0.0, 1.0, '%.2f');
        if (c) then
            changed = true;
            renderer.dot_glow_min = B.dot_glow_min[1];
        end
        tip('Minimum brightness of pulse cycle (0 = fully dim).');

        c = imgui.SliderFloat('Pulse Max', B.dot_glow_max, 0.0, 1.0, '%.2f');
        if (c) then
            changed = true;
            renderer.dot_glow_max = B.dot_glow_max[1];
        end
        tip('Maximum brightness of pulse cycle (1 = full bright).');

        c = imgui.SliderFloat('Glow Intensity', B.dot_glow_intensity, 0.1, 2.0, '%.2f');
        if (c) then
            changed = true;
            renderer.dot_glow_intensity = B.dot_glow_intensity[1];
        end
        tip('Overall glow brightness multiplier.');
    end

    imgui.Spacing();
    sub_header('Edge Glow');

    c = imgui.SliderFloat('Dot Glow', B.dot_glow, 0.0, 1.0, '%.2f');
    if (c) then changed = true; end
    tip('Edge glow intensity. 0 = sharp edges, 1 = solid fill.');

    if (changed) then
        sync_to_settings();
        ui.settings_dirty = true;
    end
end

-------------------------------------------------------------------------------
-- Category: Labels
-------------------------------------------------------------------------------

local function render_cat_labels()
    local changed = false;
    local c;

    sub_header('Display');

    c = imgui.Checkbox('Labels', B.d3d_show_labels);
    if (c) then
        changed = true;
        renderer.d3d_show_labels = B.d3d_show_labels[1];
    end
    tip('Show zone destination names above markers.');

    imgui.SameLine();
    c = imgui.Checkbox('Distance', B.d3d_show_distance);
    if (c) then
        changed = true;
        renderer.d3d_show_distance = B.d3d_show_distance[1];
    end
    tip('Show distance to zone line.');

    c = imgui.Checkbox('Text Outline', B.d3d_text_outline);
    if (c) then
        changed = true;
        renderer.d3d_text_outline = B.d3d_text_outline[1];
    end
    tip('Black outline around label text for readability.');

    if (B.d3d_show_distance[1]) then
        imgui.Spacing();
        sub_header('Distance Position');

        imgui.PushItemWidth(120);
        if (imgui.Combo('Position##distpos', B.d3d_dist_pos_idx, DIST_POS_NAMES)) then
            changed = true;
            renderer.d3d_dist_position = DIST_POS_VALUES[B.d3d_dist_pos_idx[1] + 1] or 'bottom';
        end
        imgui.PopItemWidth();
        tip('Position of distance relative to zone name.');

        c = imgui.SliderFloat('Label Gap', B.d3d_label_spacing, 0, 20, '%.0f');
        if (c) then
            changed = true;
            renderer.d3d_label_spacing = B.d3d_label_spacing[1];
        end
        tip('Extra pixel gap between zone name and distance text.');
    end

    imgui.Spacing();
    sub_header('Sizing');

    c = imgui.SliderFloat('Font Size', B.d3d_text_scale, 0.3, 3.0, '%.1f');
    if (c) then
        changed = true;
        renderer.d3d_text_scale = B.d3d_text_scale[1];
    end
    tip('Base font size multiplier for labels.');

    c = imgui.SliderFloat('Label Height', B.d3d_label_offset, 0.0, 5.0, '%.1f yalms');
    if (c) then
        changed = true;
        renderer.d3d_label_offset = B.d3d_label_offset[1];
    end
    tip('How far above the dots the label floats.');

    c = imgui.SliderFloat('Min Zoom', B.d3d_text_min_scale, 0.1, 2.0, '%.1f');
    if (c) then
        changed = true;
        renderer.d3d_text_min_scale = B.d3d_text_min_scale[1];
    end
    tip('Minimum font scale when far away.');

    c = imgui.SliderFloat('Max Zoom', B.d3d_text_max_scale, 1.0, 10.0, '%.1f');
    if (c) then
        changed = true;
        renderer.d3d_text_max_scale = B.d3d_text_max_scale[1];
    end
    tip('Maximum font scale when close up.');

    if (changed) then
        sync_to_settings();
        ui.settings_dirty = true;
    end
end

-------------------------------------------------------------------------------
-- Category: Colors
-------------------------------------------------------------------------------

local function render_cat_colors()
    local changed = false;
    local c;

    sub_header('Base');

    c = imgui.ColorEdit3('Dot Color', B.dot_color);
    if (c) then changed = true; end
    tip('Base color for all zone line dots.');

    imgui.Spacing();
    sub_header('Distance Colors');

    c = imgui.Checkbox('Distance Colors', B.use_dist_colors);
    if (c) then changed = true; end
    tip('Change dot color based on distance to zone line.');

    if (B.use_dist_colors[1]) then
        c = imgui.ColorEdit3('Far (20y+)', B.color_far);
        if (c) then changed = true; end
        tip('Dot color when 20+ yalms from zone line.');

        c = imgui.ColorEdit3('Mid (10-20y)', B.color_mid);
        if (c) then changed = true; end
        tip('Dot color when 10-20 yalms from zone line.');

        c = imgui.ColorEdit3('Close (<10y)', B.color_close);
        if (c) then changed = true; end
        tip('Dot color when under 10 yalms from zone line.');
    end

    if (changed) then
        sync_to_settings();
        ui.settings_dirty = true;
    end
end

-------------------------------------------------------------------------------
-- Category: Fade
-------------------------------------------------------------------------------

local function render_cat_fade()
    local changed = false;
    local c;

    sub_header('Render Distance');

    c = imgui.SliderFloat('Render Distance', B.render_distance, 10.0, 300.0, '%.0f yalms');
    if (c) then changed = true; end
    tip('Max distance to render zone line markers.');

    imgui.Spacing();
    sub_header('Distance Fade');

    c = imgui.Checkbox('Distance Fade', B.distance_fade);
    if (c) then changed = true; end
    tip('Shrink dots smoothly near render distance edge instead of hard cutoff.');

    if (B.distance_fade[1]) then
        c = imgui.SliderFloat('Fade Zone##fadezone', B.distance_fade_zone, 5.0, 100.0, '%.0f%%');
        if (c) then changed = true; end
        tip('Percentage of render distance where dots fade in. Higher = longer gradual fade.');
    end

    if (changed) then
        sync_to_settings();
        ui.settings_dirty = true;
    end
end

-------------------------------------------------------------------------------
-- Category: Zone Lines
-------------------------------------------------------------------------------

local function render_cat_zonelines(zone_id)
    local zone_lines = data_ref.get_zone_lines(zone_id);

    if (#zone_lines == 0) then
        imgui.TextColored(colors.dimmed, 'No zone lines for this zone.');
        return;
    end

    local flags = ImGuiTableFlags_Borders
        + ImGuiTableFlags_RowBg
        + ImGuiTableFlags_Resizable
        + ImGuiTableFlags_ScrollY;

    if (imgui.BeginTable('##zone_lines_table', 4, flags, { 0, 0 })) then
        imgui.TableSetupColumn('Destination', ImGuiTableColumnFlags_WidthStretch);
        imgui.TableSetupColumn('Position', ImGuiTableColumnFlags_WidthFixed, 150);
        imgui.TableSetupColumn('Size', ImGuiTableColumnFlags_WidthFixed, 100);
        imgui.TableSetupColumn('Src', ImGuiTableColumnFlags_WidthFixed, 55);
        imgui.TableHeadersRow();

        for _, zl in ipairs(zone_lines) do
            imgui.TableNextRow();

            -- Destination
            imgui.TableNextColumn();
            local dest = zl.display_name;
            if (dest == nil or dest == '') then
                dest = '--';
            end
            imgui.Text(dest);

            -- Position
            imgui.TableNextColumn();
            imgui.Text(string.format('%.0f, %.0f, %.0f', zl.x or 0, zl.y or 0, zl.z or 0));

            -- Size (bounding box dimensions)
            imgui.TableNextColumn();
            imgui.Text(string.format('%.0fx%.0fx%.0f',
                zl.sx or 0, zl.sy or 0, zl.sz or 0));

            -- Source (dat + zone ID, or trig)
            imgui.TableNextColumn();
            if (zl.source == 'dat') then
                local zid = zl.to_zone or 0;
                imgui.TextColored(colors.info, string.format('dat%d', zid));
            else
                imgui.TextColored({ 0.8, 0.6, 0.2, 1.0 }, 'trig');
            end
        end

        imgui.EndTable();
    end
end

-------------------------------------------------------------------------------
-- Category: Overrides
-------------------------------------------------------------------------------

local function render_cat_overrides(zone_id)
    imgui.TextColored(colors.dimmed, 'Per-zone-line overrides. Expand an entry to adjust.');
    imgui.Spacing();

    local zone_lines = data_ref.get_zone_lines(zone_id);
    local has_entry = false;

    for _, zl in ipairs(zone_lines) do
        -- Show any zone line with a valid rect_id and bounding box
        if (zl.rect_id ~= nil and zl.rect_id ~= 0
            and zl.sx ~= nil and zl.sx > 0 and zl.sz ~= nil and zl.sz > 0) then

            has_entry = true;
            local key = tostring(zl.rect_id);
            local is_circle = (zl.shape == 'circle');

            -- Lazy-create buffers for this zone line
            -- Use rawget to avoid T{} sugar methods (e.g. .flatten is a T{} method)
            if (override_bufs[key] == nil) then
                local existing = settings_ref.zoneline_overrides[key] or {};
                local rg = (type(existing) == 'table') and rawget or function(t, k) return t[k]; end;
                override_bufs[key] = {
                    height      = { rg(existing, 'height')      or 0 },
                    trim        = { rg(existing, 'trim')        or 0 },
                    flatten     = { rg(existing, 'flatten')     or 0 },
                    hide        = { rg(existing, 'hide') == true },
                    pole_height = { rg(existing, 'pole_height') or 0 },
                };
            end

            local dest = zl.display_name;
            if (dest == nil or dest == '') then dest = 'Zone Line'; end

            imgui.PushID('zlo_' .. key);
            if (imgui.TreeNode(dest .. '##' .. key)) then
                local bufs = override_bufs[key];
                local changed = false;

                local c = imgui.Checkbox('Hide', bufs.hide);
                if (c) then changed = true; end
                tip('Hide this zone line (e.g. door-activated zones).');

                if (is_circle) then
                    -- Circle markers: pole height control
                    c = imgui.SliderFloat('Pole Height', bufs.pole_height, 0.0, 15.0, '%.1f yalms');
                    if (c) then changed = true; end
                    tip('Vertical pole height. 0 = use default (4 yalms).');
                else
                    -- Curtain markers: height, trim, flatten controls
                    c = imgui.SliderFloat('Height', bufs.height, -5.0, 5.0, '%.1f yalms');
                    if (c) then changed = true; end
                    tip('Height offset. Positive = higher, 0 = auto terrain.');

                    c = imgui.SliderFloat('Trim', bufs.trim, 0.0, 6.0, '%.1f yalms');
                    if (c) then changed = true; end
                    tip('Inset dots from each edge. Use to avoid railings/walls.');

                    c = imgui.SliderFloat('Cliff Flatten', bufs.flatten, 0.0, 5.0, '%.1f yalms');
                    if (c) then changed = true; end
                    tip('Max height change per dot before flattening. 0 = use global setting.');
                end

                if (changed) then
                    local h = bufs.height[1];
                    local t = bufs.trim[1];
                    local f = bufs.flatten[1];
                    local hid = bufs.hide[1];
                    local ph = bufs.pole_height[1];
                    -- Store entry only if any value is non-default
                    local all_default = (math.abs(h) < 0.05 and math.abs(t) < 0.05
                        and math.abs(f) < 0.05 and math.abs(ph) < 0.05 and not hid);
                    if (all_default) then
                        settings_ref.zoneline_overrides[key] = nil;
                    else
                        settings_ref.zoneline_overrides[key] = T{
                            height      = (math.abs(h) >= 0.05) and h or nil,
                            trim        = (math.abs(t) >= 0.05) and t or nil,
                            flatten     = (math.abs(f) >= 0.05) and f or nil,
                            hide        = hid or nil,
                            pole_height = (math.abs(ph) >= 0.05) and ph or nil,
                        };
                    end
                    ui.settings_dirty = true;
                end

                imgui.TreePop();
            end
            imgui.PopID();
        end
    end

    if (not has_entry) then
        imgui.TextColored(colors.dimmed, 'No adjustable zone lines in this zone.');
    end
end

-------------------------------------------------------------------------------
-- Renderer dispatch table
-------------------------------------------------------------------------------

local cat_renderers = {
    render_cat_markers,
    render_cat_labels,
    render_cat_colors,
    render_cat_fade,
    render_cat_zonelines,
    render_cat_overrides,
};

-------------------------------------------------------------------------------
-- Main render: header + sidebar + detail panel + footer
-------------------------------------------------------------------------------

function ui.render(zone_id, zone_name)
    if (not ui.is_open[1]) then return; end
    if (data_ref == nil or settings_ref == nil) then return; end

    -- Handle reset
    if (ui.reset_pending) then
        ui.reset_pending = false;
        imgui.SetNextWindowSize({ 560, 480 }, ImGuiCond_Always);
        imgui.SetNextWindowPos({ 100, 100 }, ImGuiCond_Always);
    end

    imgui.SetNextWindowSize({ 560, 480 }, ImGuiCond_FirstUseEver);
    if (imgui.Begin('Zone Lines v1.2.3##zonelines', ui.is_open, ImGuiWindowFlags_None)) then

        -- Header: visibility toggle + zone info (always visible)
        local vis_changed = imgui.Checkbox('Show Markers', B.visible);
        if (vis_changed) then
            sync_to_settings();
            ui.settings_dirty = true;
        end
        tip('Toggle zone line marker visibility.');

        imgui.SameLine();
        imgui.TextColored(colors.info,
            string.format('%s (%d)', zone_name or '???', zone_id or 0));

        local total = data_ref.get_total_count();
        local static = data_ref.static_total or 0;
        imgui.SameLine();
        imgui.TextColored(colors.dimmed,
            string.format('DAT: %d  Total: %d', static, total));

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        -- Reserve footer height (separator + line + spacing)
        local footer_h = imgui.GetFrameHeightWithSpacing() + imgui.GetStyle().ItemSpacing.y + 4;

        -- Left sidebar
        imgui.BeginChild('##sidebar', { SIDEBAR_W, -footer_h }, ImGuiChildFlags_Borders);
        imgui.PushStyleColor(ImGuiCol_Header, colors.cat_sel);
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, colors.cat_hover);
        imgui.PushStyleColor(ImGuiCol_HeaderActive, colors.cat_sel);
        for ci = 1, #CATEGORIES do
            if (imgui.Selectable(CATEGORIES[ci] .. '##cat' .. tostring(ci), ci == selected_cat)) then
                selected_cat = ci;
            end
        end
        imgui.PopStyleColor(3);
        imgui.EndChild();

        -- Right detail panel
        imgui.SameLine();
        imgui.BeginChild('##detail', { 0, -footer_h }, ImGuiChildFlags_Borders);
        local renderer_fn = cat_renderers[selected_cat];
        if (renderer_fn ~= nil) then
            -- Zone Lines and Overrides need zone_id
            if (selected_cat >= 5) then
                renderer_fn(zone_id);
            else
                renderer_fn();
            end
        end
        imgui.EndChild();

        -- Footer
        imgui.Separator();
        imgui.TextColored(colors.dimmed, '/zl help');
        -- Right-align reset button (get full width before SameLine moves cursor)
        local reset_w = 180;
        local content_w = imgui.GetContentRegionAvail();
        imgui.SameLine(content_w - reset_w);
        if (defaults_ref ~= nil) then
            if (imgui.Button('Reset to Defaults', { reset_w, 0 })) then
                -- Deep copy defaults so we don't mutate the defaults table
                for k, v in pairs(defaults_ref) do
                    if (type(v) == 'table') then
                        local copy = T{};
                        for ik, iv in pairs(v) do
                            if (type(iv) == 'table') then
                                local inner = T{};
                                for jk, jv in pairs(iv) do inner[jk] = jv; end
                                copy[ik] = inner;
                            else
                                copy[ik] = iv;
                            end
                        end
                        settings_ref[k] = copy;
                    else
                        settings_ref[k] = v;
                    end
                end
                override_bufs = {};
                sync_from_settings();
                sync_renderer_fields();
                ui.settings_dirty = true;
            end
            tip('Reset all settings and overrides to defaults.');
        end
    end
    imgui.End();
end

return ui;
