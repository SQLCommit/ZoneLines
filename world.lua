-- Server-independent world data.
local P = {};

P.VANA_EPOCH = 1009810800;

-- Zone to region 0..18.
P.REGION_OF_ZONE = {
    [1]=2, [2]=2, [3]=6, [4]=6, [5]=9, [6]=9, [7]=7, [8]=7, [9]=8, [10]=8, [11]=17, [12]=17, [13]=17, [24]=18,
    [25]=18, [27]=18, [28]=18, [29]=18, [30]=18, [31]=18, [32]=18, [100]=0, [101]=0, [102]=1, [103]=1,
    [104]=2, [105]=2, [106]=3, [107]=3, [108]=1, [109]=4, [110]=4, [111]=8, [112]=9, [113]=13, [114]=12,
    [115]=5, [116]=5, [117]=6, [118]=6, [119]=7, [120]=7, [121]=11, [122]=11, [123]=14, [124]=15, [125]=12,
    [126]=10, [127]=10, [128]=13, [130]=16, [139]=0, [140]=0, [141]=0, [142]=0, [143]=3, [144]=3, [145]=5,
    [146]=5, [147]=4, [148]=4, [149]=2, [150]=2, [151]=7, [152]=7, [153]=11, [154]=11, [157]=10, [158]=10,
    [159]=15, [160]=15, [161]=9, [162]=9, [163]=15, [165]=9, [166]=8, [167]=0, [168]=12, [169]=5, [170]=5,
    [172]=3, [173]=3, [174]=13, [176]=14, [177]=16, [178]=16, [179]=10, [180]=16, [181]=16, [184]=10, [190]=0,
    [191]=3, [192]=5, [193]=1, [194]=5, [195]=2, [196]=1, [197]=4, [198]=6, [200]=7, [201]=13, [202]=11,
    [203]=8, [204]=8, [205]=15, [206]=8, [207]=15, [208]=12, [209]=12, [211]=15, [212]=13, [213]=6, [247]=12,
    [248]=1, [249]=6, [250]=14, [251]=11, [252]=14,
};

-- Owner to crest key.
P.CREST_OF_OWNER = { [1] = 'scre', [2] = 'bcre', [3] = 'wcre', [4] = 'mcre' };

