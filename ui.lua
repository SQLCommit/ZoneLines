-- Settings window.

require 'common';

local imgui, guard = require('guard').wrap(require('imgui'));
local renderer = require 'renderer';

local ui = {};

local data_ref = nil;
local settings_ref = nil;
local defaults_ref = nil;

ui.is_open = T{ false };
ui.settings_dirty = false;
ui.overrides_changed = false;
ui.reset_pending = false;

-- Save on slider release.
local HOLD_S = 2.0;
local save_pending, last_change = false, 0;

function ui.note_change()
    save_pending = true;
    last_change = os.clock();
end

function ui.save_due()
    if (not save_pending) then return false; end
    if (imgui.IsAnyItemActive() and os.clock() - last_change < HOLD_S) then return false; end
    save_pending = false;
    return true;
end

-- Widget buffers.
local B = {
    visible = { true }, render_distance = { 0 }, dot_size = { 0 }, dot_spacing = { 0 }, dot_glow = { 0 },
    hover_height = { 0 }, rise_distance = { 0 }, d3d_text_scale = { 0 }, d3d_label_offset = { 0 },
    d3d_text_min_scale = { 0 }, d3d_text_max_scale = { 0 }, d3d_labels_fixed = { false }, d3d_show_labels = { true }, d3d_show_distance = { true },
    d3d_dist_pos_idx = { 0 }, d3d_font_idx = { 0 }, d3d_outline_width = { 0 }, d3d_bold = { true }, d3d_label_spacing = { 0 },
    dot_glow_enabled = { true }, dot_glow_speed = { 0 }, dot_glow_intensity = { 0 }, dot_glow_min = { 0 }, dot_glow_max = { 0 },
    distance_fade = { false }, distance_fade_zone = { 0 }, dot_color = { 0, 0, 0 }, use_dist_colors = { false },
    color_far = { 0, 0, 0 }, color_mid = { 0, 0, 0 }, color_close = { 0, 0, 0 }, show_zone_lines = { true }, show_travel = { true }, show_crests = { true }, show_teleporters = { true }, show_map_exits = { true }, map_times = { true }, map_zone_lines = { true }, map_portals = { true }, map_docks = { true },
    map_npcs = { true }, map_names = { true }, map_dot_size = { 5 }, map_dot_color = { 0, 0, 0 }, map_text_color = { 0, 0, 0 },
    show_keepers = { true }, keeper_route = { true }, keeper_status = { true }, keeper_clock = { true },
    keeper_countdown = { true }, keeper_distance = { true },
    show_dots = { true }, portal_markers = { true }, npc_markers = { true }, fx_wave = { true }, fx_reveal = { true }, fx_motes = { true },
};
-- Map display options.
local MAP_BOOLS = { 'map_zone_lines', 'map_portals', 'map_docks', 'map_npcs', 'map_times', 'map_names' };
local MAP_KEYS = { 'map_zone_lines', 'map_portals', 'map_docks', 'map_npcs', 'map_times', 'map_names', 'map_dot_size',
    'map_dot_color', 'map_text_color' };
local KEEPER_KEYS = { 'show_keepers', 'keeper_route', 'keeper_status', 'keeper_clock', 'keeper_countdown', 'keeper_distance' };
local FX_KEYS = { 'fx_wave', 'fx_reveal', 'fx_motes' };

