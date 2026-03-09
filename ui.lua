--[[
    ZoneLines v1.1.0 - ImGui Settings & Status Window
    Displays zone line bounding boxes for the current zone with
    rendering settings and zone line information.
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

-- ImGui buffer variables (widgets need { value } tables, not plain values)
local buf_render_distance  = { 100.0 };
local buf_dot_size         = { 6.0 };
local buf_dot_spacing      = { 1.0 };
local buf_dot_glow         = { 0.15 };
local buf_hover_height     = { 1.0 };
local buf_rise_distance    = { 2.0 };
local buf_visible            = { true };
local buf_d3d_text_scale     = { 1.0 };
local buf_d3d_label_offset   = { 0.6 };
local buf_d3d_text_min_scale = { 0.5 };
local buf_d3d_text_max_scale = { 3.0 };
local buf_d3d_show_labels    = { true };
local buf_d3d_show_distance  = { true };
local buf_d3d_dist_pos_idx  = { 0 };
local DIST_POS_NAMES = 'Bottom\0Top\0Left\0Right\0';
local DIST_POS_VALUES = { 'bottom', 'top', 'left', 'right' };
local buf_d3d_label_spacing  = { 2 };
local buf_dot_glow_enabled   = { true };
local buf_dot_glow_speed     = { 2.0 };
local buf_dot_glow_intensity = { 0.5 };
local buf_dot_glow_min       = { 0.4 };
local buf_dot_glow_max       = { 1.0 };
local buf_dot_color          = { 0.0, 1.0, 0.0 };
local buf_use_dist_colors    = { false };
local buf_color_far          = { 0.0, 1.0, 0.0 };
local buf_color_mid          = { 1.0, 1.0, 0.0 };
local buf_color_close        = { 1.0, 0.0, 0.0 };

-- Per-zone-line override buffers (keyed by tostring(rect_id))
-- Each entry: { height = {0}, trim = {0}, flatten = {0} }
local override_bufs = {};

-------------------------------------------------------------------------------
-- Sync settings <-> ImGui buffers
-------------------------------------------------------------------------------

local function sync_from_settings()
    if (settings_ref == nil) then return; end
    buf_render_distance[1]  = settings_ref.render_distance or 100.0;
    buf_dot_size[1]         = settings_ref.dot_size or 1.4;
    buf_dot_spacing[1]      = settings_ref.dot_spacing or 0.3;
    buf_dot_glow[1]         = settings_ref.dot_glow or 0.15;
    buf_hover_height[1]     = settings_ref.hover_height or 0.5;
    buf_rise_distance[1]    = settings_ref.rise_distance or 0.9;
    buf_visible[1]              = (settings_ref.visible ~= false);
    buf_d3d_text_scale[1]       = settings_ref.d3d_text_scale or 1.0;
    buf_d3d_label_offset[1]     = settings_ref.d3d_label_offset or 0.6;
    buf_d3d_text_min_scale[1]   = settings_ref.d3d_text_min_scale or 0.5;
    buf_d3d_text_max_scale[1]   = settings_ref.d3d_text_max_scale or 3.0;
    buf_d3d_show_labels[1]      = (settings_ref.d3d_show_labels ~= false);
    buf_d3d_show_distance[1]    = (settings_ref.d3d_show_distance ~= false);
    local dp = settings_ref.d3d_dist_position or 'bottom';
    for i = 1, #DIST_POS_VALUES do
        if (DIST_POS_VALUES[i] == dp) then buf_d3d_dist_pos_idx[1] = i - 1; break; end
    end
    buf_d3d_label_spacing[1]  = settings_ref.d3d_label_spacing or 2;
    buf_dot_glow_enabled[1]   = (settings_ref.dot_glow_enabled ~= false);
    buf_dot_glow_speed[1]     = settings_ref.dot_glow_speed or 2.0;
    buf_dot_glow_intensity[1] = settings_ref.dot_glow_intensity or 0.5;
    buf_dot_glow_min[1]       = settings_ref.dot_glow_min or 0.4;
    buf_dot_glow_max[1]       = settings_ref.dot_glow_max or 1.0;
    local dc = settings_ref.dot_color or { 0, 1, 0 };
    buf_dot_color[1] = dc[1] or 0; buf_dot_color[2] = dc[2] or 1; buf_dot_color[3] = dc[3] or 0;
    buf_use_dist_colors[1] = (settings_ref.use_dist_colors == true);
    local cf = settings_ref.color_far or { 0, 1, 0 };
    buf_color_far[1] = cf[1] or 0; buf_color_far[2] = cf[2] or 1; buf_color_far[3] = cf[3] or 0;
    local cm = settings_ref.color_mid or { 1, 1, 0 };
    buf_color_mid[1] = cm[1] or 1; buf_color_mid[2] = cm[2] or 1; buf_color_mid[3] = cm[3] or 0;
    local cc = settings_ref.color_close or { 1, 0, 0 };
    buf_color_close[1] = cc[1] or 1; buf_color_close[2] = cc[2] or 0; buf_color_close[3] = cc[3] or 0;

    -- Migrate old height_overrides → zoneline_overrides
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
    settings_ref.render_distance  = buf_render_distance[1];
    settings_ref.dot_size         = buf_dot_size[1];
    settings_ref.dot_spacing      = buf_dot_spacing[1];
    settings_ref.dot_glow         = buf_dot_glow[1];
    settings_ref.hover_height     = buf_hover_height[1];
    settings_ref.rise_distance    = buf_rise_distance[1];
    settings_ref.visible              = buf_visible[1];
    settings_ref.d3d_text_scale       = buf_d3d_text_scale[1];
    settings_ref.d3d_label_offset     = buf_d3d_label_offset[1];
    settings_ref.d3d_text_min_scale   = buf_d3d_text_min_scale[1];
    settings_ref.d3d_text_max_scale   = buf_d3d_text_max_scale[1];
    settings_ref.d3d_show_labels      = buf_d3d_show_labels[1];
    settings_ref.d3d_show_distance    = buf_d3d_show_distance[1];
    settings_ref.d3d_dist_position    = DIST_POS_VALUES[buf_d3d_dist_pos_idx[1] + 1] or 'bottom';
    settings_ref.d3d_label_spacing    = buf_d3d_label_spacing[1];
    settings_ref.dot_glow_enabled     = buf_dot_glow_enabled[1];
    settings_ref.dot_glow_speed       = buf_dot_glow_speed[1];
    settings_ref.dot_glow_intensity   = buf_dot_glow_intensity[1];
    settings_ref.dot_glow_min         = buf_dot_glow_min[1];
    settings_ref.dot_glow_max         = buf_dot_glow_max[1];
    settings_ref.dot_color   = T{ buf_dot_color[1],   buf_dot_color[2],   buf_dot_color[3] };
    settings_ref.use_dist_colors = buf_use_dist_colors[1];
    settings_ref.color_far   = T{ buf_color_far[1],   buf_color_far[2],   buf_color_far[3] };
    settings_ref.color_mid   = T{ buf_color_mid[1],   buf_color_mid[2],   buf_color_mid[3] };
    settings_ref.color_close = T{ buf_color_close[1], buf_color_close[2], buf_color_close[3] };
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
-- Render
-------------------------------------------------------------------------------

function ui.render(zone_id, zone_name)
    if (not ui.is_open[1]) then return; end
    if (zone_id == nil or zone_id <= 0) then return; end
    if (data_ref == nil or settings_ref == nil) then return; end

    -- Handle reset
    if (ui.reset_pending) then
        ui.reset_pending = false;
        imgui.SetNextWindowSize({ 560, 450 }, ImGuiCond_Always);
        imgui.SetNextWindowPos({ 100, 100 }, ImGuiCond_Always);
    end

    imgui.SetNextWindowSize({ 560, 450 }, ImGuiCond_FirstUseEver);
    if (imgui.Begin('Zone Lines##zonelines', ui.is_open, ImGuiWindowFlags_None)) then
        -- Visibility toggle
        local vis_changed = imgui.Checkbox('Show Markers', buf_visible);
        if (vis_changed) then
            sync_to_settings();
            ui.settings_dirty = true;
        end
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('Toggle zone line marker visibility.');
        end

        imgui.SameLine();

        -- Header
        imgui.TextColored({ 0.3, 0.7, 1.0, 1.0 },
            string.format('Zone: %s (ID: %d)', zone_name or '???', zone_id));

        local total = data_ref.get_total_count();
        local static = data_ref.static_total or 0;
        imgui.SameLine();
        imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 },
            string.format('| DAT: %d | Total: %d', static, total));

        imgui.Separator();
        imgui.Spacing();

        -- Settings section
        local settings_open = imgui.CollapsingHeader('Settings');
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('Rendering settings: labels, dots, colors, distances.');
        end
        if (settings_open) then
            imgui.Spacing();

            local changed = false;
            local c;

            c = imgui.Checkbox('Labels', buf_d3d_show_labels);
            if (c) then
                changed = true;
                renderer.d3d_show_labels = buf_d3d_show_labels[1];
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Show zone destination names above markers.');
            end

            c = imgui.Checkbox('Distance', buf_d3d_show_distance);
            if (c) then
                changed = true;
                renderer.d3d_show_distance = buf_d3d_show_distance[1];
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Show distance to zone line.');
            end
            if (buf_d3d_show_distance[1]) then
                imgui.SameLine();
                imgui.PushItemWidth(100);
                if (imgui.Combo('Position##distpos', buf_d3d_dist_pos_idx, DIST_POS_NAMES)) then
                    changed = true;
                    renderer.d3d_dist_position = DIST_POS_VALUES[buf_d3d_dist_pos_idx[1] + 1] or 'bottom';
                end
                imgui.PopItemWidth();
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip('Position of distance relative to zone name.');
                end
            end

            c = imgui.SliderFloat('Label Gap', buf_d3d_label_spacing, 0, 20, '%.0f');
            if (c) then
                changed = true;
                renderer.d3d_label_spacing = buf_d3d_label_spacing[1];
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Extra pixel gap between zone name and distance text.');
            end

            c = imgui.SliderFloat('Font Size', buf_d3d_text_scale, 0.3, 3.0, '%.1f');
            if (c) then
                changed = true;
                renderer.d3d_text_scale = buf_d3d_text_scale[1];
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Base font size multiplier for labels.');
            end

            c = imgui.SliderFloat('Label Height', buf_d3d_label_offset, 0.0, 5.0, '%.1f yalms');
            if (c) then
                changed = true;
                renderer.d3d_label_offset = buf_d3d_label_offset[1];
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('How far above the dots the label floats.');
            end

            c = imgui.SliderFloat('Min Zoom', buf_d3d_text_min_scale, 0.1, 2.0, '%.1f');
            if (c) then
                changed = true;
                renderer.d3d_text_min_scale = buf_d3d_text_min_scale[1];
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Minimum font scale when far away.');
            end

            c = imgui.SliderFloat('Max Zoom', buf_d3d_text_max_scale, 1.0, 10.0, '%.1f');
            if (c) then
                changed = true;
                renderer.d3d_text_max_scale = buf_d3d_text_max_scale[1];
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Maximum font scale when close up.');
            end

            c = imgui.SliderFloat('Render Distance', buf_render_distance, 10.0, 300.0, '%.0f yalms');
            if (c) then changed = true; end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Max distance to render zone line markers.');
            end

            imgui.Spacing();
            imgui.Separator();
            imgui.TextColored({ 0.7, 0.7, 0.7, 1.0 }, 'Dots');
            imgui.Spacing();

            c = imgui.Checkbox('Glow Pulse', buf_dot_glow_enabled);
            if (c) then
                changed = true;
                renderer.dot_glow_enabled = buf_dot_glow_enabled[1];
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Enable glowing pulsating halos around dots.');
            end

            if (buf_dot_glow_enabled[1]) then
                imgui.SameLine();
                imgui.PushItemWidth(100);
                c = imgui.SliderFloat('Speed##glow', buf_dot_glow_speed, 0.5, 20.0, '%.1f');
                if (c) then
                    changed = true;
                    renderer.dot_glow_speed = buf_dot_glow_speed[1];
                end
                imgui.PopItemWidth();
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip('Pulse speed (radians/sec). Higher = faster.');
                end

                c = imgui.SliderFloat('Pulse Min', buf_dot_glow_min, 0.0, 1.0, '%.2f');
                if (c) then
                    changed = true;
                    renderer.dot_glow_min = buf_dot_glow_min[1];
                end
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip('Minimum brightness of pulse cycle (0 = fully dim).');
                end

                c = imgui.SliderFloat('Pulse Max', buf_dot_glow_max, 0.0, 1.0, '%.2f');
                if (c) then
                    changed = true;
                    renderer.dot_glow_max = buf_dot_glow_max[1];
                end
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip('Maximum brightness of pulse cycle (1 = full bright).');
                end

                c = imgui.SliderFloat('Glow Intensity', buf_dot_glow_intensity, 0.1, 2.0, '%.2f');
                if (c) then
                    changed = true;
                    renderer.dot_glow_intensity = buf_dot_glow_intensity[1];
                end
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip('Overall glow brightness multiplier.');
                end
            end

            c = imgui.SliderFloat('Dot Size', buf_dot_size, 1.0, 20.0, '%.1f');
            if (c) then changed = true; end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Size of each dot in world units.');
            end

            c = imgui.SliderFloat('Dot Glow', buf_dot_glow, 0.0, 1.0, '%.2f');
            if (c) then changed = true; end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Edge glow intensity. 0 = sharp edges, 1 = solid fill.');
            end

            c = imgui.SliderFloat('Dot Spacing', buf_dot_spacing, 0.1, 5.0, '%.1f yalms');
            if (c) then changed = true; end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Distance between dots along the zone line.');
            end

            c = imgui.SliderFloat('Hover Height', buf_hover_height, 0.0, 4.0, '%.1f yalms');
            if (c) then changed = true; end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('How far above the ground dots hover.');
            end

            c = imgui.SliderFloat('Cliff Flatten', buf_rise_distance, 0.5, 5.0, '%.1f yalms');
            if (c) then changed = true; end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Max height change per dot before flattening. Lower = flatter on slopes.');
            end

            imgui.Spacing();
            imgui.Separator();
            imgui.TextColored({ 0.7, 0.7, 0.7, 1.0 }, 'Colors');
            imgui.Spacing();

            c = imgui.ColorEdit3('Dot Color', buf_dot_color);
            if (c) then changed = true; end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Base color for all zone line dots.');
            end

            c = imgui.Checkbox('Distance Colors', buf_use_dist_colors);
            if (c) then changed = true; end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Change dot color based on distance to zone line.');
            end

            if (buf_use_dist_colors[1]) then
                c = imgui.ColorEdit3('Far (20y+)', buf_color_far);
                if (c) then changed = true; end
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip('Dot color when 20+ yalms from zone line.');
                end

                c = imgui.ColorEdit3('Mid (10-20y)', buf_color_mid);
                if (c) then changed = true; end
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip('Dot color when 10-20 yalms from zone line.');
                end

                c = imgui.ColorEdit3('Close (<10y)', buf_color_close);
                if (c) then changed = true; end
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip('Dot color when under 10 yalms from zone line.');
                end
            end

            if (changed) then
                sync_to_settings();
                ui.settings_dirty = true;
            end

            imgui.Spacing();
            imgui.Separator();
            imgui.Spacing();

            if (defaults_ref ~= nil) then
                if (imgui.Button('Reset to Defaults')) then
                    for k, v in pairs(defaults_ref) do
                        settings_ref[k] = v;
                    end
                    override_bufs = {};
                    sync_from_settings();
                    ui.settings_dirty = true;
                end
            end

            imgui.Spacing();
        end

        -- Zone lines table
        local zonelines_open = imgui.CollapsingHeader('Zone Lines', ImGuiTreeNodeFlags_DefaultOpen);
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('Zone lines in the current zone with position, size, and source.');
        end
        if (zonelines_open) then
            local zone_lines = data_ref.get_zone_lines(zone_id);

            if (#zone_lines == 0) then
                imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 },
                    'No zone lines for this zone.');
            else
                local flags = ImGuiTableFlags_Borders
                    + ImGuiTableFlags_RowBg
                    + ImGuiTableFlags_Resizable
                    + ImGuiTableFlags_ScrollY;

                if (imgui.BeginTable('##zone_lines_table', 4, flags, { 0, 220 })) then
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
                        imgui.Text(string.format('%.0f, %.0f, %.0f', zl.x, zl.y, zl.z));

                        -- Size (bounding box dimensions)
                        imgui.TableNextColumn();
                        imgui.Text(string.format('%.0fx%.0fx%.0f',
                            zl.sx or 0, zl.sy or 0, zl.sz or 0));

                        -- Source (dat + zone ID, or trig)
                        imgui.TableNextColumn();
                        if (zl.source == 'dat') then
                            local zid = zl.to_zone or 0;
                            imgui.TextColored({ 0.3, 0.7, 1.0, 1.0 }, string.format('dat%d', zid));
                        else
                            imgui.TextColored({ 0.8, 0.6, 0.2, 1.0 }, 'trig');
                        end
                    end

                    imgui.EndTable();
                end
            end

            imgui.Spacing();
        end

        -- Zone Line Overrides section (per-zone-line height, trim, flatten)
        local overrides_open = imgui.CollapsingHeader('Zone Line Overrides');
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('Per-zone-line adjustments: hide, trim, height, pole height.');
        end
        if (overrides_open) then
            imgui.Spacing();
            imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 },
                'Per-zone-line overrides. Expand an entry to adjust.');
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
                        if (imgui.IsItemHovered()) then
                            imgui.SetTooltip('Hide this zone line (e.g. door-activated zones).');
                        end

                        if (is_circle) then
                            -- Circle markers: pole height control
                            c = imgui.SliderFloat('Pole Height', bufs.pole_height, 0.0, 15.0, '%.1f yalms');
                            if (c) then changed = true; end
                            if (imgui.IsItemHovered()) then
                                imgui.SetTooltip('Vertical pole height. 0 = use default (4 yalms).');
                            end
                        else
                            -- Curtain markers: height, trim, flatten controls
                            c = imgui.SliderFloat('Height', bufs.height, -5.0, 5.0, '%.1f yalms');
                            if (c) then changed = true; end
                            if (imgui.IsItemHovered()) then
                                imgui.SetTooltip('Height offset. Positive = higher, 0 = auto terrain.');
                            end

                            c = imgui.SliderFloat('Trim', bufs.trim, 0.0, 6.0, '%.1f yalms');
                            if (c) then changed = true; end
                            if (imgui.IsItemHovered()) then
                                imgui.SetTooltip('Inset dots from each edge. Use to avoid railings/walls.');
                            end

                            c = imgui.SliderFloat('Cliff Flatten', bufs.flatten, 0.0, 5.0, '%.1f yalms');
                            if (c) then changed = true; end
                            if (imgui.IsItemHovered()) then
                                imgui.SetTooltip('Max height change per dot before flattening. 0 = use global setting.');
                            end
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
                imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 }, 'No adjustable zone lines in this zone.');
            end

            imgui.Spacing();
        end

        imgui.Spacing();
        imgui.Separator();

        -- Footer
        imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 },
            'Commands: /zl list | /zl help');
    end
    imgui.End();
end

return ui;