-- Transport runs.
P.RUNS = {
    { zone = 50, name = 'whitegate_mhaura_boat', toau = true, door_npc = '_1es', vessel = 'ferry', label = 'Ferry to Mhaura',
      door = { -11.692, 1.69, -144.423 }, berth = { -20.726, 3.389, -154.231 },
      every = 1152, offset = 344,
      phases = { { state = 'arriving', s = 42 }, { state = 'docked', s = 191 }, { state = 'closing', s = 1 }, { state = 'departing' } } },
    { zone = 50, name = 'whitegate_nashmau_boat', toau = true, door_npc = '_1et', vessel = 'ferry', label = 'Ferry to Nashmau',
      door = { 12.066, 1.385, 144.424 }, berth = { 20.726, 3.389, 154.231 },
      every = 1152, offset = 680,
      phases = { { state = 'arriving', s = 42 }, { state = 'docked', s = 431 }, { state = 'closing', s = 1 }, { state = 'departing' } } },
    { zone = 4, name = 'manaclip_bibiki_tours', door_npc = '_04s', vessel = 'manaclipper', label = 'Manaclipper tour',
      door = { 489.593, -5.236, 707.984 }, berth = { 491.728, 0, 687.394 },
      every = 1728, offset = 2,
      phases = { { state = 'arriving', s = 41 }, { state = 'docked', s = 72 }, { state = 'closing', s = 5 }, { state = 'departing' } } },
    { zone = 4, name = 'manaclip_bibiki_purgonorgo', door_npc = '_04s', vessel = 'manaclipper', label = 'Manaclipper to Purgonorgo Isle',
      door = { 489.593, -5.236, 707.984 }, berth = { 491.728, 0, 687.394 },
      every = 1728, offset = 675,
      phases = { { state = 'arriving', s = 40 }, { state = 'docked', s = 78 }, { state = 'closing', s = 5 }, { state = 'departing' } } },
    { zone = 4, name = 'manaclip_purgonorgo_bibiki', door_npc = '_04t', vessel = 'manaclipper', label = 'Manaclipper to Sunset Docks',
      door = { -393.839, -2.784, -384.703 }, berth = { -391.373, 0, -364.2 },
      every = 1728, offset = 1203,
      phases = { { state = 'arriving', s = 51 }, { state = 'docked', s = 79 }, { state = 'closing', s = 5 }, { state = 'departing' } } },
    { zone = 2, name = 'barge_south_central', door_npc = '_02s', vessel = 'barge', label = 'Barge to Central Landing',
      door = { 232.547, -4.176, -529.924 }, berth = { 246.377, 0, -529.793 },
      every = 3456, offset = 7,
      phases = { { state = 'arriving', s = 31 }, { state = 'docked', s = 84 }, { state = 'closing', s = 7 }, { state = 'departing' } } },
    { zone = 2, name = 'barge_central_south_day', door_npc = '_02t', vessel = 'barge', label = 'Barge to South Landing',
      door = { -134.909, 0, 63.07 }, berth = { -125.042, 0, 72.786 },
      every = 3456, offset = 647,
      phases = { { state = 'arriving', s = 31 }, { state = 'docked', s = 69 }, { state = 'closing', s = 5 }, { state = 'departing' } } },
    { zone = 2, name = 'barge_south_north', door_npc = '_02s', vessel = 'barge', label = 'Barge to North Landing',
      door = { 232.547, -4.176, -529.924 }, berth = { 246.377, 0, -529.793 },
      every = 3456, offset = 1351,
      phases = { { state = 'arriving', s = 31 }, { state = 'docked', s = 84 }, { state = 'closing', s = 6 }, { state = 'departing' } } },
    { zone = 2, name = 'barge_north_central', door_npc = '_02u', vessel = 'barge', label = 'Barge to Central Landing',
      door = { -301.181, 0, 507.121 }, berth = { -291.355, 0, 516.868 },
      every = 3456, offset = 2375,
      phases = { { state = 'arriving', s = 40 }, { state = 'docked', s = 93 }, { state = 'closing', s = 6 }, { state = 'departing' } } },
    { zone = 2, name = 'barge_central_south_night', door_npc = '_02t', vessel = 'barge', label = 'Barge to South Landing',
      door = { -134.909, 0, 63.07 }, berth = { -125.042, 0, 72.786 },
      every = 3456, offset = 2759,
      phases = { { state = 'arriving', s = 31 }, { state = 'docked', s = 69 }, { state = 'closing', s = 5 }, { state = 'departing' } } },
    { zone = 250, name = 'kazham_jeuno_airship', door_npc = '_6ys', vessel = 'airship', label = 'Airship to Jeuno',
      door = { -4.068, -3.764, 16.142 }, berth = { -4, -3.497, 32.125 },
      every = 864, offset = 218,
      phases = { { state = 'arriving', s = 40 }, { state = 'docked', s = 131 }, { state = 'closing', s = 4 }, { state = 'departing' } } },
    { zone = 249, name = 'mhaura_selbina_boat', door_npc = '_6xw', vessel = 'ferry', label = 'Ferry to Selbina',
      door = { 8.322, -3.278, 1.84 }, berth = { -0.516, 0.026, -8.409 },
      every = 1152, offset = 920,
      phases = { { state = 'arriving', s = 41 }, { state = 'docked', s = 192 }, { state = 'closing', s = 1 }, { state = 'departing' } } },
    { zone = 249, name = 'mhaura_whitegate_boat', toau = true, door_npc = '_6xw', vessel = 'ferry', label = 'Ferry to Aht Urhgan',
      door = { 8.322, -3.278, 1.84 }, berth = { -0.516, 0.026, -8.409 },
      every = 1152, offset = 344,
      phases = { { state = 'arriving', s = 41 }, { state = 'docked', s = 192 }, { state = 'closing', s = 1 }, { state = 'departing' } } },
    { zone = 53, name = 'nashmau_whitegate_boat', toau = true, door_npc = '_1hs', vessel = 'ferry', label = 'Ferry to Aht Urhgan',
      door = { 12.216, 0, -104.492 }, berth = { 3.273, 3.389, -114.213 },
      every = 1152, offset = 680,
      phases = { { state = 'arriving', s = 40 }, { state = 'docked', s = 432 }, { state = 'closing', s = 2 }, { state = 'departing' } } },
    { zone = 236, name = 'bastok_jeuno_airship', door_npc = '_6ku', vessel = 'airship', label = 'Airship to Jeuno',
      door = { -36.432, 0, -60.986 }, berth = { -36.458, 6.365, -77.322 },
      every = 864, offset = 2,
      phases = { { state = 'arriving', s = 29 }, { state = 'docked', s = 143 }, { state = 'closing', s = 4 }, { state = 'departing' } } },
    { zone = 246, name = 'jeuno_kazham_airship', door_npc = '_6uv', vessel = 'airship', label = 'Airship to Kazham',
      door = { -20.906, 10.199, 116.993 }, berth = { -4, 10.45, 117 },
      every = 864, offset = 650,
      phases = { { state = 'arriving', s = 45 }, { state = 'docked', s = 118 }, { state = 'closing', s = 3 }, { state = 'departing' } } },
    { zone = 246, name = 'jeuno_sandoria_airship', door_npc = '_6us', vessel = 'airship', label = "Airship to San d'Oria",
      door = { -84.932, 10.199, 116.958 }, berth = { -68, 10.45, 117 },
      every = 864, offset = 2,
      phases = { { state = 'arriving', s = 26 }, { state = 'docked', s = 151 }, { state = 'closing', s = 3 }, { state = 'departing' } } },
    { zone = 246, name = 'jeuno_windurst_airship', door_npc = '_6uu', vessel = 'airship', label = 'Airship to Windurst',
      door = { 10.909, 10.193, -117.039 }, berth = { -6, 10.45, -117 },
      every = 864, offset = 218,
      phases = { { state = 'arriving', s = 26 }, { state = 'docked', s = 152 }, { state = 'closing', s = 2 }, { state = 'departing' } } },
    { zone = 246, name = 'jeuno_bastok_airship', door_npc = '_6ut', vessel = 'airship', label = 'Airship to Bastok',
      door = { -53.063, 10.091, -116.854 }, berth = { -70, 10.45, -117 },
      every = 864, offset = 434,
      phases = { { state = 'arriving', s = 26 }, { state = 'docked', s = 152 }, { state = 'closing', s = 2 }, { state = 'departing' } } },
    { zone = 232, name = 'sandoria_jeuno_airship', door_npc = '_6gs', vessel = 'airship', label = 'Airship to Jeuno',
      door = { -2.091, -11.349, 20.603 }, berth = { 20, -2, 44 },
      every = 864, offset = 434,
      phases = { { state = 'arriving', s = 23 }, { state = 'docked', s = 151 }, { state = 'closing', s = 4 }, { state = 'departing' } } },
    { zone = 240, name = 'windurst_jeuno_airship', door_npc = '_6os', vessel = 'airship', label = 'Airship to Jeuno',
      door = { 231.123, -1.535, 73.166 }, berth = { 242.281, -3.522, 61.994 },
      every = 864, offset = 650,
      phases = { { state = 'arriving', s = 40 }, { state = 'docked', s = 139 }, { state = 'closing', s = 4 }, { state = 'departing' } } },
    { zone = 248, name = 'selbina_mhaura_boat', door_npc = '_6ww', vessel = 'ferry', label = 'Ferry to Mhaura',
      door = { 18, -2.385, -59.554 }, berth = { 9.294, 0, -69.775 },
      every = 1152, offset = 920,
      phases = { { state = 'arriving', s = 41 }, { state = 'docked', s = 192 }, { state = 'closing', s = 1 }, { state = 'departing' } } },
};