-- Effect control rows.
local FX_TUNE = {
    fx_wave = { { 'fx_wave_speed', 'Speed', 'How fast the light runs along the line.', 0.25, 3, '%.2fx' },
        { 'fx_wave_depth', 'Strength', 'How much the dots dim between waves.', 0, 60, '%.0f%%' } },
    fx_reveal = { { 'fx_reveal_time', 'Duration', 'How long a line takes to light up.', 0.2, 3, '%.1f s' } },
    fx_motes = { { 'fx_motes_start', 'Start height', 'How far above the ground the motes appear. 0 starts them on the ground.', 0, 3, '%.1f yalms' },
        { 'fx_motes_range', 'Range', 'Motes show within this distance.', 10, 80, '%.0f yalms' },
        { 'fx_motes_amount', 'Amount', 'How many motes rise from each line.', 25, 200, '%.0f%%' },
        { 'fx_motes_rise', 'Rise', 'How high a mote floats before it fades.', 1, 8, '%.1f yalms' } },
};
local FX_TUNE_KEYS = {};
for _, k in ipairs(FX_KEYS) do
    for _, t in ipairs(FX_TUNE[k] or {}) do
        FX_TUNE_KEYS[#FX_TUNE_KEYS + 1] = t[1];
        B[t[1]] = { (t[4] == nil) and true or 0 };
    end
end

-- Dock sign control rows.
local SIGN_STYLES, SIGN_STYLE_NAMES = { 'window', 'none' }, 'Game window\0None\0';
local SIGN_TUNE = {
    { 'sign_style', 'Style', 'Game window: the background and border of your Window Type (Config > Window). None: just the words and banner.', 'look' },
    { 'sign_emblem', 'Nation banner', "The destination's flag on the left of the sign, where it has one." },
    { 'sign_npcs', 'Also where a sign hangs', 'Keep the times above the schedule NPCs at docks that have a sign.' },
    { 'sign_title', 'Route name', 'The destination on top, like Airship to Kazham.' },
    { 'sign_status', 'Status words', 'Words like Next airship docks or Boarding - departs.' },
    { 'sign_clock', 'Game time', "The Vana'diel time it happens, like 10:49." },
    { 'sign_countdown', 'Countdown', 'Real time left, like in 1:18.' },
    { 'sign_range', 'Range', 'Signs show within this distance.', 10, 150, '%.0f yalms' },
    { 'sign_scale', 'Sign size', 'The whole sign larger or smaller: window, banner and text together.', 50, 200, '%.0f%%' },
    { 'sign_width', 'Width', 'How wide the sign is. Long text shrinks to fit.', 2, 8, '%.1f yalms' },
    { 'sign_height', 'Hanging height', 'How high the sign hangs, from the street to its centre.', 2, 9, '%.1f yalms' },
    { 'sign_text', 'Text size', 'Size of all the writing.', 60, 150, '%.0f%%' },
    { 'sign_opacity', 'Background', 'How solid the window is; 0 leaves just the text.', 0, 100, '%.0f%%' },
    { 'sign_back', 'Readable from behind', 'Write the text on the back too, so it reads from inside the hall.' },
    { 'sign_boarding', 'Highlight boarding', 'The schedule line takes the boarding colour while the ship boards.' },
    { 'sign_title_color', 'Name colour', 'Colour of the route name.', 'color' },
    { 'sign_line_color', 'Text colour', 'Colour of the schedule line.', 'color' },
    { 'sign_board_color', 'Boarding colour', 'Colour of the schedule line while the ship boards.', 'color' },
};
local SIGN_SPEC = {};
for _, t in ipairs(SIGN_TUNE) do SIGN_SPEC[t[1]] = t; end
-- Sign rows by section.
local SIGN_ON = { 'sign_title', 'sign_status', 'sign_clock', 'sign_countdown', 'sign_emblem', 'sign_boarding' };
local SIGN_LOOK = { 'sign_style', 'sign_opacity', 'sign_title_color', 'sign_line_color', 'sign_board_color' };
local SIGN_SIZE = { 'sign_scale', 'sign_width', 'sign_text', 'sign_height' };
local SIGN_KEYS = { 'show_signs' };
B.show_signs = { true };
for _, t in ipairs(SIGN_TUNE) do
    SIGN_KEYS[#SIGN_KEYS + 1] = t[1];
    B[t[1]] = (t[4] == 'color') and { 0, 0, 0 } or { (t[4] == nil) and true or 0 };   -- Look is combo index.
end

local DIST_POS_NAMES = 'Bottom\0Top\0Left\0Right\0';
local DIST_POS_VALUES = { 'bottom', 'top', 'left', 'right' };

local function font_values()
    local l = renderer.font_list;
    if (l == nil or #l == 0) then return { 'Arial' }; end
    return l;
end

-- Cached combo string.
local font_list_seen, font_count_seen, font_str = nil, -1, '';
local function font_names()
    local l = font_values();
    if (l ~= font_list_seen or #l ~= font_count_seen) then
        font_list_seen, font_count_seen = l, #l;
        font_str = table.concat(l, '\0') .. '\0';
    end
    return font_str;
end

-- Per-line override buffers.
local override_bufs = {};

local COL_TEXT   = { 0.93, 0.91, 0.86, 1.0 };
local COL_LUME   = { 0.58, 0.90, 0.80, 1.0 };
local COL_STEEL  = { 0.44, 0.62, 1.00, 1.0 };
local COL_HEAD   = { 0.55, 0.71, 1.00, 1.0 };
local COL_SHADOW = { 0.0, 0.0, 0.0, 0.35 };
local COL_TRIG   = { 0.8, 0.6, 0.2, 1.0 };
local SEC_PAD = { 10, 8 };
local V_POS, V_SIZE, V_GAP = { 0, 0 }, { 0, 0 }, { 0, 0 };
local ITEM_W = 200;
local RESET_SIZE = { 150, 0 };
local CARD = 20 + 2 + 3;

local TABS = { { 'lines', 'Lines###zl_t1' }, { 'labels', 'Labels###zl_t2' },
    { 'ships', 'Travel###zl_t4' },
    { 'map', 'Map###zl_t6' }, { 'zone', 'This Zone###zl_t5' } };

local st = { sizes = {}, top = 0, lw = 0, klw = 0, kvw = 0, rw = 0, min_w = 0, measured = false, dirty = false,
    zone_id = 0, zone_name = '', lines = nil };

local function tw(s) return (imgui.CalcTextSize(s)); end

local function tip(text)
    if (text and imgui.IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled)) then
        imgui.BeginTooltip();
        imgui.PushTextWrapPos(imgui.GetFontSize() * 26);
        imgui.TextUnformatted(text);
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end
end

local function note(text)
    imgui.PushTextWrapPos(0);
    imgui.TextDisabled(text);
    imgui.PopTextWrapPos();
end

-- Section with shadow.
local function section(key, title, body)
    local sp = imgui.GetStyle().ItemSpacing.y;
    if (imgui.GetCursorPosY() > st.top + 0.5) then V_GAP[2] = math.max(0, 10 - 2 * sp); imgui.Dummy(V_GAP); end
    local aw = imgui.GetContentRegionAvail();
    local width = math.max(1, aw - 3);
    local x, y = imgui.GetCursorScreenPos();
    imgui.PushID(key);
    local h = st.sizes[key];
    if (h and h > 0) then
        V_POS[1], V_POS[2] = x + 3, y + 3;
        imgui.SetCursorScreenPos(V_POS);
        imgui.PushStyleColor(ImGuiCol_ChildBg, COL_SHADOW);
        V_SIZE[1], V_SIZE[2] = width, h;
        imgui.BeginChild('##shadow', V_SIZE, ImGuiChildFlags_None, bit.bor(ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoScrollbar));
        imgui.EndChild();
        imgui.PopStyleColor();
        V_POS[1], V_POS[2] = x, y;
        imgui.SetCursorScreenPos(V_POS);
    end
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, SEC_PAD);
    V_SIZE[1], V_SIZE[2] = width, 0;
    imgui.BeginChild('##section', V_SIZE, bit.bor(ImGuiChildFlags_Borders, ImGuiChildFlags_AutoResizeY, ImGuiChildFlags_AlwaysAutoResize),
        bit.bor(ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse));
    imgui.PopStyleVar();
    imgui.PushStyleColor(ImGuiCol_Text, COL_HEAD);
    imgui.SeparatorText(title);
    imgui.PopStyleColor();
    body();
    imgui.EndChild();
    local _, sh = imgui.GetItemRectSize();
    st.sizes[key] = sh;
    imgui.PopID();
end

local function rows_begin(id)
    if (not imgui.BeginTable(id, 2, ImGuiTableFlags_SizingFixedFit)) then return false; end
    imgui.TableSetupColumn('label', ImGuiTableColumnFlags_WidthFixed, st.lw);
    imgui.TableSetupColumn('control', ImGuiTableColumnFlags_WidthStretch);
    return true;
end

local function row(label, help)
    imgui.TableNextRow();
    imgui.TableNextColumn();
    imgui.AlignTextToFramePadding();
    imgui.Text(label);
    tip(help);
    imgui.TableNextColumn();
end

local function kv_begin(id)
    if (not imgui.BeginTable(id, 2, ImGuiTableFlags_SizingFixedFit)) then return false; end
    imgui.TableSetupColumn('name', ImGuiTableColumnFlags_WidthFixed, st.klw);
    imgui.TableSetupColumn('value', ImGuiTableColumnFlags_WidthStretch);
    return true;
end

-- Text cut with ellipsis.
local function fit(text, w)
    if (tw(text) <= w) then return text; end
    while (#text > 1 and tw(text .. '...') > w) do text = text:sub(1, -2); end
    return text .. '...';
end

local function kv(name, help, value, col)
    imgui.TableNextRow();
    imgui.TableNextColumn();
    imgui.TextDisabled(name);
    tip(help);
    imgui.TableNextColumn();
    local shown = fit(value, st.kvw);
    if (col) then imgui.TextColored(col, shown); else imgui.Text(shown); end
    tip(help .. ((shown ~= value) and ('\n' .. value) or ''));
end

-- Fixed-width widgets.
local function done(c) if (c) then st.dirty = true; end return c; end

local function slider(id, buf, lo, hi, fmt)
    imgui.SetNextItemWidth(ITEM_W);
    return done(imgui.SliderFloat(id, buf, lo, hi, fmt));
end

local function check(id, buf) return done(imgui.Checkbox(id, buf)); end

local function color(id, buf)
    imgui.SetNextItemWidth(ITEM_W);
    return done(imgui.ColorEdit3(id, buf));
end

local function combo(id, buf, items)
    imgui.SetNextItemWidth(ITEM_W);
    return done(imgui.Combo(id, buf, items));
end

local LABELS = { 'Schedule NPCs', 'Dot colour', 'Dot size', 'Text colour', 'Names', 'Colour', 'Colour by distance', 'Size', 'Spacing',
    'Height above ground', 'Slope smoothing', 'Soft edges', 'Pulse', 'Show within', 'Fade at the edge',
'Destination name', 'Nation crest', 'Distance', 'Font', 'Font files', 'Bold',
    'Outline', 'Height above the line', 'Smallest, far away', 'Largest, up close', 'Dot line', 'Travelling wave',
    'Draw-in reveal', 'Rising motes', 'Signs at the docks', 'Times over schedule NPCs', 'Hide',
    'What', 'NPC', 'Routes', 'Goes to', 'Position', 'Pole height', 'Reset line' };
for _, t in ipairs(SIGN_TUNE) do LABELS[#LABELS + 1] = t[2] .. '    '; end   -- indented rows
for _, l in ipairs({ 'Far, 20+ yalms', 'Mid, 10-20 yalms', 'Close, under 10', 'Speed', 'Dimmest', 'Brightest',
    'Strength', 'Fade length', 'Gap', 'Duration', 'Amount', 'Range', 'Rise', 'Start height' }) do LABELS[#LABELS + 1] = l .. '    '; end

local function measure()
    if (st.measured) then return; end
    st.measured = true;
    for _, l in ipairs(LABELS) do st.lw = math.max(st.lw, tw(l)); end
    st.lw = st.lw + 16;
    for _, l in ipairs({ 'Zone', 'Zone ID', 'Lines', 'DAT', 'Total', 'Zone lines', 'Portals', 'Travel', 'Map' }) do st.klw = math.max(st.klw, tw(l)); end
    st.klw = st.klw + 8;
    st.kvw = tw("Ru'Lude Gardens");
    st.rw = st.klw + st.kvw + CARD + 20;
    local main = math.max(st.lw + ITEM_W + 2 * SEC_PAD[1] + 30, 480);
    st.min_w = 16 + st.rw + 14 + main;
end

-- Settings <-> widget buffers

local function set3(buf, src, def)
    buf[1] = src[1] or def[1] or 0; buf[2] = src[2] or def[2] or 0; buf[3] = src[3] or def[3] or 0;
end

local function sync_from_settings()
    if (settings_ref == nil or defaults_ref == nil) then return; end
    local s, d = settings_ref, defaults_ref;
    B.render_distance[1]    = s.render_distance or d.render_distance;
    B.dot_size[1]           = s.dot_size or d.dot_size;
    B.dot_spacing[1]        = s.dot_spacing or d.dot_spacing;
    B.dot_glow[1]           = s.dot_glow or d.dot_glow;
    B.hover_height[1]       = s.hover_height or d.hover_height;
    B.rise_distance[1]      = s.rise_distance or d.rise_distance;
    B.visible[1]            = (s.visible ~= false);
    B.d3d_text_scale[1]     = s.d3d_text_scale or d.d3d_text_scale;
    B.d3d_label_offset[1]   = s.d3d_label_offset or d.d3d_label_offset;
    B.d3d_text_min_scale[1] = s.d3d_text_min_scale or d.d3d_text_min_scale;
    B.d3d_text_max_scale[1] = s.d3d_text_max_scale or d.d3d_text_max_scale;
    B.d3d_labels_fixed[1]   = (s.d3d_labels_fixed == true);
    B.d3d_show_labels[1]    = (s.d3d_show_labels ~= false);
    B.d3d_show_distance[1]  = (s.d3d_show_distance ~= false);
    local fnt = s.d3d_font_family or d.d3d_font_family;
    local fv = font_values();
    local fidx = nil;
    for i = 1, #fv do if (fv[i] == fnt) then fidx = i - 1; break; end end
    if (fidx == nil) then
        -- Keep missing saved font.
        fv[#fv + 1] = fnt;
        fidx = #fv - 1;
    end
    B.d3d_font_idx[1] = fidx;
    B.d3d_outline_width[1]  = s.d3d_outline_width or d.d3d_outline_width;
    B.d3d_bold[1]           = (s.d3d_bold ~= false);
    local dp = s.d3d_dist_position or d.d3d_dist_position;
    for i = 1, #DIST_POS_VALUES do
        if (DIST_POS_VALUES[i] == dp) then B.d3d_dist_pos_idx[1] = i - 1; break; end
    end
    B.d3d_label_spacing[1]  = s.d3d_label_spacing or d.d3d_label_spacing;
    B.dot_glow_enabled[1]   = (s.dot_glow_enabled ~= false);
    B.dot_glow_speed[1]     = s.dot_glow_speed or d.dot_glow_speed;
    B.dot_glow_intensity[1] = s.dot_glow_intensity or d.dot_glow_intensity;
    B.dot_glow_min[1]       = s.dot_glow_min or d.dot_glow_min;
    B.dot_glow_max[1]       = s.dot_glow_max or d.dot_glow_max;
    B.distance_fade[1]      = (s.distance_fade == true);
    B.distance_fade_zone[1] = (s.distance_fade_zone or d.distance_fade_zone) * 100;
    set3(B.dot_color, s.dot_color or d.dot_color, d.dot_color);
    B.use_dist_colors[1]    = (s.use_dist_colors == true);
    B.show_zone_lines[1]    = (s.show_zone_lines ~= false);
    B.show_dots[1]          = (s.show_dots ~= false);
    B.portal_markers[1]     = (s.portal_markers ~= false);
    B.npc_markers[1]        = (s.npc_markers ~= false);
    B.show_travel[1]        = (s.show_travel ~= false);
    B.show_crests[1]        = (s.show_crests ~= false);
    B.show_teleporters[1]   = (s.show_teleporters ~= false);
    B.show_map_exits[1]     = (s.show_map_exits ~= false);
    for _, k in ipairs(MAP_BOOLS) do B[k][1] = (s[k] ~= false); end
    B.map_dot_size[1]       = s.map_dot_size or d.map_dot_size;
    set3(B.map_dot_color, s.map_dot_color or d.map_dot_color, d.map_dot_color);
    set3(B.map_text_color, s.map_text_color or d.map_text_color, d.map_text_color);
    for _, k in ipairs(FX_KEYS) do B[k][1] = (s[k] ~= false); end
    for _, k in ipairs(FX_TUNE_KEYS) do
        local v = s[k];
        if (v == nil) then v = d[k]; end
        if (type(B[k][1]) == 'boolean') then B[k][1] = (v ~= false); else B[k][1] = tonumber(v) or 0; end
    end
    for _, k in ipairs(KEEPER_KEYS) do B[k][1] = (s[k] ~= false); end
    for _, k in ipairs(SIGN_KEYS) do
        local b, v = B[k], s[k];
        if (v == nil) then v = d[k]; end
        if (#b == 3) then set3(b, type(v) == 'table' and v or {}, d[k] or {});
        elseif (k == 'sign_style') then b[1] = (v == 'none') and 1 or 0;
        elseif (type(b[1]) == 'boolean') then b[1] = (v ~= false);
        else b[1] = tonumber(v) or 0; end
    end
    set3(B.color_far, s.color_far or d.color_far, d.color_far);
    set3(B.color_mid, s.color_mid or d.color_mid, d.color_mid);
    set3(B.color_close, s.color_close or d.color_close, d.color_close);
    if (s.zoneline_overrides == nil) then s.zoneline_overrides = T{}; end
end

local function sync_to_settings()
    if (settings_ref == nil) then return; end
    local s = settings_ref;
    s.render_distance    = B.render_distance[1];
    s.dot_size           = B.dot_size[1];
    s.dot_spacing        = B.dot_spacing[1];
    s.dot_glow           = B.dot_glow[1];
    s.hover_height       = B.hover_height[1];
    s.rise_distance      = B.rise_distance[1];
    s.visible            = B.visible[1];
    s.d3d_text_scale     = B.d3d_text_scale[1];
    s.d3d_label_offset   = B.d3d_label_offset[1];
    s.d3d_text_min_scale = B.d3d_text_min_scale[1];
    s.d3d_text_max_scale = B.d3d_text_max_scale[1];
    s.d3d_labels_fixed   = B.d3d_labels_fixed[1];
    s.d3d_show_labels    = B.d3d_show_labels[1];
    s.d3d_show_distance  = B.d3d_show_distance[1];
    s.d3d_dist_position  = DIST_POS_VALUES[B.d3d_dist_pos_idx[1] + 1] or 'bottom';
    s.d3d_font_family    = font_values()[B.d3d_font_idx[1] + 1] or 'Arial';
    s.d3d_outline_width  = B.d3d_outline_width[1];
    s.d3d_bold           = B.d3d_bold[1];
    s.d3d_label_spacing  = B.d3d_label_spacing[1];
    s.dot_glow_enabled   = B.dot_glow_enabled[1];
    s.dot_glow_speed     = B.dot_glow_speed[1];
    s.dot_glow_intensity = B.dot_glow_intensity[1];
    s.dot_glow_min       = B.dot_glow_min[1];
    s.dot_glow_max       = B.dot_glow_max[1];
    s.distance_fade      = B.distance_fade[1];
    s.distance_fade_zone = B.distance_fade_zone[1] / 100;
    s.use_dist_colors    = B.use_dist_colors[1];
    s.show_zone_lines    = B.show_zone_lines[1];
    s.show_dots          = B.show_dots[1];
    s.portal_markers     = B.portal_markers[1];
    s.npc_markers        = B.npc_markers[1];
    s.show_travel        = B.show_travel[1];
    s.show_crests        = B.show_crests[1];
    s.show_teleporters   = B.show_teleporters[1];
    s.show_map_exits     = B.show_map_exits[1];
    for _, k in ipairs(MAP_BOOLS) do s[k] = B[k][1]; end
    s.map_dot_size       = B.map_dot_size[1];
    s.map_dot_color      = T{ B.map_dot_color[1], B.map_dot_color[2], B.map_dot_color[3] };
    s.map_text_color     = T{ B.map_text_color[1], B.map_text_color[2], B.map_text_color[3] };
    for _, k in ipairs(FX_KEYS) do s[k] = B[k][1]; end
    for _, k in ipairs(FX_TUNE_KEYS) do s[k] = B[k][1]; end
    for _, k in ipairs(KEEPER_KEYS) do s[k] = B[k][1]; end
    for _, k in ipairs(SIGN_KEYS) do
        local b = B[k];
        if (#b == 3) then s[k] = T{ b[1], b[2], b[3] };
        elseif (k == 'sign_style') then s[k] = SIGN_STYLES[b[1] + 1] or 'window';
        else s[k] = b[1]; end
    end
    s.dot_color          = T{ B.dot_color[1], B.dot_color[2], B.dot_color[3] };
    s.color_far          = T{ B.color_far[1], B.color_far[2], B.color_far[3] };
    s.color_mid          = T{ B.color_mid[1], B.color_mid[2], B.color_mid[3] };
    s.color_close        = T{ B.color_close[1], B.color_close[2], B.color_close[3] };
end

-- Widgets into settings.
function ui.sync_settings()
    sync_to_settings();
end

function ui.init(data, s, defaults)
    data_ref = data;
    settings_ref = s;
    defaults_ref = defaults;
    sync_from_settings();
end

-- Settings changed outside the window
function ui.apply_settings(s)
    settings_ref = s;
    sync_from_settings();
    override_bufs = {};
end

-- Row under a toggle.
local SUB_IN = 14;
local function subrow(label, help)
    imgui.TableNextRow();
    imgui.TableNextColumn();
    imgui.AlignTextToFramePadding();
    imgui.Indent(SUB_IN);
    imgui.Text(label);
    imgui.Unindent(SUB_IN);
    tip(help);
    imgui.TableNextColumn();
end

-- Reset keys to defaults.
local function reset_keys(lists)
    for _, keys in ipairs(lists) do
        for _, k in ipairs(keys) do
            local v = defaults_ref[k];
            if (type(v) == 'table') then
                local copy = T{};
                for ik, iv in pairs(v) do copy[ik] = iv; end
                v = copy;
            end
            settings_ref[k] = v;
        end
    end
    sync_from_settings();
    renderer.sync(settings_ref, defaults_ref);
    data_ref.set_features(settings_ref);
    ui.settings_dirty = true;
end

-- Reset button section.
local function reset_section(key, label, help, lists)
    section(key, 'Defaults', function()
        if (imgui.Button(label, RESET_SIZE)) then reset_keys(lists); end
        tip(help);
    end);
end

-- Lines

local LINE_KEYS = { 'show_dots', 'portal_markers', 'npc_markers', 'dot_color', 'use_dist_colors', 'color_far', 'color_mid',
    'color_close', 'dot_size', 'dot_spacing', 'hover_height', 'rise_distance', 'dot_glow', 'dot_glow_enabled',
    'dot_glow_speed', 'dot_glow_min', 'dot_glow_max', 'dot_glow_intensity', 'render_distance', 'distance_fade',
    'distance_fade_zone' };

local function body_dots()
    if (not rows_begin('##dots')) then return; end
    row('Dot line', 'The dots along each zone line. Off keeps the rising motes and the labels.');
    check('##show_dots', B.show_dots);
    imgui.BeginDisabled(not B.show_dots[1]);
    row('Size', 'How big each dot is.');
    slider('##dot_size', B.dot_size, 1.0, 20.0, '%.1f');
    row('Soft edges', 'How soft each dot edge is. 0 is a sharp disc, 1 a soft glow.');
    slider('##dot_glow', B.dot_glow, 0.0, 1.0, '%.2f');
    imgui.EndDisabled();
    row('Spacing', 'Distance between dots along the line.');
    slider('##dot_spacing', B.dot_spacing, 0.1, 5.0, '%.1f yalms');
    row('Height above ground', 'How far above the ground the dots hover.');
    slider('##hover', B.hover_height, 0.0, 4.0, '%.1f yalms');
    row('Slope smoothing', 'How far a dot may rise or drop from the one before. Lower keeps the line flatter over cliffs.');
    slider('##rise', B.rise_distance, 0.5, 5.0, '%.1f yalms');
    imgui.EndTable();
end

local function body_markers()
    if (not rows_begin('##markers')) then return; end
    row('Portal markers', 'The circle and pole at portals and telepads. Off keeps the labels.');
    check('##portal_markers', B.portal_markers);
    row('NPC markers', 'The gem over warp NPCs. Off keeps the labels.');
    check('##npc_markers', B.npc_markers);
    imgui.EndTable();
end

local function body_colour()
    if (not rows_begin('##colour')) then return; end
    row('Colour', 'Colour of the dots and the motes.');
    color('##dot_color', B.dot_color);
    row('Colour by distance', 'Dots change colour as you get closer to the line.');
    check('##use_dist', B.use_dist_colors);
    imgui.BeginDisabled(not B.use_dist_colors[1]);
    subrow('Far, 20+ yalms', 'Dot colour 20 or more yalms from the line.');
    color('##far', B.color_far);
    subrow('Mid, 10-20 yalms', 'Dot colour 10 to 20 yalms from the line.');
    color('##mid', B.color_mid);
    subrow('Close, under 10', 'Dot colour under 10 yalms from the line.');
    color('##close', B.color_close);
    imgui.EndDisabled();
    imgui.EndTable();
end

local function body_range()
    if (not rows_begin('##range')) then return; end
    row('Show within', 'Lines further away than this are not drawn.');
    slider('##render_dist', B.render_distance, 10.0, 300.0, '%.0f yalms');
    row('Fade at the edge', 'Lines fade out near that distance instead of popping.');
    check('##fade_on', B.distance_fade);
    imgui.BeginDisabled(not B.distance_fade[1]);
    subrow('Fade length', 'How much of that distance the fade takes. Higher is a longer, softer fade.');
    slider('##fade_zone', B.distance_fade_zone, 5.0, 100.0, '%.0f%%');
    imgui.EndDisabled();
    imgui.EndTable();
end

-- Effect toggles and controls.
local function fx_rows(id, list)
    if (not rows_begin(id)) then return; end
    for _, e in ipairs(list) do
        local no_dots = e[4] and not B.show_dots[1];   -- Needs the dot line.
        if (no_dots) then imgui.BeginDisabled(); end
        row(e[2], e[3]);
        check('##' .. e[1], B[e[1]]);
        local knobs = e[5] or FX_TUNE[e[1]];
        if (knobs ~= nil) then
            local off = not B[e[1]][1];
            if (off) then imgui.BeginDisabled(); end
            for _, t in ipairs(knobs) do
                subrow(t[2], t[3]);
                if (t[4] == nil) then check('##' .. t[1], B[t[1]]);
                else slider('##' .. t[1], B[t[1]], t[4], t[5], t[6]); end
            end
            if (off) then imgui.EndDisabled(); end
        end
        if (no_dots) then imgui.EndDisabled(); end
    end
    imgui.EndTable();
end

local PULSE_TUNE = {
    { 'dot_glow_speed', 'Speed', 'How fast the halo breathes.', 0.5, 20.0, '%.1f' },
    { 'dot_glow_min', 'Dimmest', 'Halo brightness at its lowest. 0 fades it out completely.', 0.0, 1.0, '%.2f' },
    { 'dot_glow_max', 'Brightest', 'Halo brightness at its peak.', 0.0, 1.0, '%.2f' },
    { 'dot_glow_intensity', 'Strength', 'How strong the halo is overall.', 0.1, 2.0, '%.2f' } };

-- Effect rows.
local FX_LIST = {
    { 'dot_glow_enabled', 'Pulse', 'A halo that breathes around each dot. Needs the dot line.', true, PULSE_TUNE },
    { 'fx_wave', 'Travelling wave', 'Light runs out from the centre of the line. Needs the dot line.', true },
    { 'fx_reveal', 'Draw-in reveal', 'A line lights up from its centre when it comes into range. Needs the dot line.', true },
    { 'fx_motes', 'Rising motes', 'Sparks drift up from the line and fade. They stay with the dot line off.' } };

local function body_fx() fx_rows('##fx', FX_LIST); end

local function tab_lines()
    section('dots', 'Dots', body_dots);
    section('markers', 'Markers', body_markers);
    section('colour', 'Colour', body_colour);
    section('fx', 'Effects', body_fx);
    section('range', 'Distance', body_range);
    reset_section('lines_reset', 'Reset Lines', 'Every setting on this tab back to its first value. Other tabs are kept.',
        { LINE_KEYS, FX_KEYS, FX_TUNE_KEYS });
end

-- Labels

local LABEL_KEYS = { 'd3d_show_labels', 'show_crests', 'd3d_show_distance', 'd3d_dist_position', 'd3d_label_spacing',
    'd3d_font_family', 'd3d_bold', 'd3d_outline_width', 'd3d_text_scale', 'd3d_label_offset', 'd3d_text_min_scale',
    'd3d_text_max_scale', 'd3d_labels_fixed' };

local function body_lshow()
    if (not rows_begin('##lshow')) then return; end
    row('Destination name', 'Where the line goes, above it.');
    check('##labels', B.d3d_show_labels);
    row('Nation crest', 'The crest of the nation or beastmen that hold the region ahead, beside the name.');
    check('##show_crests', B.show_crests);
    row('Distance', 'Yalms to the line.');
    check('##distance', B.d3d_show_distance);
    imgui.BeginDisabled(not B.d3d_show_distance[1]);
    subrow('Position', 'Where the distance sits next to the name.');
    combo('##dist_pos', B.d3d_dist_pos_idx, DIST_POS_NAMES);
    subrow('Gap', 'Extra space between the name and the distance.');
    slider('##gap', B.d3d_label_spacing, 0, 20, '%.0f px');
    imgui.EndDisabled();
    imgui.EndTable();
end

local function body_ltext()
    if (not rows_begin('##ltext')) then return; end
    row('Font', 'Font of the labels.');
    combo('##font', B.d3d_font_idx, font_names());
    row('Font files', 'Picks up .ttf and .otf files added to the addon fonts folder. No install or restart needed.');
    if (imgui.Button('Rescan fonts folder')) then
        pcall(renderer.scan_fonts);
        ui.apply_settings(settings_ref);   -- keep the chosen font selected
    end
    row('Bold', 'Bold label text.');
    check('##bold', B.d3d_bold);
    row('Outline', 'Black outline around the letters.');
    slider('##outline', B.d3d_outline_width, 0, 5, '%.0f px');
    row('Size', 'Size of the label text.');
    slider('##font_size', B.d3d_text_scale, 0.3, 3.0, '%.1fx');
    imgui.EndTable();
end

local function body_lplace()
    if (not rows_begin('##lplace')) then return; end
    row('Height above the line', 'How far above the dots the label floats.');
    slider('##label_h', B.d3d_label_offset, 0.0, 5.0, '%.1f yalms');
    row('Fixed in the world', 'Labels stand still like the ship signs instead of turning with the camera. Zone line labels run along their line; others face you.');
    check('##labels_fixed', B.d3d_labels_fixed);
    imgui.BeginDisabled(B.d3d_labels_fixed[1]);
    row('Smallest, far away', 'Labels never shrink below this when you are far off. Not used when fixed.');
    slider('##min_zoom', B.d3d_text_min_scale, 0.1, 2.0, '%.1fx');
    row('Largest, up close', 'Labels never grow past this when you are close. Not used when fixed.');
    slider('##max_zoom', B.d3d_text_max_scale, 1.0, 10.0, '%.1fx');
    imgui.EndDisabled();
    imgui.EndTable();
end

local function tab_labels()
    section('lshow', 'Show', body_lshow);
    section('ltext', 'Text', body_ltext);
    section('lplace', 'Placement', body_lplace);
    reset_section('labels_reset', 'Reset Labels', 'Every setting on this tab back to its first value. Other tabs are kept.', { LABEL_KEYS });
end

-- Ship Times

-- Sign key rows.
local function sign_rows(id, keys)
    if (not rows_begin(id)) then return; end
    imgui.BeginDisabled(not B.show_signs[1]);
    for _, k in ipairs(keys) do
        local t = SIGN_SPEC[k];
        row(t[2], t[3]);
        if (t[4] == nil) then check('##' .. k, B[k]);
        elseif (t[4] == 'color') then color('##' .. k, B[k]);
        elseif (t[4] == 'look') then combo('##' .. k, B[k], SIGN_STYLE_NAMES);
        else slider('##' .. k, B[k], t[4], t[5], t[6]); end
    end
    imgui.EndDisabled();
    imgui.EndTable();
end

local function body_signs()
    if (not rows_begin('##signs')) then return; end
    row('Signs at the docks', 'A sign with the ship times hangs at every airship, ferry, barge and manaclipper dock, and outside the ticket buildings.');
    check('##show_signs', B.show_signs);
    imgui.BeginDisabled(not B.show_signs[1]);
    for _, k in ipairs({ 'sign_range', 'sign_back' }) do
        local t = SIGN_SPEC[k];
        subrow(t[2], t[3]);
        if (t[4] == nil) then check('##' .. k, B[k]); else slider('##' .. k, B[k], t[4], t[5], t[6]); end
    end
    imgui.EndDisabled();
    imgui.EndTable();
end

local function body_sign_on() sign_rows('##sign_on', SIGN_ON); end
local function body_sign_look() sign_rows('##sign_look', SIGN_LOOK); end
local function body_sign_size() sign_rows('##sign_size', SIGN_SIZE); end

local function body_keepers()
    if (not rows_begin('##keepers')) then return; end
    row('Times over schedule NPCs', 'Show the next sailing above the NPCs who announce it.');
    check('##show_keepers', B.show_keepers);
    imgui.BeginDisabled(not B.show_keepers[1]);
    subrow('Route name', 'The route on top, like Airship to Kazham.');
    check('##keeper_route', B.keeper_route);
    subrow('Status words', 'Words like Next airship docks or Boarding - departs.');
    check('##keeper_status', B.keeper_status);
    subrow('Game time', "The Vana'diel time it happens, like 10:49.");
    check('##keeper_clock', B.keeper_clock);
    subrow('Countdown', 'Real time left, like in 1:18.');
    check('##keeper_countdown', B.keeper_countdown);
    subrow('Distance', 'Yalms to the NPC.');
    check('##keeper_distance', B.keeper_distance);
    local t = SIGN_SPEC.sign_npcs;
    subrow(t[2], t[3]);
    check('##sign_npcs', B.sign_npcs);
    imgui.EndDisabled();
    imgui.EndTable();
end

local function tab_ships()
    local off = not B.show_travel[1];
    if (off) then note('Travel is off in the sidebar.'); imgui.BeginDisabled(); end
    section('signs', 'Docks', body_signs);
    section('sign_on', 'On the Sign', body_sign_on);
    section('sign_look', 'Look', body_sign_look);
    section('sign_size', 'Size', body_sign_size);
    section('keepers', 'Schedule NPCs', body_keepers);
    if (off) then imgui.EndDisabled(); end
    reset_section('ships_reset', 'Reset Travel', 'Docks, signs and NPC times back to their first look and parts. Other tabs are kept.',
        { SIGN_KEYS, KEEPER_KEYS });
end

-- Map

local function body_map_show()
    if (not rows_begin('##map_show')) then return; end
    row('Zone lines', 'Exits into the next zone.');
    check('##map_zone_lines', B.map_zone_lines);
    row('Portals', 'Windurst teleporters and Delkfutt telepads.');
    check('##map_portals', B.map_portals);
    row('Docks', 'Each ferry and airship door, with its route.');
    check('##map_docks', B.map_docks);
    row('Schedule NPCs', 'The NPCs who announce the ships.');
    check('##map_npcs', B.map_npcs);
    imgui.BeginDisabled(not B.map_npcs[1]);
    subrow('Ship times', 'Their next sailings under the name. Off leaves just the name.');
    check('##map_times', B.map_times);
    imgui.EndDisabled();
    imgui.EndTable();
end

local function body_map_look()
    if (not rows_begin('##map_look')) then return; end
    row('Dot colour', 'Colour of the dots on the map.');
    color('##map_dot_color', B.map_dot_color);
    row('Dot size', 'How big the dots are on the map.');
    slider('##map_dot_size', B.map_dot_size, 2, 12, '%.0f px');
    row('Names', 'Where each marker goes, beside its dot.');
    check('##map_names', B.map_names);
    imgui.BeginDisabled(not B.map_names[1]);
    subrow('Text colour', 'Colour of the names and times.');
    color('##map_text_color', B.map_text_color);
    imgui.EndDisabled();
    imgui.EndTable();
end

local function tab_map()
    local off = not B.show_map_exits[1];
    if (off) then note('The map is off in the sidebar.'); imgui.BeginDisabled(); end
    section('map_show', 'Show on the /map', body_map_show);
    section('map_look', 'Look', body_map_look);
    if (off) then imgui.EndDisabled(); end
    reset_section('map_reset', 'Reset Map', 'Every setting on this tab back to its first value. Other tabs are kept.', { MAP_KEYS });
end

-- This Zone

local function override_buffers(key)
    local bufs = override_bufs[key];
    if (bufs == nil) then
        local eff = data_ref.effective_override(settings_ref.zoneline_overrides, key);
        bufs = {
            height      = { eff.height or 0 },
            trim        = { eff.trim or 0 },
            flatten     = { eff.flatten or 0 },
            hide        = { eff.hide == true },
            pole_height = { eff.pole_height or 0 },
        };
        override_bufs[key] = bufs;
    end
    return bufs;
end

-- Keep values differing from built-in.
local function store_override(key, bufs)
    local want = { height = bufs.height[1], trim = bufs.trim[1], flatten = bufs.flatten[1],
        hide = bufs.hide[1], pole_height = bufs.pole_height[1] };
    local builtin = data_ref.BUILTIN_OVERRIDES[key] or {};
    local entry = T{};
    for _, f in ipairs(data_ref.OVERRIDE_FIELDS) do
        local base = builtin[f];
        if (base == nil) then base = (f == 'hide') and false or 0; end
        if (not data_ref.same_value(want[f], base)) then entry[f] = want[f]; end
    end
    settings_ref.zoneline_overrides[key] = (next(entry) ~= nil) and entry or nil;
    ui.settings_dirty = true;
    ui.overrides_changed = true;
end

local function oslider(id, buf, lo, hi)
    imgui.SetNextItemWidth(ITEM_W);
    return imgui.SliderFloat(id, buf, lo, hi, '%.1f yalms');
end

-- Marker description.
local function kind_of(zl)
    local c = zl.cat;
    if (c == 'portal') then
        if (zl.floor_label ~= nil) then return 'Telepad, floor ' .. zl.floor_label, COL_LUME; end
        return 'Teleporter NPC', COL_LUME;
    end
    if (c == 'sign') then return 'Ship-time sign', COL_LUME; end
    if (c == 'keeper') then return 'Schedule NPC', COL_LUME; end
    if (zl.source == 'dat') then return 'Exit from the game files', COL_STEEL; end
    return 'Exit added by ZoneLines', COL_TRIG;
end

local function routes_of(zl)
    if (zl.routes == nil or #zl.routes == 0) then return nil; end
    local t, seen = {}, {};
    for _, r in ipairs(zl.routes) do
        local l = r.label or r.name;
        if (not seen[l]) then seen[l] = true; t[#t + 1] = l; end
    end
    return table.concat(t, ', ');
end

local SPOT = { dock = 'Sign at the dock', arch = 'Sign on the gate arch', entrance = 'Sign at the entrance' };

-- List name for entry.
local function name_of(zl, key)
    if (zl.ui_node ~= nil) then return zl.ui_node; end
    local name = zl.display_name;
    if (name == nil or name == '') then name = 'Zone line'; end
    local r = routes_of(zl) or name;
    if (zl.cat == 'sign') then name = (SPOT[zl.spot] or 'Sign') .. ': ' .. r;
    elseif (zl.cat == 'keeper') then name = (zl.npc and ('NPC ' .. zl.npc) or 'Schedule NPC') .. ': ' .. r;
    end
    zl.ui_name, zl.ui_node = name, name .. '##' .. key;
    return zl.ui_node;
end

-- Adjust rows per kind.
local ADJ_HIDE = {
    zone = 'Hide this line, for example a door that only zones when opened.',
    portal = 'Hide this portal marker.',
    sign = 'Hide this sign.',
    keeper = 'Hide the times over this NPC.',
};
local ADJ_LIFT = { sign = 'Raise or lower this sign.', keeper = 'Raise or lower the times over this NPC.' };

local function adjustable(zl)
    return zl.rect_id ~= nil and zl.rect_id ~= 0 and zl.sx ~= nil and zl.sx > 0 and zl.sz ~= nil and zl.sz > 0;
end

-- Player position per draw.
local PX, PZ, have_pos = 0, 0, false;
local function read_player()
    have_pos = false;
    local e = GetPlayerEntity();
    if (e == nil) then return; end
    local p = e.Movement.LocalPosition;
    PX, PZ, have_pos = p.X, p.Y, true;
end

-- One marker.
local function draw_line(i, zl)
    local key = zl.key or tostring(i);
    imgui.PushID('zl_' .. key);
    local open = imgui.TreeNode(name_of(zl, key));
    if (have_pos) then
        imgui.SameLine();
        imgui.TextDisabled(string.format('%.0f yalms', math.sqrt((zl.x - PX) ^ 2 + (zl.z - PZ) ^ 2)));
    end
    if (open) then
        if (rows_begin('##line')) then
            local what, col = kind_of(zl);
            row('What', 'What kind of marker this is.');
            imgui.TextColored(col, what);
            local r = routes_of(zl);
            if (zl.npc ~= nil) then
                row('NPC', 'Who announces the ships.');
                imgui.Text(zl.npc);
            end
            if (r ~= nil) then
                row('Routes', 'The ships it shows.');
                imgui.TextWrapped(r);
            elseif (zl.to_zone ~= nil and zl.to_zone > 0 and zl.cat ~= 'zone') then
                row('Goes to', 'Where it takes you.');
                imgui.Text(zl.to_zone_name ~= nil and zl.to_zone_name ~= '' and zl.to_zone_name or tostring(zl.to_zone));
            end
            row('Position', 'Where it is in the zone.');
            imgui.TextDisabled(string.format('%.0f, %.0f, %.0f', zl.x or 0, zl.y or 0, zl.z or 0));
            local cat = zl.cat or 'zone';
            if (ADJ_HIDE[cat] and (cat ~= 'zone' or adjustable(zl))) then
                local bufs, changed = override_buffers(key), false;
                row('Hide', ADJ_HIDE[cat]);
                if (imgui.Checkbox('##hide', bufs.hide)) then changed = true; end
                local lift = ADJ_LIFT[cat] or (zl.ident == 'npc' and 'Raise or lower the marker over this NPC.') or nil;
                if (lift) then
                    row('Height', lift);
                    if (oslider('##height', bufs.height, -5.0, 5.0)) then changed = true; end
                elseif (renderer.curtain_shape(zl)) then
                    row('Height', 'Raise or lower the dots. 0 follows the ground.');
                    if (oslider('##height', bufs.height, -5.0, 5.0)) then changed = true; end
                    row('Trim', 'Pull the dots in from each end, clear of railings and walls.');
                    if (oslider('##trim', bufs.trim, 0.0, 6.0)) then changed = true; end
                    row('Slope smoothing', 'This line only. 0 uses the Lines tab value.');
                    if (oslider('##flatten', bufs.flatten, 0.0, 5.0)) then changed = true; end
                else
                    row('Pole height', 'Height of the marker pole. 0 uses the usual 4 yalms.');
                    if (oslider('##pole', bufs.pole_height, 0.0, 15.0)) then changed = true; end
                end
                row('Reset line', 'Back to the built-in values for this marker.');
                if (imgui.Button('Reset##reset_line')) then
                    settings_ref.zoneline_overrides[key] = nil;
                    override_bufs[key] = nil;
                    ui.settings_dirty = true;
                    ui.overrides_changed = true;
                end
                if (changed) then store_override(key, bufs); end
            end
            imgui.EndTable();
        end
        imgui.TreePop();
    end
    imgui.PopID();
end

-- Zone markers by kind.
local GROUPS = {
    { key = 'zl_here', title = 'Zone Lines', cats = { zone = true }, list = {}, n = 0 },
    { key = 'pt_here', title = 'Portals', cats = { portal = true }, list = {}, n = 0 },
    { key = 'tr_here', title = 'Travel', cats = { sign = true, keeper = true }, list = {}, n = 0 },
};
for _, g in ipairs(GROUPS) do g.body = function() for i, zl in ipairs(g.list) do draw_line(i, zl); end end; end
local grouped_src, grouped_n = nil, -1;
local function by_name(a, b)
    local x, y = a.ui_name or '', b.ui_name or '';
    if (x ~= y) then return x < y; end
    return (a.key or '') < (b.key or '');
end
local function regroup()
    if (st.lines == grouped_src and #st.lines == grouped_n) then return; end
    grouped_src, grouped_n = st.lines, #st.lines;
    for _, g in ipairs(GROUPS) do
        g.list = {};
        for i, zl in ipairs(st.lines) do
            if (g.cats[zl.cat or 'zone']) then name_of(zl, zl.key or tostring(i)); g.list[#g.list + 1] = zl; end
        end
        table.sort(g.list, by_name);
        g.label = string.format('%s (%d)', g.title, #g.list);
    end
end

local function counts_body()
    if (not kv_begin('##counts')) then return; end
    kv('DAT', 'Zone lines read from the game DAT files, all zones.', tostring(data_ref.dat_total or 0));
    kv('Total', 'DAT lines plus trigger lines, all zones.', tostring(data_ref.get_total_count()));
    imgui.EndTable();
end

local function tab_zone()
    note('What ZoneLines marks in the zone you are in, by kind. Open one to see what it is or to adjust it.');
    regroup();
    read_player();
    local any = false;
    for _, g in ipairs(GROUPS) do
        if (#g.list > 0) then
            any = true;
            section(g.key, g.label, g.body);
        end
    end
    if (not any) then note('Nothing is marked here. The sidebar switches may have a kind turned off.'); end
    section('counts', 'All Zones', counts_body);
end

local DRAW = { lines = tab_lines, labels = tab_labels, ships = tab_ships, map = tab_map, zone = tab_zone };

-- Sidebar

-- Quick switches.
local QUICK = {
    { 'Zone lines', 'show_zone_lines', 'Lines where you walk into the next zone.' },
    { 'Portals', 'show_teleporters', 'Windurst teleporters and Delkfutt telepads.' },
    { 'Travel', 'show_travel', 'Ship-time signs at the docks and the times over schedule NPCs. The Travel tab has each part.' },
    { 'Map', 'show_map_exits', 'Markers on the native /map for this zone. The Map tab picks which.' } };

local function body_show()
    if (not B.visible[1]) then
        imgui.TextColored(COL_TRIG, 'All hidden by /zl hide.');
        if (imgui.Button('Show Again', RESET_SIZE)) then B.visible[1] = true; st.dirty = true; end
    end
    if (not kv_begin('##show')) then return; end
    for _, q in ipairs(QUICK) do
        imgui.TableNextRow();
        imgui.TableNextColumn();
        imgui.AlignTextToFramePadding();
        imgui.Text(q[1]);
        tip(q[3]);
        imgui.TableNextColumn();
        check('##q_' .. q[2], B[q[2]]);
        tip(q[3]);
    end
    imgui.EndTable();
end

local function body_zone()
    if (not kv_begin('##zone')) then return; end
    kv('Zone', 'The zone you are in.', st.zone_name ~= '' and st.zone_name or '???', COL_LUME);
    kv('Zone ID', 'The game zone id.', tostring(st.zone_id), COL_LUME);
    regroup();
    kv('Lines', 'Zone lines drawn in this zone.', tostring(#GROUPS[1].list));
    imgui.EndTable();
end

-- Back to defaults.
local function reset_to_defaults()
    for k, v in pairs(defaults_ref) do
        if (k ~= 'zoneline_overrides' and k ~= 'conquest') then
            if (type(v) == 'table') then
                local copy = T{};
                for ik, iv in pairs(v) do copy[ik] = iv; end
                settings_ref[k] = copy;
            else
                settings_ref[k] = v;
            end
        end
    end
    sync_from_settings();
    renderer.sync(settings_ref, defaults_ref);
    data_ref.set_features(settings_ref);
    ui.settings_dirty = true;
end

local function body_reset()
    if (imgui.Button('Reset Everything', RESET_SIZE)) then reset_to_defaults(); end
    tip('Every tab back to its first values. Your per-line adjustments on This Zone are kept.');
    note('/zl help lists the commands.');
end

local function draw_sidebar()
    st.top = imgui.GetCursorPosY();
    section('show', 'Show', body_show);
    section('zone', 'Zone', body_zone);
    section('reset', 'Settings', body_reset);
end

local function draw_tabs()
    imgui.PushStyleColor(ImGuiCol_TabSelectedOverline, COL_STEEL);
    if (imgui.BeginTabBar('##tabs', bit.bor(ImGuiTabBarFlags_FittingPolicyShrink, ImGuiTabBarFlags_DrawSelectedOverline))) then
        for _, t in ipairs(TABS) do
            if (imgui.BeginTabItem(t[2])) then
                st.top = imgui.GetCursorPosY();
                DRAW[t[1]]();
                imgui.EndTabItem();
            end
        end
        imgui.EndTabBar();
    end
    imgui.PopStyleColor();
end

-- Window

local POS, SIZE, MINS, MAXS = { 100, 100 }, { 0, 600 }, { 0, 320 }, { 10000, 10000 };
local title = nil;

local function window(zone_id, zone_name)
    measure();
    st.zone_id, st.zone_name = zone_id or 0, zone_name or '';
    st.lines = data_ref.get_world_lines(st.zone_id);
    st.dirty = false;
    SIZE[1], MINS[1] = st.min_w, st.min_w;
    if (ui.reset_pending) then
        ui.reset_pending = false;
        imgui.SetNextWindowSize(SIZE, ImGuiCond_Always);
        imgui.SetNextWindowPos(POS, ImGuiCond_Always);
    end
    imgui.SetNextWindowPos(POS, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize(SIZE, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints(MINS, MAXS);
    imgui.PushStyleColor(ImGuiCol_Text, COL_TEXT);
    title = title or ('Zone Lines v' .. addon.version .. '###zonelines');
    if (imgui.Begin(title, ui.is_open, ImGuiWindowFlags_None)) then
        if (imgui.BeginTable('##layout', 2, ImGuiTableFlags_BordersInnerV)) then
            imgui.TableSetupColumn('side', ImGuiTableColumnFlags_WidthFixed, st.rw);
            imgui.TableSetupColumn('main', ImGuiTableColumnFlags_WidthStretch);
            imgui.TableNextRow();
            imgui.TableNextColumn();
            draw_sidebar();
            imgui.TableNextColumn();
            draw_tabs();
            imgui.EndTable();
        end
    end
    imgui.End();
    imgui.PopStyleColor();
    if (st.dirty) then
        sync_to_settings();
        renderer.sync(settings_ref, defaults_ref);
        ui.settings_dirty = true;
    end
end

-- Close scopes on error.
function ui.render(zone_id, zone_name)
    if (not ui.is_open[1]) then return; end
    if (data_ref == nil or settings_ref == nil) then return; end
    local ok, err = xpcall(window, debug.traceback, zone_id, zone_name);
    if (not ok) then guard.unwind(); error(err, 0); end
end

return ui;