-- Warp NPCs by zone.
P.TELEPORTERS = {
    [239] = { { npc = 'Komulili', label = 'Teleport to Port Windurst', to_zone = 240, at = { 66.758, -7.436, -43.916 } } },
    [240] = {
        { npc = 'Machu-Kuchu', label = 'Teleport to Windurst Walls', to_zone = 239, at = { -111.866, -9.000, 101.462 } },
        { npc = 'Rottata', label = 'Outpost Warp', at = { 193.111, -11.999, 215.638 } },
        { npc = 'Mumbo-Bumbo', label = 'Teleport to Windurst Woods', to_zone = 241 },   -- Horizon
    },
    [238] = { { npc = 'Tonana', label = 'Teleport to Windurst Woods', to_zone = 241, at = { -1.536, -1.500, 98.566 } } },
    [241] = {
        { npc = 'Pattsu-Yabittsu', label = 'Teleport to Windurst Waters', to_zone = 238, at = { 105.755, -4.999, -137.295 } },
        { npc = 'Polo-Colo', label = 'Teleport to Port Windurst', to_zone = 240 },   -- Horizon
    },
    [231] = { { npc = 'Jeanvirgaud', label = 'Outpost Warp', at = { 109.813, -0.199, -4.881 } } },
    [234] = { { npc = 'Conrad', label = 'Outpost Warp', at = { 94.457, 0.625, -66.161 } } },
    [237] = { { npc = 'Conrad', label = 'Outpost Warp' } },   -- Horizon
    [244] = {
        { npc = 'Ajithaam', label = 'Teleport to Whitegate', to_zone = 50, toau = true, at = { -81.184, 0.000, 161.539 } },
        { npc = 'Sprinkstix', label = 'Outpost Warp' },   -- Horizon
    },
    [245] = { { npc = 'Twinkstix', label = 'Outpost Warp' } },   -- Horizon
    [246] = { { npc = 'Burnstix', label = 'Outpost Warp' } },    -- Horizon
    [50] = { { npc = 'Kaduru-Haiduru', label = 'Warp to Jeuno or your nation', toau = true, at = { -71.041, -6.000, -71.247 } } },
    [48] = { { npc = 'Shihu-Danhu', label = 'Warp to the Jeuno area', toau = true, at = { 62.768, -0.980, -51.299 } } },
};

-- Schedule NPCs by zone.
P.TIMEKEEPERS = {
    [246] = {
        { npc = 'Avijit', runs = { 'jeuno_sandoria_airship' }, at = { -67.575, 10.999, 76.017 } },
        { npc = 'Chudigrimane', runs = { 'jeuno_sandoria_airship' }, at = { -76.868, 0.000, 8.685 } },
        { npc = 'Najib', runs = { 'jeuno_windurst_airship' }, at = { -6.433, 10.999, -76.511 } },
        { npc = 'Supiroro', runs = { 'jeuno_windurst_airship' }, at = { 11.043, 0.000, -8.897 } },
        { npc = 'Gaura', runs = { 'jeuno_bastok_airship' }, at = { -70.414, 10.999, -76.551 } },
        { npc = 'Raging Lion', runs = { 'jeuno_bastok_airship' }, at = { -77.582, 0.000, -8.466 } },
        { npc = 'Chaka Skitimah', runs = { 'jeuno_kazham_airship' }, at = { 11.849, 0.000, 8.918 } },
        { npc = 'Jaipal', runs = { 'jeuno_kazham_airship' }, at = { -5.326, 10.999, 76.629 } },
    },
    [236] = { { npc = 'Bodaway', runs = { 'bastok_jeuno_airship' }, at = { -29.579, 7.363, -54.363 } }, { npc = 'Bruno', runs = { 'bastok_jeuno_airship' }, at = { -98.028, -2.615, -10.733 } } },
    [232] = { { npc = 'Louis', runs = { 'sandoria_jeuno_airship' }, at = { -37.297, -8.000, 30.338 } }, { npc = 'Nazar', runs = { 'sandoria_jeuno_airship' }, at = { -31.922, -2.000, 44.240 } } },
    [240] = { { npc = 'Kameel', runs = { 'windurst_jeuno_airship' }, at = { 220.994, -5.834, 89.828 } }, { npc = 'Martin', runs = { 'windurst_jeuno_airship' }, at = { 202.824, -6.249, 126.393 } } },
    [250] = { { npc = 'Majjih Bakrhamab', runs = { 'kazham_jeuno_airship' }, at = { -6.129, -2.500, 15.308 } }, { npc = 'Shey Wayatih', runs = { 'kazham_jeuno_airship' }, at = { -15.614, -4.000, -21.134 } } },
    [248] = { { npc = 'Humilitie', runs = { 'selbina_mhaura_boat' }, at = { 17.979, -1.390, -58.800 } } },
    [249] = {
        { npc = 'Dieh Yamilsiah', runs = { 'mhaura_selbina_boat', 'mhaura_whitegate_boat' }, at = { 8.257, -1.364, 2.197 } },
        { npc = 'Laughing Bison', runs = { 'mhaura_selbina_boat', 'mhaura_whitegate_boat' }, at = { 51.000, -8.000, 41.700 } },
        { npc = 'Radhika', runs = { 'mhaura_selbina_boat', 'mhaura_whitegate_boat' }, at = { 34.124, -7.999, 39.629 } },
    },
    [50] = {
        { npc = 'Baya Hiramayuh', runs = { 'whitegate_mhaura_boat' }, at = { -12.082, 1.999, -143.367 } },
        { npc = 'Kuhn Tsahnpri', runs = { 'whitegate_nashmau_boat' }, at = { 12.082, 1.999, 143.392 } },
    },
    [53] = { { npc = 'Yohj Dukonlhy', runs = { 'nashmau_whitegate_boat' }, at = { 10.049, 1.999, -103.451 } } },
    [4] = {
        { npc = 'Fheli Lapatzuo', runs = { 'manaclip_bibiki_tours', 'manaclip_bibiki_purgonorgo' }, at = { 488.793, -3.003, 709.473 } },
        { npc = 'Noih Tahparawh', runs = { 'manaclip_purgonorgo_bibiki' }, at = { -392.274, -3.000, -385.541 } },
    },
    [2] = {
        { npc = 'Chuaie', runs = { 'barge_south_central', 'barge_south_north' }, at = { 231.384, -2.000, -531.830 } },
        { npc = 'Felourie', runs = { 'barge_north_central' }, at = { -300.134, -1.999, 505.016 } },
        { npc = 'Ratoulle', runs = { 'barge_central_south_day', 'barge_central_south_night' }, at = { -133.959, -2.000, 60.839 } },
    },
};

-- Ship-time signs by zone.
-- Spot: dock, arch, entrance.
P.SIGNS = {
    [246] = {
        { spot = 'arch', runs = { 'jeuno_sandoria_airship' }, at = { -80.9, 0, 11.36 }, face = { 0, -1 }, emblem = 'san' },
        { spot = 'arch', runs = { 'jeuno_kazham_airship' }, at = { 7.1, 0, 11.36 }, face = { 0, -1 }, emblem = 'kaz' },
        { spot = 'arch', runs = { 'jeuno_bastok_airship' }, at = { -81.1, 0, -12.25 }, face = { 0, 1 }, emblem = 'basu' },
        { spot = 'arch', runs = { 'jeuno_windurst_airship' }, at = { 7.1, 0, -12.25 }, face = { 0, 1 }, emblem = 'win' },
    },
    -- Airship cities.
    [236] = { { spot = 'dock', runs = { 'bastok_jeuno_airship' }, at = { -36.43, 7.71, -60.39 }, face = { 0, 1 }, emblem = 'jeuno' },
        { spot = 'entrance', runs = { 'bastok_jeuno_airship' }, at = { -101.0, -2.04, -7.9 }, face = { -1, 0 }, emblem = 'jeuno' } },
    [232] = { { spot = 'dock', runs = { 'sandoria_jeuno_airship' }, at = { 3.0, -0.8, 44.0 }, face = { -1, 0 }, emblem = 'jeuno' },   -- Berth walkway end.
        { spot = 'entrance', runs = { 'sandoria_jeuno_airship' }, at = { -36.5, -8.0, 28.0 }, face = { -1, 0 }, emblem = 'jeuno' } },
    [240] = { { spot = 'dock', runs = { 'windurst_jeuno_airship' }, at = { 230.7, -2.28, 73.59 }, face = { -0.707, 0.708 }, emblem = 'jeuno' },
        { spot = 'entrance', runs = { 'windurst_jeuno_airship' }, at = { 204.49, -6.55, 127.51 }, face = { -0.707, 0.707 }, emblem = 'jeuno' } },
    [250] = { { spot = 'dock', runs = { 'kazham_jeuno_airship' }, at = { -4.07, -2.49, 15.54 }, face = { 0, -1 }, emblem = 'jeuno' },
        { spot = 'entrance', runs = { 'kazham_jeuno_airship' }, at = { -10.0, -3.99, -22.0 }, face = { 0, -1 }, emblem = 'jeuno' } },
    -- Ferry ports.
    [248] = { { spot = 'dock', runs = { 'selbina_mhaura_boat' }, at = { 18.0, -1.39, -58.95 }, face = { 0, 1 }, emblem = 'selbina' },
        { spot = 'entrance', runs = { 'selbina_mhaura_boat' }, at = { 27.1, -2.56, -26.3 }, face = { 0, 1 }, emblem = 'selbina' } },
    [249] = { { spot = 'dock', runs = { 'mhaura_selbina_boat', 'mhaura_whitegate_boat' }, at = { 8.32, -1.36, 2.44 }, face = { 0, 1 }, swap = true,
        emblems = { mhaura_selbina_boat = 'selbina', mhaura_whitegate_boat = 'ahtu' } },
        { spot = 'entrance', runs = { 'mhaura_selbina_boat', 'mhaura_whitegate_boat' }, at = { 51.0, -8.0, 41.7 }, face = { -1, 0 }, swap = true,
        emblems = { mhaura_selbina_boat = 'selbina', mhaura_whitegate_boat = 'ahtu' } } },
    [50] = {
        { spot = 'dock', runs = { 'whitegate_mhaura_boat' }, at = { -11.69, 2.0, -143.82 }, face = { 0, 1 }, emblem = 'selbina' },
        { spot = 'dock', runs = { 'whitegate_nashmau_boat' }, at = { 12.07, 2.0, 143.82 }, face = { 0, -1 }, emblem = 'anchor' },
        { spot = 'entrance', runs = { 'whitegate_mhaura_boat' }, at = { -10.0, 0.0, -94.66 }, face = { 0, 1 }, emblem = 'selbina' },
        { spot = 'entrance', runs = { 'whitegate_nashmau_boat' }, at = { 10.0, 0.0, 94.66 }, face = { 0, -1 }, emblem = 'anchor' },
    },
    [53] = { { spot = 'dock', runs = { 'nashmau_whitegate_boat' }, at = { 12.22, 2.0, -103.89 }, face = { 0, 1 }, emblem = 'ahtu' },
        { spot = 'entrance', runs = { 'nashmau_whitegate_boat' }, at = { 10.0, 0.0, -54.66 }, face = { 0, 1 }, emblem = 'ahtu' } },
    [4] = {
        { spot = 'dock', runs = { 'manaclip_bibiki_tours' }, at = { 489.07, -3.0, 713.06 }, face = { -0.103, 0.995 }, slot = -1, emblem = 'anchor' },
        { spot = 'dock', runs = { 'manaclip_bibiki_purgonorgo' }, at = { 489.07, -3.0, 713.06 }, face = { -0.103, 0.995 }, slot = 1, emblem = 'anchor' },
        { spot = 'dock', runs = { 'manaclip_purgonorgo_bibiki' }, at = { -393.91, -3.0, -385.3 }, face = { -0.119, -0.993 }, emblem = 'anchor' },
    },
    [2] = {
        { spot = 'dock', runs = { 'barge_south_central' }, at = { 226.35, -1.8, -529.98 }, face = { -1, -0.009 }, slot = -1, emblem = 'anchor' },
        { spot = 'dock', runs = { 'barge_south_north' }, at = { 226.35, -1.8, -529.98 }, face = { -1, -0.009 }, slot = 1, emblem = 'anchor' },
        { spot = 'dock', runs = { 'barge_central_south_day', 'barge_central_south_night' }, at = { -139.33, -1.79, 58.72 }, face = { -0.713, -0.702 }, emblem = 'anchor' },
        { spot = 'dock', runs = { 'barge_north_central' }, at = { -305.58, -1.79, 502.75 }, face = { -0.71, -0.704 }, emblem = 'anchor' },
    },
};

-- Fallback tally rule.
function P.next_tally(unix)
    local d = math.floor((unix + 32400) / 86400);
    local wd = (d + 3) % 7;
    return (d + 7 - wd) * 86400 - 32400;
end

return P;
