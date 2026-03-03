#import "HADemoDataProvider.h"
#import "HAEntity.h"
#import "HALovelaceParser.h"
#import "HAConnectionManager.h"

@interface HADemoDataProvider ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, HAEntity *> *entityStore;
@property (nonatomic, strong) HALovelaceDashboard *demoDashboard;
@property (nonatomic, strong) NSArray<NSDictionary *> *availableDashboards;
@property (nonatomic, strong) NSDictionary<NSString *, HALovelaceDashboard *> *dashboards;
@property (nonatomic, strong) NSTimer *simulationTimer;
@property (nonatomic, assign, getter=isSimulating) BOOL simulating;
@end

@implementation HADemoDataProvider

#pragma mark - Singleton

+ (instancetype)sharedProvider {
    static HADemoDataProvider *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HADemoDataProvider alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadDemoData];
    }
    return self;
}

#pragma mark - Data Loading

- (void)loadDemoData {
    [self loadDemoEntities];
    [self loadDemoDashboards];

    _availableDashboards = @[
        @{@"title": @"Home",       @"url_path": @"demo-home"},
        @{@"title": @"Monitoring", @"url_path": @"demo-monitoring"},
        @{@"title": @"Media",      @"url_path": @"demo-media"},
        @{@"title": @"Entity Showcase", @"url_path": @"demo-entities"}
    ];

    // Default dashboard is Home
    _demoDashboard = _dashboards[@"demo-home"];
}

- (void)reloadDemoData {
    [self stopSimulation];
    [self loadDemoData];
}

#pragma mark - Entity Creation Helper

- (HAEntity *)addEntityWithId:(NSString *)entityId
                        state:(NSString *)state
                   attributes:(NSDictionary *)attributes {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"entity_id"] = entityId;
    dict[@"state"] = state;
    dict[@"attributes"] = attributes ?: @{};
    dict[@"last_changed"] = @"2026-01-01T12:00:00Z";
    dict[@"last_updated"] = @"2026-01-01T12:00:00Z";
    HAEntity *entity = [[HAEntity alloc] initWithDictionary:dict];
    _entityStore[entityId] = entity;
    return entity;
}

#pragma mark - Demo Entity Population

- (void)loadDemoEntities {
    _entityStore = [NSMutableDictionary dictionary];

    // === LIGHTS ===
    [self addEntityWithId:@"light.kitchen"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Kitchen",
        @"brightness": @178,
        @"color_temp_kelvin": @2583,
        @"color_mode": @"color_temp",
        @"supported_color_modes": @[@"color_temp", @"xy"],
        @"icon": @"mdi:ceiling-light"
    }];

    [self addEntityWithId:@"light.living_room_accent"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Living Room Accent",
        @"brightness": @200,
        @"rgb_color": @[@255, @175, @96],
        @"color_mode": @"rgb",
        @"supported_color_modes": @[@"rgb"],
        @"icon": @"mdi:led-strip-variant"
    }];

    [self addEntityWithId:@"light.bedroom"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Bedroom",
        @"brightness": @50,
        @"color_mode": @"brightness",
        @"supported_color_modes": @[@"brightness"]
    }];

    [self addEntityWithId:@"light.hallway"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Hallway",
        @"supported_color_modes": @[@"brightness"]
    }];

    [self addEntityWithId:@"light.office_3"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Office",
        @"brightness": @255
    }];

    [self addEntityWithId:@"light.downstairs"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Downstairs"
    }];

    [self addEntityWithId:@"light.upstairs"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Upstairs"
    }];

    // === CLIMATE ===
    [self addEntityWithId:@"climate.living_room"
                    state:@"heat"
               attributes:@{
        @"friendly_name": @"Living Room",
        @"temperature": @21,
        @"current_temperature": @20.8,
        @"preset_mode": @"comfort",
        @"hvac_action": @"heating",
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7,
        @"max_temp": @35,
        @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"
    }];

    [self addEntityWithId:@"climate.office"
                    state:@"cool"
               attributes:@{
        @"friendly_name": @"Office",
        @"temperature": @24,
        @"current_temperature": @26.5,
        @"hvac_action": @"cooling",
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7,
        @"max_temp": @35,
        @"temperature_unit": @"\u00B0C"
    }];

    [self addEntityWithId:@"climate.bedroom"
                    state:@"auto"
               attributes:@{
        @"friendly_name": @"Bedroom",
        @"target_temp_low": @20,
        @"target_temp_high": @24,
        @"current_temperature": @22,
        @"hvac_action": @"idle",
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7,
        @"max_temp": @35,
        @"temperature_unit": @"\u00B0C"
    }];

    [self addEntityWithId:@"climate.aidoo"
                    state:@"heat"
               attributes:@{
        @"friendly_name": @"Aidoo",
        @"current_temperature": @22.0,
        @"temperature": @22.0,
        @"hvac_action": @"idle",
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"temperature_unit": @"\u00B0C"
    }];

    // === SWITCHES ===
    [self addEntityWithId:@"switch.in_meeting"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"In Meeting",
        @"icon": @"mdi:laptop-account"
    }];

    [self addEntityWithId:@"switch.driveway"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Driveway",
        @"icon": @"mdi:driveway"
    }];

    [self addEntityWithId:@"switch.decorative_lights"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Decorative Lights",
        @"icon": @"mdi:string-lights"
    }];

    // === COVERS ===
    [self addEntityWithId:@"cover.living_room_shutter"
                    state:@"open"
               attributes:@{
        @"friendly_name": @"Living Room Shutter",
        @"current_position": @100,
        @"device_class": @"shutter"
    }];

    [self addEntityWithId:@"cover.garage_door"
                    state:@"closed"
               attributes:@{
        @"friendly_name": @"Garage Door",
        @"device_class": @"garage"
    }];

    [self addEntityWithId:@"cover.office_blinds"
                    state:@"open"
               attributes:@{
        @"friendly_name": @"Office Blinds",
        @"current_position": @50,
        @"device_class": @"blind"
    }];

    // === MEDIA PLAYERS ===
    [self addEntityWithId:@"media_player.living_room_speaker"
                    state:@"playing"
               attributes:@{
        @"friendly_name": @"Living Room Speaker",
        @"media_title": @"I Wasn't Born To Follow",
        @"media_artist": @"The Byrds",
        @"media_album_name": @"The Notorious Byrd Brothers",
        @"volume_level": @0.18,
        @"is_volume_muted": @NO,
        @"media_content_type": @"music",
        @"icon": @"mdi:speaker"
    }];

    [self addEntityWithId:@"media_player.bedroom_speaker"
                    state:@"paused"
               attributes:@{
        @"friendly_name": @"Bedroom Speaker",
        @"media_title": @"Bohemian Rhapsody",
        @"media_artist": @"Queen",
        @"media_album_name": @"A Night at the Opera",
        @"volume_level": @0.5,
        @"is_volume_muted": @NO,
        @"media_content_type": @"music",
        @"icon": @"mdi:speaker"
    }];

    [self addEntityWithId:@"media_player.study_speaker"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Study Speaker",
        @"volume_level": @0.18,
        @"is_volume_muted": @NO,
        @"icon": @"mdi:speaker"
    }];

    // === SENSORS ===
    [self addEntityWithId:@"sensor.living_room_temperature"
                    state:@"22.8"
               attributes:@{
        @"friendly_name": @"Living Room Temperature",
        @"unit_of_measurement": @"\u00B0C",
        @"device_class": @"temperature",
        @"state_class": @"measurement",
        @"icon": @"mdi:thermometer"
    }];

    [self addEntityWithId:@"sensor.living_room_humidity"
                    state:@"57"
               attributes:@{
        @"friendly_name": @"Living Room Humidity",
        @"unit_of_measurement": @"%",
        @"device_class": @"humidity",
        @"state_class": @"measurement",
        @"icon": @"mdi:water-percent"
    }];

    [self addEntityWithId:@"sensor.power_consumption"
                    state:@"797.86"
               attributes:@{
        @"friendly_name": @"Power Consumption",
        @"unit_of_measurement": @"W",
        @"device_class": @"power",
        @"state_class": @"measurement",
        @"icon": @"mdi:flash"
    }];

    [self addEntityWithId:@"sensor.phone_battery"
                    state:@"78"
               attributes:@{
        @"friendly_name": @"Phone Battery",
        @"unit_of_measurement": @"%",
        @"device_class": @"battery",
        @"icon": @"mdi:battery-charging"
    }];

    [self addEntityWithId:@"sensor.office_illuminance"
                    state:@"555"
               attributes:@{
        @"friendly_name": @"Office Illuminance",
        @"unit_of_measurement": @"lx",
        @"device_class": @"illuminance",
        @"icon": @"mdi:brightness-5"
    }];

    [self addEntityWithId:@"sensor.cpu_temperature"
                    state:@"62"
               attributes:@{
        @"friendly_name": @"CPU Temperature",
        @"unit_of_measurement": @"\u00B0C",
        @"device_class": @"temperature",
        @"icon": @"mdi:thermometer"
    }];

    // === BINARY SENSORS ===
    [self addEntityWithId:@"binary_sensor.hallway_motion"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Hallway Motion",
        @"device_class": @"motion",
        @"icon": @"mdi:motion-sensor"
    }];

    [self addEntityWithId:@"binary_sensor.front_door"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Front Door",
        @"device_class": @"door",
        @"icon": @"mdi:door-closed"
    }];

    [self addEntityWithId:@"binary_sensor.kitchen_leak"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Kitchen Leak",
        @"device_class": @"moisture",
        @"icon": @"mdi:water-off"
    }];

    // === LOCKS ===
    [self addEntityWithId:@"lock.frontdoor"
                    state:@"locked"
               attributes:@{
        @"friendly_name": @"Front Door",
        @"icon": @"mdi:lock"
    }];

    [self addEntityWithId:@"lock.back_door"
                    state:@"unlocked"
               attributes:@{
        @"friendly_name": @"Back Door",
        @"icon": @"mdi:lock-open"
    }];

    [self addEntityWithId:@"lock.garage"
                    state:@"locked"
               attributes:@{
        @"friendly_name": @"Garage",
        @"icon": @"mdi:lock"
    }];

    // === ALARM ===
    [self addEntityWithId:@"alarm_control_panel.home_alarm"
                    state:@"disarmed"
               attributes:@{
        @"friendly_name": @"Home Alarm",
        @"code_arm_required": @YES,
        @"supported_features": @31,
        @"icon": @"mdi:shield-check"
    }];

    // === VACUUM ===
    [self addEntityWithId:@"vacuum.roborock"
                    state:@"docked"
               attributes:@{
        @"friendly_name": @"Roborock",
        @"battery_level": @100,
        @"status": @"Docked",
        @"icon": @"mdi:robot-vacuum"
    }];

    [self addEntityWithId:@"vacuum.saros_10"
                    state:@"docked"
               attributes:@{
        @"friendly_name": @"Ribbit",
        @"battery_level": @100,
        @"status": @"Docked"
    }];

    // === FANS ===
    [self addEntityWithId:@"fan.living_room"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Living Room Fan",
        @"percentage": @50,
        @"oscillating": @NO,
        @"preset_mode": @"normal",
        @"preset_modes": @[@"normal", @"sleep", @"nature"],
        @"percentage_step": @(100.0 / 3.0),
        @"icon": @"mdi:fan"
    }];

    [self addEntityWithId:@"fan.bedroom"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Bedroom Fan",
        @"percentage": @0,
        @"icon": @"mdi:fan-off"
    }];

    // === HUMIDIFIER ===
    [self addEntityWithId:@"humidifier.bedroom"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Bedroom Humidifier",
        @"humidity": @60,
        @"min_humidity": @30,
        @"max_humidity": @80,
        @"mode": @"normal",
        @"available_modes": @[@"normal", @"eco", @"boost"],
        @"icon": @"mdi:air-humidifier"
    }];

    // === WEATHER ===
    [self addEntityWithId:@"weather.home"
                    state:@"sunny"
               attributes:@{
        @"friendly_name": @"Home",
        @"temperature": @22,
        @"humidity": @57,
        @"pressure": @1015,
        @"wind_speed": @10,
        @"wind_bearing": @"NW",
        @"temperature_unit": @"\u00B0C",
        @"forecast": [self forecastArrayForDays:7],
        @"icon": @"mdi:weather-sunny"
    }];

    [self addEntityWithId:@"weather.office"
                    state:@"cloudy"
               attributes:@{
        @"friendly_name": @"Office",
        @"temperature": @12,
        @"humidity": @85,
        @"pressure": @1008,
        @"wind_speed": @15,
        @"wind_bearing": @"SW",
        @"temperature_unit": @"\u00B0C",
        @"icon": @"mdi:weather-cloudy"
    }];

    // === PERSON ===
    [self addEntityWithId:@"person.james"
                    state:@"home"
               attributes:@{
        @"friendly_name": @"James",
        @"icon": @"mdi:account"
    }];

    [self addEntityWithId:@"person.olivia"
                    state:@"not_home"
               attributes:@{
        @"friendly_name": @"Olivia",
        @"icon": @"mdi:account"
    }];

    // === INPUT SELECT ===
    [self addEntityWithId:@"input_select.media_source"
                    state:@"Shield"
               attributes:@{
        @"friendly_name": @"Media Source",
        @"options": @[@"AppleTV", @"FireTV", @"Shield"],
        @"icon": @"mdi:remote"
    }];

    [self addEntityWithId:@"input_select.living_room_app"
                    state:@"YouTube"
               attributes:@{
        @"friendly_name": @"Living Room App",
        @"options": @[@"PowerOff", @"YouTube", @"Netflix", @"Plex", @"AppleTV"],
        @"icon": @"mdi:application"
    }];

    // === INPUT NUMBER ===
    [self addEntityWithId:@"input_number.target_temperature"
                    state:@"18.0"
               attributes:@{
        @"friendly_name": @"Target Temperature",
        @"min": @1,
        @"max": @100,
        @"step": @1,
        @"mode": @"slider",
        @"icon": @"mdi:thermometer"
    }];

    // === INPUT BOOLEAN ===
    [self addEntityWithId:@"input_boolean.vacation_mode"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Vacation Mode",
        @"icon": @"mdi:airplane"
    }];

    // === TIMERS ===
    [self addEntityWithId:@"timer.laundry"
                    state:@"active"
               attributes:@{
        @"friendly_name": @"Laundry",
        @"duration": @"0:45:00",
        @"remaining": @"0:23:15",
        @"icon": @"mdi:timer-outline"
    }];

    [self addEntityWithId:@"timer.oven"
                    state:@"idle"
               attributes:@{
        @"friendly_name": @"Oven",
        @"duration": @"0:30:00",
        @"icon": @"mdi:timer-outline"
    }];

    // === COUNTERS ===
    [self addEntityWithId:@"counter.litterbox_visits"
                    state:@"3"
               attributes:@{
        @"friendly_name": @"Litterbox Visits",
        @"icon": @"mdi:cat",
        @"step": @1
    }];

    // === SCENES ===
    [self addEntityWithId:@"scene.movie_night"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Movie Night",
        @"icon": @"mdi:movie-open"
    }];

    [self addEntityWithId:@"scene.good_morning"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Good Morning",
        @"icon": @"mdi:weather-sunny"
    }];

    // ============================================================
    // Entity Showcase — exhaustive attribute combinations
    // ============================================================

    // ── LIGHTS (10 variants) ──────────────────────────────────
    [self addEntityWithId:@"light.sc_basic_on" state:@"on" attributes:@{
        @"friendly_name": @"Basic On", @"brightness": @204, @"color_mode": @"brightness",
        @"supported_color_modes": @[@"brightness"], @"icon": @"mdi:lightbulb"}];
    [self addEntityWithId:@"light.sc_basic_off" state:@"off" attributes:@{
        @"friendly_name": @"Basic Off", @"supported_color_modes": @[@"brightness"],
        @"icon": @"mdi:lightbulb-outline"}];
    [self addEntityWithId:@"light.sc_color_temp" state:@"on" attributes:@{
        @"friendly_name": @"Color Temp", @"brightness": @153, @"color_temp_kelvin": @3000,
        @"min_color_temp_kelvin": @2000, @"max_color_temp_kelvin": @6500,
        @"color_mode": @"color_temp", @"supported_color_modes": @[@"color_temp"],
        @"icon": @"mdi:ceiling-light"}];
    [self addEntityWithId:@"light.sc_rgb" state:@"on" attributes:@{
        @"friendly_name": @"RGB Blue", @"brightness": @255, @"hs_color": @[@240, @100],
        @"rgb_color": @[@0, @0, @255], @"color_mode": @"hs",
        @"supported_color_modes": @[@"hs"], @"icon": @"mdi:led-strip-variant"}];
    [self addEntityWithId:@"light.sc_rgbw" state:@"on" attributes:@{
        @"friendly_name": @"RGBW", @"brightness": @200, @"rgbw_color": @[@255, @0, @0, @128],
        @"color_mode": @"rgbw", @"supported_color_modes": @[@"rgbw"],
        @"icon": @"mdi:led-strip"}];
    [self addEntityWithId:@"light.sc_all_modes" state:@"on" attributes:@{
        @"friendly_name": @"All Modes", @"brightness": @191, @"color_temp_kelvin": @4000,
        @"min_color_temp_kelvin": @2000, @"max_color_temp_kelvin": @6500,
        @"color_mode": @"color_temp",
        @"supported_color_modes": @[@"brightness", @"color_temp", @"hs"],
        @"icon": @"mdi:lightbulb-multiple"}];
    [self addEntityWithId:@"light.sc_effect" state:@"on" attributes:@{
        @"friendly_name": @"With Effect", @"brightness": @255, @"effect": @"rainbow",
        @"effect_list": @[@"rainbow", @"strobe", @"colorloop", @"none"],
        @"color_mode": @"rgb", @"supported_color_modes": @[@"rgb"],
        @"icon": @"mdi:lava-lamp"}];
    [self addEntityWithId:@"light.sc_brightness_only" state:@"on" attributes:@{
        @"friendly_name": @"Brightness Only", @"brightness": @102,
        @"color_mode": @"brightness", @"supported_color_modes": @[@"brightness"],
        @"icon": @"mdi:desk-lamp"}];
    [self addEntityWithId:@"light.sc_dimmed_low" state:@"on" attributes:@{
        @"friendly_name": @"Dimmed 2%", @"brightness": @5,
        @"color_mode": @"brightness", @"supported_color_modes": @[@"brightness"],
        @"icon": @"mdi:lightbulb-on-10"}];
    [self addEntityWithId:@"light.sc_max_bright" state:@"on" attributes:@{
        @"friendly_name": @"Max Bright", @"brightness": @255,
        @"color_mode": @"brightness", @"supported_color_modes": @[@"brightness"],
        @"icon": @"mdi:lightbulb-on"}];

    // ── CLIMATE (8 variants) ──────────────────────────────────
    [self addEntityWithId:@"climate.sc_heating" state:@"heat" attributes:@{
        @"friendly_name": @"Heating", @"temperature": @22, @"current_temperature": @20,
        @"hvac_action": @"heating", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"}];
    [self addEntityWithId:@"climate.sc_cooling" state:@"cool" attributes:@{
        @"friendly_name": @"Cooling", @"temperature": @24, @"current_temperature": @26,
        @"hvac_action": @"cooling", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"}];
    [self addEntityWithId:@"climate.sc_heat_cool" state:@"heat_cool" attributes:@{
        @"friendly_name": @"Heat/Cool", @"target_temp_high": @24, @"target_temp_low": @20,
        @"current_temperature": @22, @"hvac_action": @"idle",
        @"hvac_modes": @[@"off", @"heat", @"cool", @"heat_cool"],
        @"min_temp": @7, @"max_temp": @35, @"temperature_unit": @"\u00B0C"}];
    [self addEntityWithId:@"climate.sc_presets" state:@"heat" attributes:@{
        @"friendly_name": @"With Presets", @"temperature": @22, @"current_temperature": @20.5,
        @"hvac_action": @"heating", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"preset_mode": @"eco", @"preset_modes": @[@"eco", @"comfort", @"away", @"boost", @"sleep"],
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"}];
    [self addEntityWithId:@"climate.sc_fan" state:@"cool" attributes:@{
        @"friendly_name": @"With Fan", @"temperature": @24, @"current_temperature": @26,
        @"hvac_action": @"cooling", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"fan_mode": @"medium", @"fan_modes": @[@"auto", @"low", @"medium", @"high"],
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @1,
        @"temperature_unit": @"\u00B0C"}];
    [self addEntityWithId:@"climate.sc_swing" state:@"heat" attributes:@{
        @"friendly_name": @"With Swing", @"temperature": @21, @"current_temperature": @19,
        @"hvac_action": @"heating", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"swing_mode": @"vertical",
        @"swing_modes": @[@"on", @"off", @"vertical", @"horizontal", @"both"],
        @"min_temp": @7, @"max_temp": @35, @"temperature_unit": @"\u00B0C"}];
    [self addEntityWithId:@"climate.sc_all" state:@"heat" attributes:@{
        @"friendly_name": @"All Features", @"temperature": @22, @"current_temperature": @21,
        @"hvac_action": @"heating", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto", @"dry", @"fan_only"],
        @"preset_mode": @"comfort", @"preset_modes": @[@"eco", @"comfort", @"away", @"boost"],
        @"fan_mode": @"auto", @"fan_modes": @[@"auto", @"low", @"medium", @"high"],
        @"swing_mode": @"off", @"swing_modes": @[@"on", @"off", @"vertical", @"horizontal"],
        @"aux_heat": @YES, @"target_humidity": @50,
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"}];
    [self addEntityWithId:@"climate.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Off", @"current_temperature": @18,
        @"hvac_action": @"off", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7, @"max_temp": @35, @"temperature_unit": @"\u00B0C"}];

    // ── COVERS (10 variants) ──────────────────────────────────
    [self addEntityWithId:@"cover.sc_position" state:@"open" attributes:@{
        @"friendly_name": @"Position Only", @"current_position": @50,
        @"supported_features": @15, @"device_class": @"shutter"}];
    [self addEntityWithId:@"cover.sc_tilt" state:@"open" attributes:@{
        @"friendly_name": @"Tilt Only", @"current_position": @100, @"current_tilt_position": @30,
        @"supported_features": @255, @"device_class": @"blind"}];
    [self addEntityWithId:@"cover.sc_pos_tilt" state:@"open" attributes:@{
        @"friendly_name": @"Position+Tilt", @"current_position": @75, @"current_tilt_position": @60,
        @"supported_features": @255, @"device_class": @"blind"}];
    [self addEntityWithId:@"cover.sc_no_position" state:@"open" attributes:@{
        @"friendly_name": @"No Position", @"supported_features": @3, @"device_class": @"awning"}];
    [self addEntityWithId:@"cover.sc_opening" state:@"opening" attributes:@{
        @"friendly_name": @"Opening", @"current_position": @65,
        @"supported_features": @15, @"device_class": @"shutter"}];
    [self addEntityWithId:@"cover.sc_closed" state:@"closed" attributes:@{
        @"friendly_name": @"Closed", @"current_position": @0,
        @"supported_features": @15, @"device_class": @"shutter"}];
    [self addEntityWithId:@"cover.sc_blind" state:@"open" attributes:@{
        @"friendly_name": @"Blind", @"current_position": @80, @"current_tilt_position": @45,
        @"supported_features": @255, @"device_class": @"blind"}];
    [self addEntityWithId:@"cover.sc_garage" state:@"closed" attributes:@{
        @"friendly_name": @"Garage", @"supported_features": @3, @"device_class": @"garage",
        @"icon": @"mdi:garage"}];
    [self addEntityWithId:@"cover.sc_door" state:@"closed" attributes:@{
        @"friendly_name": @"Door", @"supported_features": @3, @"device_class": @"door",
        @"icon": @"mdi:gate"}];
    [self addEntityWithId:@"cover.sc_shutter" state:@"open" attributes:@{
        @"friendly_name": @"Shutter", @"current_position": @100,
        @"supported_features": @15, @"device_class": @"shutter"}];

    // ── LOCKS (5 variants) ────────────────────────────────────
    [self addEntityWithId:@"lock.sc_locked" state:@"locked" attributes:@{
        @"friendly_name": @"Locked", @"icon": @"mdi:lock"}];
    [self addEntityWithId:@"lock.sc_unlocked" state:@"unlocked" attributes:@{
        @"friendly_name": @"Unlocked", @"icon": @"mdi:lock-open"}];
    [self addEntityWithId:@"lock.sc_jammed" state:@"jammed" attributes:@{
        @"friendly_name": @"Jammed", @"icon": @"mdi:lock-alert"}];
    [self addEntityWithId:@"lock.sc_code" state:@"locked" attributes:@{
        @"friendly_name": @"With Code", @"code_format": @"^\\d{4}$",
        @"icon": @"mdi:lock-smart"}];
    [self addEntityWithId:@"lock.sc_locking" state:@"locking" attributes:@{
        @"friendly_name": @"Locking", @"icon": @"mdi:lock-clock"}];

    // ── MEDIA PLAYERS (6 variants) ────────────────────────────
    [self addEntityWithId:@"media_player.sc_full" state:@"playing" attributes:@{
        @"friendly_name": @"Full Player", @"media_title": @"Interstellar",
        @"media_artist": @"Hans Zimmer", @"media_album_name": @"Soundtrack",
        @"media_content_type": @"music", @"entity_picture": @"/local/interstellar.jpg",
        @"source": @"Spotify", @"source_list": @[@"TV", @"Spotify", @"AirPlay", @"Bluetooth"],
        @"volume_level": @0.65, @"is_volume_muted": @NO,
        @"shuffle": @YES, @"repeat": @"all",
        @"media_duration": @240, @"media_position": @120,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];
    [self addEntityWithId:@"media_player.sc_paused" state:@"paused" attributes:@{
        @"friendly_name": @"Paused", @"media_title": @"Yesterday",
        @"media_artist": @"The Beatles", @"volume_level": @0.5, @"is_volume_muted": @NO,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];
    [self addEntityWithId:@"media_player.sc_muted" state:@"playing" attributes:@{
        @"friendly_name": @"Muted", @"media_title": @"Focus Beats",
        @"media_artist": @"Lo-Fi Radio", @"volume_level": @0.7, @"is_volume_muted": @YES,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];
    [self addEntityWithId:@"media_player.sc_idle" state:@"idle" attributes:@{
        @"friendly_name": @"Idle", @"volume_level": @0.3, @"is_volume_muted": @NO,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];
    [self addEntityWithId:@"media_player.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Off", @"volume_level": @0.5, @"is_volume_muted": @NO,
        @"supported_features": @152461, @"icon": @"mdi:speaker-off"}];
    [self addEntityWithId:@"media_player.sc_no_source" state:@"playing" attributes:@{
        @"friendly_name": @"No Source", @"media_title": @"Radio Stream",
        @"media_artist": @"BBC Radio 4", @"volume_level": @0.4, @"is_volume_muted": @NO,
        @"supported_features": @21437, @"icon": @"mdi:radio"}];

    // ── ALARM CONTROL PANEL (7 variants) ──────────────────────
    [self addEntityWithId:@"alarm_control_panel.sc_disarmed" state:@"disarmed" attributes:@{
        @"friendly_name": @"Disarmed", @"code_arm_required": @YES,
        @"code_format": @"number", @"supported_features": @31, @"icon": @"mdi:shield-check"}];
    [self addEntityWithId:@"alarm_control_panel.sc_home" state:@"armed_home" attributes:@{
        @"friendly_name": @"Armed Home", @"code_arm_required": @YES,
        @"supported_features": @31, @"icon": @"mdi:shield-home"}];
    [self addEntityWithId:@"alarm_control_panel.sc_away" state:@"armed_away" attributes:@{
        @"friendly_name": @"Armed Away", @"code_arm_required": @YES,
        @"supported_features": @31, @"icon": @"mdi:shield-lock"}];
    [self addEntityWithId:@"alarm_control_panel.sc_night" state:@"armed_night" attributes:@{
        @"friendly_name": @"Night", @"code_arm_required": @YES, @"code_format": @"number",
        @"supported_features": @31, @"icon": @"mdi:shield-moon"}];
    [self addEntityWithId:@"alarm_control_panel.sc_vacation" state:@"armed_vacation" attributes:@{
        @"friendly_name": @"Vacation", @"code_arm_required": @NO,
        @"supported_features": @31, @"icon": @"mdi:shield-airplane"}];
    [self addEntityWithId:@"alarm_control_panel.sc_triggered" state:@"triggered" attributes:@{
        @"friendly_name": @"TRIGGERED", @"code_arm_required": @YES,
        @"supported_features": @31, @"icon": @"mdi:bell-ring"}];
    [self addEntityWithId:@"alarm_control_panel.sc_no_code" state:@"disarmed" attributes:@{
        @"friendly_name": @"No Code", @"code_arm_required": @NO,
        @"supported_features": @31, @"icon": @"mdi:shield-off"}];

    // ── FANS (5 variants) ─────────────────────────────────────
    [self addEntityWithId:@"fan.sc_basic" state:@"on" attributes:@{
        @"friendly_name": @"Basic 50%", @"percentage": @50,
        @"percentage_step": @(100.0/3.0), @"icon": @"mdi:fan"}];
    [self addEntityWithId:@"fan.sc_presets" state:@"on" attributes:@{
        @"friendly_name": @"With Presets", @"percentage": @67,
        @"preset_mode": @"nature", @"preset_modes": @[@"auto", @"sleep", @"nature", @"baby"],
        @"percentage_step": @(100.0/6.0), @"icon": @"mdi:fan"}];
    [self addEntityWithId:@"fan.sc_oscillating" state:@"on" attributes:@{
        @"friendly_name": @"Oscillating", @"percentage": @75, @"oscillating": @YES,
        @"direction": @"forward", @"percentage_step": @(100.0/4.0), @"icon": @"mdi:fan"}];
    [self addEntityWithId:@"fan.sc_reverse" state:@"on" attributes:@{
        @"friendly_name": @"Reverse", @"percentage": @33, @"oscillating": @NO,
        @"direction": @"reverse", @"percentage_step": @(100.0/3.0),
        @"icon": @"mdi:ceiling-fan"}];
    [self addEntityWithId:@"fan.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Off", @"percentage": @0, @"icon": @"mdi:fan-off"}];

    // ── SENSORS (10 variants by device_class) ─────────────────
    [self addEntityWithId:@"sensor.sc_temperature" state:@"22.5" attributes:@{
        @"friendly_name": @"Temperature", @"unit_of_measurement": @"\u00B0C",
        @"device_class": @"temperature", @"state_class": @"measurement", @"icon": @"mdi:thermometer"}];
    [self addEntityWithId:@"sensor.sc_humidity" state:@"65" attributes:@{
        @"friendly_name": @"Humidity", @"unit_of_measurement": @"%",
        @"device_class": @"humidity", @"state_class": @"measurement", @"icon": @"mdi:water-percent"}];
    [self addEntityWithId:@"sensor.sc_power" state:@"1200" attributes:@{
        @"friendly_name": @"Power", @"unit_of_measurement": @"W",
        @"device_class": @"power", @"state_class": @"measurement", @"icon": @"mdi:flash"}];
    [self addEntityWithId:@"sensor.sc_energy" state:@"45.2" attributes:@{
        @"friendly_name": @"Energy", @"unit_of_measurement": @"kWh",
        @"device_class": @"energy", @"state_class": @"total_increasing", @"icon": @"mdi:lightning-bolt"}];
    [self addEntityWithId:@"sensor.sc_battery" state:@"78" attributes:@{
        @"friendly_name": @"Battery", @"unit_of_measurement": @"%",
        @"device_class": @"battery", @"icon": @"mdi:battery-70"}];
    [self addEntityWithId:@"sensor.sc_illuminance" state:@"350" attributes:@{
        @"friendly_name": @"Illuminance", @"unit_of_measurement": @"lx",
        @"device_class": @"illuminance", @"icon": @"mdi:brightness-5"}];
    [self addEntityWithId:@"sensor.sc_pressure" state:@"1013" attributes:@{
        @"friendly_name": @"Pressure", @"unit_of_measurement": @"hPa",
        @"device_class": @"pressure", @"state_class": @"measurement", @"icon": @"mdi:gauge"}];
    [self addEntityWithId:@"sensor.sc_gas" state:@"2.3" attributes:@{
        @"friendly_name": @"Gas", @"unit_of_measurement": @"m\u00B3",
        @"device_class": @"gas", @"state_class": @"total_increasing", @"icon": @"mdi:meter-gas"}];
    [self addEntityWithId:@"sensor.sc_monetary" state:@"12.50" attributes:@{
        @"friendly_name": @"Cost", @"unit_of_measurement": @"\u00A3",
        @"device_class": @"monetary", @"state_class": @"total", @"icon": @"mdi:currency-gbp"}];
    [self addEntityWithId:@"sensor.sc_text" state:@"Running" attributes:@{
        @"friendly_name": @"Status", @"icon": @"mdi:state-machine"}];

    // ── BINARY SENSORS (12 variants by device_class) ──────────
    [self addEntityWithId:@"binary_sensor.sc_door_open" state:@"on" attributes:@{
        @"friendly_name": @"Door Open", @"device_class": @"door", @"icon": @"mdi:door-open"}];
    [self addEntityWithId:@"binary_sensor.sc_door_closed" state:@"off" attributes:@{
        @"friendly_name": @"Door Closed", @"device_class": @"door", @"icon": @"mdi:door-closed"}];
    [self addEntityWithId:@"binary_sensor.sc_motion_on" state:@"on" attributes:@{
        @"friendly_name": @"Motion Detected", @"device_class": @"motion", @"icon": @"mdi:motion-sensor"}];
    [self addEntityWithId:@"binary_sensor.sc_motion_off" state:@"off" attributes:@{
        @"friendly_name": @"Motion Clear", @"device_class": @"motion", @"icon": @"mdi:motion-sensor"}];
    [self addEntityWithId:@"binary_sensor.sc_smoke" state:@"on" attributes:@{
        @"friendly_name": @"Smoke!", @"device_class": @"smoke", @"icon": @"mdi:smoke-detector-alert"}];
    [self addEntityWithId:@"binary_sensor.sc_moisture" state:@"on" attributes:@{
        @"friendly_name": @"Moisture!", @"device_class": @"moisture", @"icon": @"mdi:water-alert"}];
    [self addEntityWithId:@"binary_sensor.sc_window" state:@"on" attributes:@{
        @"friendly_name": @"Window Open", @"device_class": @"window", @"icon": @"mdi:window-open"}];
    [self addEntityWithId:@"binary_sensor.sc_occupancy" state:@"on" attributes:@{
        @"friendly_name": @"Occupied", @"device_class": @"occupancy", @"icon": @"mdi:account"}];
    [self addEntityWithId:@"binary_sensor.sc_presence" state:@"on" attributes:@{
        @"friendly_name": @"Present", @"device_class": @"presence", @"icon": @"mdi:home-account"}];
    [self addEntityWithId:@"binary_sensor.sc_battery_low" state:@"on" attributes:@{
        @"friendly_name": @"Battery Low", @"device_class": @"battery", @"icon": @"mdi:battery-alert"}];
    [self addEntityWithId:@"binary_sensor.sc_plug" state:@"on" attributes:@{
        @"friendly_name": @"Plug", @"device_class": @"plug", @"icon": @"mdi:power-plug"}];
    [self addEntityWithId:@"binary_sensor.sc_generic" state:@"on" attributes:@{
        @"friendly_name": @"Generic On", @"icon": @"mdi:check-circle"}];

    // ── VACUUMS (4 variants) ──────────────────────────────────
    [self addEntityWithId:@"vacuum.sc_docked" state:@"docked" attributes:@{
        @"friendly_name": @"Docked", @"battery_level": @80, @"status": @"Docked",
        @"icon": @"mdi:robot-vacuum"}];
    [self addEntityWithId:@"vacuum.sc_cleaning" state:@"cleaning" attributes:@{
        @"friendly_name": @"Cleaning", @"battery_level": @65, @"status": @"Cleaning",
        @"fan_speed": @"turbo", @"fan_speed_list": @[@"quiet", @"balanced", @"turbo", @"max"],
        @"icon": @"mdi:robot-vacuum"}];
    [self addEntityWithId:@"vacuum.sc_returning" state:@"returning" attributes:@{
        @"friendly_name": @"Returning", @"battery_level": @20, @"status": @"Returning to dock",
        @"icon": @"mdi:robot-vacuum"}];
    [self addEntityWithId:@"vacuum.sc_error" state:@"error" attributes:@{
        @"friendly_name": @"Error", @"battery_level": @45, @"status": @"Stuck on cable",
        @"icon": @"mdi:robot-vacuum-alert"}];

    // ── HUMIDIFIERS (3 variants) ──────────────────────────────
    [self addEntityWithId:@"humidifier.sc_on" state:@"on" attributes:@{
        @"friendly_name": @"Normal", @"humidity": @60, @"current_humidity": @45,
        @"min_humidity": @30, @"max_humidity": @80,
        @"mode": @"normal", @"available_modes": @[@"normal", @"eco", @"sleep"],
        @"icon": @"mdi:air-humidifier"}];
    [self addEntityWithId:@"humidifier.sc_eco" state:@"on" attributes:@{
        @"friendly_name": @"Eco Mode", @"humidity": @50, @"current_humidity": @42,
        @"min_humidity": @30, @"max_humidity": @80,
        @"mode": @"eco", @"available_modes": @[@"normal", @"eco", @"sleep"],
        @"icon": @"mdi:air-humidifier"}];
    [self addEntityWithId:@"humidifier.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Off", @"min_humidity": @30, @"max_humidity": @80,
        @"icon": @"mdi:air-humidifier-off"}];

    // ── WATER HEATER ──────────────────────────────────────────
    [self addEntityWithId:@"water_heater.sc" state:@"eco" attributes:@{
        @"friendly_name": @"Water Heater", @"temperature": @50, @"current_temperature": @48.5,
        @"min_temp": @30, @"max_temp": @65, @"target_temp_step": @1,
        @"operation_mode": @"eco", @"operation_list": @[@"eco", @"electric", @"performance", @"off"],
        @"icon": @"mdi:water-boiler"}];

    // ── INPUT BOOLEANS ────────────────────────────────────────
    [self addEntityWithId:@"input_boolean.sc_on" state:@"on" attributes:@{
        @"friendly_name": @"Guest Mode", @"icon": @"mdi:account-group"}];
    [self addEntityWithId:@"input_boolean.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Sleep Mode", @"icon": @"mdi:sleep"}];

    // ── INPUT NUMBER (2 modes) ────────────────────────────────
    [self addEntityWithId:@"input_number.sc_slider" state:@"42" attributes:@{
        @"friendly_name": @"Slider", @"min": @0, @"max": @100, @"step": @1,
        @"mode": @"slider", @"unit_of_measurement": @"%", @"icon": @"mdi:percent"}];
    [self addEntityWithId:@"input_number.sc_box" state:@"123.5" attributes:@{
        @"friendly_name": @"Box", @"min": @0, @"max": @1000, @"step": @0.1,
        @"mode": @"box", @"unit_of_measurement": @"W", @"icon": @"mdi:flash"}];

    // ── INPUT SELECT ──────────────────────────────────────────
    [self addEntityWithId:@"input_select.sc" state:@"Netflix" attributes:@{
        @"friendly_name": @"App", @"options": @[@"YouTube", @"Netflix", @"Plex", @"Disney+", @"BBC"],
        @"icon": @"mdi:application"}];

    // ── INPUT TEXT (2 modes) ──────────────────────────────────
    [self addEntityWithId:@"input_text.sc_text" state:@"Hello World" attributes:@{
        @"friendly_name": @"Text", @"mode": @"text", @"min": @0, @"max": @100,
        @"icon": @"mdi:form-textbox"}];
    [self addEntityWithId:@"input_text.sc_password" state:@"secret123" attributes:@{
        @"friendly_name": @"Password", @"mode": @"password", @"min": @0, @"max": @64,
        @"icon": @"mdi:form-textbox-password"}];

    // ── INPUT DATETIME (3 modes) ──────────────────────────────
    [self addEntityWithId:@"input_datetime.sc_date" state:@"2026-03-15" attributes:@{
        @"friendly_name": @"Date", @"has_date": @YES, @"has_time": @NO,
        @"year": @2026, @"month": @3, @"day": @15, @"icon": @"mdi:calendar"}];
    [self addEntityWithId:@"input_datetime.sc_time" state:@"07:30:00" attributes:@{
        @"friendly_name": @"Time", @"has_date": @NO, @"has_time": @YES,
        @"hour": @7, @"minute": @30, @"second": @0, @"icon": @"mdi:clock-outline"}];
    [self addEntityWithId:@"input_datetime.sc_both" state:@"2026-03-15 14:30:00" attributes:@{
        @"friendly_name": @"Date+Time", @"has_date": @YES, @"has_time": @YES,
        @"year": @2026, @"month": @3, @"day": @15, @"hour": @14, @"minute": @30, @"second": @0,
        @"icon": @"mdi:calendar-clock"}];

    // ── COUNTERS ──────────────────────────────────────────────
    [self addEntityWithId:@"counter.sc" state:@"5" attributes:@{
        @"friendly_name": @"Counter", @"step": @1, @"minimum": @0, @"maximum": @100,
        @"icon": @"mdi:counter"}];

    // ── TIMERS ────────────────────────────────────────────────
    [self addEntityWithId:@"timer.sc_active" state:@"active" attributes:@{
        @"friendly_name": @"Active", @"duration": @"0:05:00", @"remaining": @"0:03:22",
        @"icon": @"mdi:timer-outline"}];
    [self addEntityWithId:@"timer.sc_paused" state:@"paused" attributes:@{
        @"friendly_name": @"Paused", @"duration": @"0:30:00", @"remaining": @"0:12:45",
        @"icon": @"mdi:timer-pause"}];
    [self addEntityWithId:@"timer.sc_idle" state:@"idle" attributes:@{
        @"friendly_name": @"Idle", @"duration": @"0:10:00", @"icon": @"mdi:timer-outline"}];

    // ── MISC DOMAINS ──────────────────────────────────────────
    [self addEntityWithId:@"person.sc_home" state:@"home" attributes:@{
        @"friendly_name": @"Home", @"icon": @"mdi:account"}];
    [self addEntityWithId:@"person.sc_away" state:@"not_home" attributes:@{
        @"friendly_name": @"Away", @"icon": @"mdi:account-off"}];
    [self addEntityWithId:@"person.sc_zone" state:@"Work" attributes:@{
        @"friendly_name": @"At Zone", @"latitude": @51.507, @"longitude": @-0.127,
        @"gps_accuracy": @15, @"icon": @"mdi:account"}];
    [self addEntityWithId:@"scene.sc" state:@"off" attributes:@{
        @"friendly_name": @"Movie Night", @"icon": @"mdi:movie-open"}];
    [self addEntityWithId:@"script.sc" state:@"on" attributes:@{
        @"friendly_name": @"Bedtime", @"current": @1, @"last_triggered": @"2026-03-01T22:00:00Z",
        @"icon": @"mdi:script-text"}];
    [self addEntityWithId:@"automation.sc" state:@"on" attributes:@{
        @"friendly_name": @"Motion Lights", @"current": @0,
        @"last_triggered": @"2026-03-01T18:30:00Z", @"icon": @"mdi:robot"}];
    [self addEntityWithId:@"update.sc_available" state:@"on" attributes:@{
        @"friendly_name": @"HA Core", @"installed_version": @"2024.2.0",
        @"latest_version": @"2024.4.0", @"title": @"Home Assistant Core",
        @"release_url": @"https://www.home-assistant.io/blog/", @"icon": @"mdi:package-up"}];
    [self addEntityWithId:@"update.sc_current" state:@"off" attributes:@{
        @"friendly_name": @"Zigbee", @"installed_version": @"7.4.1",
        @"latest_version": @"7.4.1", @"title": @"Zigbee Coordinator",
        @"icon": @"mdi:package-check"}];

    // ── NEW DOMAINS (Wave 5 placeholders) ─────────────────────
    [self addEntityWithId:@"valve.sc_open" state:@"open" attributes:@{
        @"friendly_name": @"Garden Valve", @"current_position": @100, @"icon": @"mdi:valve-open"}];
    [self addEntityWithId:@"valve.sc_closed" state:@"closed" attributes:@{
        @"friendly_name": @"Pool Valve", @"current_position": @0, @"icon": @"mdi:valve-closed"}];
    [self addEntityWithId:@"lawn_mower.sc_docked" state:@"docked" attributes:@{
        @"friendly_name": @"Mower Docked", @"icon": @"mdi:robot-mower"}];
    [self addEntityWithId:@"lawn_mower.sc_mowing" state:@"mowing" attributes:@{
        @"friendly_name": @"Mowing", @"icon": @"mdi:robot-mower"}];
    [self addEntityWithId:@"remote.sc" state:@"idle" attributes:@{
        @"friendly_name": @"TV Remote", @"current_activity": @"Watch TV",
        @"activity_list": @[@"Watch TV", @"Gaming", @"Music", @"Off"], @"icon": @"mdi:remote"}];
    [self addEntityWithId:@"image.sc" state:@"2026-03-01T10:00:00Z" attributes:@{
        @"friendly_name": @"Snapshot", @"entity_picture": @"/api/image_proxy/image.sc",
        @"icon": @"mdi:image"}];
    [self addEntityWithId:@"todo.sc" state:@"3" attributes:@{
        @"friendly_name": @"Shopping List", @"icon": @"mdi:clipboard-list"}];
    [self addEntityWithId:@"event.sc" state:@"2026-03-01T15:30:00Z" attributes:@{
        @"friendly_name": @"Doorbell", @"event_type": @"button_press",
        @"device_class": @"doorbell", @"icon": @"mdi:doorbell"}];
    [self addEntityWithId:@"device_tracker.sc_home" state:@"home" attributes:@{
        @"friendly_name": @"Car", @"source_type": @"gps", @"icon": @"mdi:car"}];
    [self addEntityWithId:@"device_tracker.sc_away" state:@"not_home" attributes:@{
        @"friendly_name": @"Laptop", @"source_type": @"router", @"icon": @"mdi:laptop"}];

    // ── CAMERA ENTITIES (for card types showcase) ─────────────────
    [self addEntityWithId:@"camera.sc_streaming" state:@"streaming" attributes:@{
        @"friendly_name": @"Front Door", @"entity_picture": @"demo://camera-placeholder",
        @"is_streaming": @YES, @"icon": @"mdi:cctv",
        @"supported_features": @3}]; // TURN_ON=1 + TURN_OFF=2
    [self addEntityWithId:@"camera.sc_idle" state:@"idle" attributes:@{
        @"friendly_name": @"Backyard", @"entity_picture": @"demo://camera-placeholder",
        @"icon": @"mdi:cctv", @"supported_features": @3}];

    // ── MEDIA PLAYER WITH BUNDLED ART ─────────────────────────────
    [self addEntityWithId:@"media_player.sc_with_art" state:@"playing" attributes:@{
        @"friendly_name": @"With Art", @"media_title": @"Demo Track",
        @"media_artist": @"Demo Artist", @"media_album_name": @"Demo Album",
        @"media_content_type": @"music", @"entity_picture": @"demo://album-art",
        @"source": @"Local", @"source_list": @[@"Local", @"Bluetooth"],
        @"volume_level": @0.55, @"is_volume_muted": @NO,
        @"shuffle": @NO, @"repeat": @"off",
        @"media_duration": @180, @"media_position": @60,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];

    // ============================================================
    // Test-harness dashboard entities (for bundled demo-dashboard.json)
    // ============================================================

    // --- Lights (test-harness) ---
    [self addEntityWithId:@"light.bed_light"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Bed Light",
        @"brightness": @127,
        @"color_mode": @"brightness",
        @"supported_color_modes": @[@"brightness"]
    }];

    [self addEntityWithId:@"light.ceiling_lights"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Ceiling Lights",
        @"brightness": @255,
        @"color_temp_kelvin": @4000,
        @"color_mode": @"color_temp",
        @"supported_color_modes": @[@"color_temp", @"brightness"]
    }];

    [self addEntityWithId:@"light.kitchen_lights"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Kitchen Lights (Color)",
        @"brightness": @200,
        @"rgb_color": @[@255, @200, @150],
        @"color_mode": @"rgb",
        @"supported_color_modes": @[@"rgb", @"color_temp", @"brightness"]
    }];

    [self addEntityWithId:@"light.office_rgbw_lights"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Office RGBW",
        @"supported_color_modes": @[@"rgbw", @"color_temp", @"brightness"]
    }];

    // --- Switches (test-harness) ---
    [self addEntityWithId:@"switch.ac"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"AC",
        @"icon": @"mdi:air-conditioner"
    }];

    [self addEntityWithId:@"input_boolean.in_meeting"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"In Meeting",
        @"icon": @"mdi:laptop-account"
    }];

    // --- Fans (test-harness) ---
    [self addEntityWithId:@"fan.living_room_fan"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Living Room Fan",
        @"percentage": @67,
        @"oscillating": @YES,
        @"preset_mode": @"normal",
        @"preset_modes": @[@"normal", @"sleep", @"nature"],
        @"icon": @"mdi:fan"
    }];

    [self addEntityWithId:@"fan.ceiling_fan"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Ceiling Fan",
        @"percentage": @0,
        @"icon": @"mdi:ceiling-fan"
    }];

    // --- Climate (test-harness) ---
    [self addEntityWithId:@"climate.hvac"
                    state:@"heat"
               attributes:@{
        @"friendly_name": @"HVAC",
        @"temperature": @22,
        @"current_temperature": @20.5,
        @"hvac_action": @"heating",
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7,
        @"max_temp": @35,
        @"temperature_unit": @"\u00B0C"
    }];

    [self addEntityWithId:@"climate.ecobee"
                    state:@"auto"
               attributes:@{
        @"friendly_name": @"Ecobee",
        @"temperature": @21,
        @"current_temperature": @21.5,
        @"hvac_action": @"idle",
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7,
        @"max_temp": @35,
        @"temperature_unit": @"\u00B0C"
    }];

    [self addEntityWithId:@"climate.heatpump"
                    state:@"cool"
               attributes:@{
        @"friendly_name": @"Heat Pump",
        @"temperature": @24,
        @"current_temperature": @26,
        @"hvac_action": @"cooling",
        @"hvac_modes": @[@"off", @"heat", @"cool"],
        @"min_temp": @7,
        @"max_temp": @35,
        @"temperature_unit": @"\u00B0C"
    }];

    // --- Humidifiers (test-harness) ---
    [self addEntityWithId:@"humidifier.humidifier"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Humidifier",
        @"humidity": @55,
        @"min_humidity": @30,
        @"max_humidity": @80,
        @"icon": @"mdi:air-humidifier"
    }];

    [self addEntityWithId:@"humidifier.dehumidifier"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Dehumidifier",
        @"humidity": @40,
        @"min_humidity": @30,
        @"max_humidity": @80,
        @"icon": @"mdi:air-humidifier-off"
    }];

    // --- Weather (test-harness) ---
    [self addEntityWithId:@"weather.demo_weather_south"
                    state:@"sunny"
               attributes:@{
        @"friendly_name": @"South Weather",
        @"temperature": @28,
        @"humidity": @45,
        @"pressure": @1018,
        @"wind_speed": @8,
        @"wind_bearing": @"S",
        @"temperature_unit": @"\u00B0C",
        @"forecast": [self forecastArrayForDays:7]
    }];

    [self addEntityWithId:@"weather.demo_weather_north"
                    state:@"rainy"
               attributes:@{
        @"friendly_name": @"North Weather",
        @"temperature": @15,
        @"humidity": @78,
        @"pressure": @1005,
        @"wind_speed": @22,
        @"wind_bearing": @"NW",
        @"temperature_unit": @"\u00B0C",
        @"forecast": [self forecastArrayForDays:7]
    }];

    // --- Sensors (test-harness) ---
    [self addEntityWithId:@"sensor.outside_temperature"
                    state:@"18.5"
               attributes:@{
        @"friendly_name": @"Outside Temperature",
        @"unit_of_measurement": @"\u00B0C",
        @"device_class": @"temperature",
        @"state_class": @"measurement"
    }];

    [self addEntityWithId:@"sensor.outside_humidity"
                    state:@"62"
               attributes:@{
        @"friendly_name": @"Outside Humidity",
        @"unit_of_measurement": @"%",
        @"device_class": @"humidity",
        @"state_class": @"measurement"
    }];

    [self addEntityWithId:@"sensor.carbon_dioxide"
                    state:@"520"
               attributes:@{
        @"friendly_name": @"CO2",
        @"unit_of_measurement": @"ppm",
        @"device_class": @"carbon_dioxide",
        @"state_class": @"measurement"
    }];

    [self addEntityWithId:@"sensor.carbon_monoxide"
                    state:@"0"
               attributes:@{
        @"friendly_name": @"CO",
        @"unit_of_measurement": @"ppm",
        @"device_class": @"carbon_monoxide",
        @"state_class": @"measurement"
    }];

    // --- Counters (test-harness) ---
    [self addEntityWithId:@"counter.page_views"
                    state:@"1247"
               attributes:@{
        @"friendly_name": @"Page Views",
        @"icon": @"mdi:counter",
        @"step": @1
    }];

    // --- Locks (test-harness) ---
    [self addEntityWithId:@"lock.front_door"
                    state:@"locked"
               attributes:@{
        @"friendly_name": @"Front Door",
        @"icon": @"mdi:lock"
    }];

    [self addEntityWithId:@"lock.kitchen_door"
                    state:@"unlocked"
               attributes:@{
        @"friendly_name": @"Kitchen Door",
        @"icon": @"mdi:lock-open"
    }];

    [self addEntityWithId:@"lock.poorly_installed_door"
                    state:@"jammed"
               attributes:@{
        @"friendly_name": @"Jammed Lock",
        @"icon": @"mdi:lock-alert"
    }];

    // --- Alarm (test-harness) ---
    [self addEntityWithId:@"alarm_control_panel.security"
                    state:@"armed_home"
               attributes:@{
        @"friendly_name": @"Security System",
        @"code_arm_required": @YES,
        @"code_format": @"number",
        @"supported_features": @31
    }];

    // --- Covers (test-harness) ---
    [self addEntityWithId:@"cover.kitchen_window"
                    state:@"open"
               attributes:@{
        @"friendly_name": @"Kitchen Window",
        @"current_position": @100,
        @"device_class": @"blind"
    }];

    [self addEntityWithId:@"cover.hall_window"
                    state:@"closed"
               attributes:@{
        @"friendly_name": @"Hall Window",
        @"current_position": @0,
        @"device_class": @"blind"
    }];

    [self addEntityWithId:@"cover.living_room_window"
                    state:@"open"
               attributes:@{
        @"friendly_name": @"Living Room Window",
        @"current_position": @75,
        @"device_class": @"shade"
    }];

    // --- Media Players (test-harness) ---
    [self addEntityWithId:@"media_player.living_room"
                    state:@"playing"
               attributes:@{
        @"friendly_name": @"Living Room",
        @"media_title": @"Hotel California",
        @"media_artist": @"Eagles",
        @"volume_level": @0.35,
        @"is_volume_muted": @NO,
        @"media_content_type": @"music"
    }];

    [self addEntityWithId:@"media_player.bedroom"
                    state:@"paused"
               attributes:@{
        @"friendly_name": @"Bedroom",
        @"media_title": @"Yesterday",
        @"media_artist": @"The Beatles",
        @"volume_level": @0.25,
        @"is_volume_muted": @NO,
        @"media_content_type": @"music"
    }];

    [self addEntityWithId:@"media_player.lounge_room"
                    state:@"idle"
               attributes:@{
        @"friendly_name": @"Lounge Room",
        @"volume_level": @0.5,
        @"is_volume_muted": @NO
    }];

    // --- Vacuums (test-harness) ---
    [self addEntityWithId:@"vacuum.demo_vacuum_0_ground_floor"
                    state:@"cleaning"
               attributes:@{
        @"friendly_name": @"Ground Floor",
        @"battery_level": @78,
        @"status": @"Cleaning",
        @"icon": @"mdi:robot-vacuum"
    }];

    [self addEntityWithId:@"vacuum.demo_vacuum_1_first_floor"
                    state:@"docked"
               attributes:@{
        @"friendly_name": @"First Floor",
        @"battery_level": @100,
        @"status": @"Docked",
        @"icon": @"mdi:robot-vacuum"
    }];

    // --- Input Numbers (test-harness) ---
    [self addEntityWithId:@"input_number.standing_desk_height"
                    state:@"72.0"
               attributes:@{
        @"friendly_name": @"Desk Height",
        @"min": @60,
        @"max": @120,
        @"step": @1,
        @"mode": @"slider",
        @"unit_of_measurement": @"cm",
        @"icon": @"mdi:desk"
    }];

    // --- Input Text (test-harness) ---
    [self addEntityWithId:@"input_text.notes"
                    state:@"Remember to buy groceries"
               attributes:@{
        @"friendly_name": @"Notes",
        @"mode": @"text",
        @"min": @0,
        @"max": @255,
        @"icon": @"mdi:note-text"
    }];

    // --- Input Datetime (test-harness) ---
    [self addEntityWithId:@"input_datetime.vacation_start"
                    state:@"2026-03-15"
               attributes:@{
        @"friendly_name": @"Vacation Start",
        @"has_date": @YES,
        @"has_time": @NO,
        @"year": @2026,
        @"month": @3,
        @"day": @15,
        @"icon": @"mdi:calendar"
    }];

    [self addEntityWithId:@"input_datetime.appointment"
                    state:@"2026-02-20 14:30:00"
               attributes:@{
        @"friendly_name": @"Appointment",
        @"has_date": @YES,
        @"has_time": @YES,
        @"year": @2026,
        @"month": @2,
        @"day": @20,
        @"hour": @14,
        @"minute": @30,
        @"second": @0,
        @"icon": @"mdi:calendar-clock"
    }];

    // === INPUT TEXT ===
    [self addEntityWithId:@"input_text.greeting"
                    state:@"Hello World"
               attributes:@{
        @"friendly_name": @"Greeting",
        @"mode": @"text",
        @"min": @0,
        @"max": @100,
        @"icon": @"mdi:form-textbox"
    }];

    // === INPUT DATETIME ===
    [self addEntityWithId:@"input_datetime.morning_alarm"
                    state:@"07:30:00"
               attributes:@{
        @"friendly_name": @"Morning Alarm",
        @"has_date": @NO,
        @"has_time": @YES,
        @"hour": @7,
        @"minute": @30,
        @"second": @0,
        @"icon": @"mdi:clock-outline"
    }];

    // === UPDATE ===
    [self addEntityWithId:@"update.home_assistant_core"
                    state:@"on"
               attributes:@{
        @"friendly_name": @"Home Assistant Core",
        @"installed_version": @"2024.2.0",
        @"latest_version": @"2024.4.0",
        @"title": @"Home Assistant Core",
        @"release_url": @"https://www.home-assistant.io/blog/",
        @"icon": @"mdi:package-up"
    }];

    // === BUTTON ===
    [self addEntityWithId:@"button.restart"
                    state:@"off"
               attributes:@{
        @"friendly_name": @"Restart",
        @"icon": @"mdi:restart"
    }];
}

#pragma mark - Weather Forecast Helper

- (NSArray *)forecastArrayForDays:(NSInteger)days {
    NSMutableArray *forecast = [NSMutableArray arrayWithCapacity:days];
    NSArray *conditions = @[@"sunny", @"partlycloudy", @"cloudy", @"rainy",
                            @"sunny", @"lightning-rainy", @"snowy", @"partlycloudy", @"windy"];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today = [NSDate date];

    for (NSInteger i = 0; i < days; i++) {
        NSDate *date = [cal dateByAddingUnit:NSCalendarUnitDay value:i + 1 toDate:today options:0];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
        fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

        NSInteger highTemp = 10 + (i * 3) % 15;
        NSInteger lowTemp  = highTemp - 5 - (i % 3);
        double precip      = (i % 3 == 0) ? 0.0 : (double)(i * 2 % 7);

        NSString *condition = conditions[i % (NSInteger)conditions.count];

        [forecast addObject:@{
            @"datetime": [fmt stringFromDate:date],
            @"temperature": @(highTemp),
            @"templow": @(lowTemp),
            @"condition": condition,
            @"precipitation": @(precip),
            @"precipitation_probability": @((i * 13) % 100),
            @"wind_speed": @(5 + (i * 4) % 20)
        }];
    }
    return [forecast copy];
}

#pragma mark - Dashboard Loading

- (void)loadDemoDashboards {
    NSMutableDictionary *dashMap = [NSMutableDictionary dictionary];

    dashMap[@"demo-home"]       = [self createHomeDashboard];
    dashMap[@"demo-monitoring"] = [self createMonitoringDashboard];
    dashMap[@"demo-media"]      = [self createMediaDashboard];
    dashMap[@"demo-entities"]   = [self createEntityShowcaseDashboard];

    _dashboards = [dashMap copy];
    NSLog(@"[HADemo] Created %lu demo dashboards", (unsigned long)_dashboards.count);
}

- (HALovelaceDashboard *)dashboardForPath:(NSString *)urlPath {
    HALovelaceDashboard *dash = _dashboards[urlPath];
    return dash ?: _dashboards[@"demo-home"];
}

#pragma mark - Dashboard Builders

- (HALovelaceDashboard *)createHomeDashboard {
    NSArray *views = @[
        // Lighting & Controls
        @{
            @"title": @"Lighting & Controls",
            @"path": @"lighting",
            @"type": @"sections",
            @"max_columns": @3,
            @"sections": @[
                @{
                    @"title": @"Lights",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"light.kitchen",
                          @"features": @[@{@"type": @"light-brightness"}]},
                        @{@"type": @"tile", @"entity": @"light.living_room_accent",
                          @"features": @[@{@"type": @"light-brightness"}]},
                        @{@"type": @"tile", @"entity": @"light.bedroom",
                          @"features": @[@{@"type": @"light-brightness"}]},
                        @{@"type": @"tile", @"entity": @"light.hallway"}
                    ]
                },
                @{
                    @"title": @"Switches",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"switch.in_meeting"},
                        @{@"type": @"tile", @"entity": @"switch.driveway"},
                        @{@"type": @"tile", @"entity": @"switch.decorative_lights"}
                    ]
                },
                @{
                    @"title": @"Scenes",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"scene.movie_night",
                          @"tap_action": @{@"action": @"navigate", @"navigation_path": @"/demo-home/climate"}},
                        @{@"type": @"tile", @"entity": @"scene.good_morning"}
                    ]
                },
                @{
                    @"title": @"Fans",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"fan.living_room",
                          @"features": @[@{@"type": @"fan-speed"}]},
                        @{@"type": @"tile", @"entity": @"fan.bedroom",
                          @"features": @[@{@"type": @"toggle"}]}
                    ]
                }
            ]
        },
        // Climate & Weather
        @{
            @"title": @"Climate & Weather",
            @"path": @"climate",
            @"type": @"sections",
            @"max_columns": @3,
            @"sections": @[
                @{
                    @"title": @"Thermostats",
                    @"cards": @[
                        @{@"type": @"thermostat", @"entity": @"climate.living_room"},
                        @{@"type": @"thermostat", @"entity": @"climate.office"},
                        @{@"type": @"thermostat", @"entity": @"climate.bedroom"}
                    ]
                },
                @{
                    @"title": @"Climate Tiles",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"climate.aidoo",
                          @"features": @[
                              @{@"type": @"climate-hvac-modes",
                                @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
                                @"style": @"icons"},
                              @{@"type": @"target-temperature"}
                          ]},
                        @{@"type": @"tile", @"entity": @"climate.office",
                          @"features": @[
                              @{@"type": @"climate-hvac-modes", @"style": @"dropdown"},
                              @{@"type": @"target-temperature"}
                          ]}
                    ]
                },
                @{
                    @"title": @"Humidifiers",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"humidifier.bedroom"}
                    ]
                },
                @{
                    @"title": @"Weather",
                    @"cards": @[
                        @{@"type": @"weather-forecast", @"entity": @"weather.home", @"forecast_type": @"daily"},
                        @{@"type": @"weather-forecast", @"entity": @"weather.office", @"forecast_type": @"daily"}
                    ]
                }
            ]
        },
        // Security & Access
        @{
            @"title": @"Security & Access",
            @"path": @"security",
            @"type": @"sections",
            @"max_columns": @3,
            @"sections": @[
                @{
                    @"title": @"Locks",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"lock.frontdoor",
                          @"features": @[@{@"type": @"lock-commands"}]},
                        @{@"type": @"tile", @"entity": @"lock.back_door",
                          @"features": @[@{@"type": @"lock-commands"}]},
                        @{@"type": @"tile", @"entity": @"lock.garage",
                          @"features": @[@{@"type": @"lock-commands"}]}
                    ]
                },
                @{
                    @"title": @"Alarm",
                    @"cards": @[
                        @{@"type": @"alarm-panel", @"entity": @"alarm_control_panel.home_alarm"}
                    ]
                },
                @{
                    @"title": @"Covers",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"cover.living_room_shutter",
                          @"features": @[@{@"type": @"cover-open-close"}, @{@"type": @"cover-position"}]},
                        @{@"type": @"tile", @"entity": @"cover.garage_door",
                          @"features": @[@{@"type": @"cover-open-close"}]},
                        @{@"type": @"tile", @"entity": @"cover.office_blinds",
                          @"features": @[@{@"type": @"cover-position"}]}
                    ]
                }
            ]
        }
    ];

    NSDictionary *dict = @{@"title": @"Home", @"views": views};
    return [[HALovelaceDashboard alloc] initWithDictionary:dict];
}

- (HALovelaceDashboard *)createMonitoringDashboard {
    NSArray *views = @[
        // Sensors & Monitoring
        @{
            @"title": @"Sensors",
            @"path": @"sensors",
            @"type": @"sections",
            @"max_columns": @3,
            @"sections": @[
                @{
                    @"title": @"At a Glance",
                    @"cards": @[
                        @{@"type": @"glance",
                          @"title": @"Home Overview",
                          @"columns": @4,
                          @"show_name": @YES,
                          @"show_state": @YES,
                          @"state_color": @YES,
                          @"entities": @[
                              @{@"entity": @"sensor.living_room_temperature"},
                              @{@"entity": @"sensor.living_room_humidity"},
                              @{@"entity": @"light.kitchen"},
                              @{@"entity": @"binary_sensor.front_door"},
                              @{@"entity": @"lock.frontdoor"},
                              @{@"entity": @"sensor.phone_battery"}
                          ]}
                    ]
                },
                @{
                    @"title": @"Environment",
                    @"cards": @[
                        @{@"type": @"sensor", @"entity": @"sensor.living_room_temperature", @"graph": @"line", @"hours_to_show": @24},
                        @{@"type": @"sensor", @"entity": @"sensor.living_room_humidity", @"graph": @"line", @"hours_to_show": @24},
                        @{@"type": @"sensor", @"entity": @"sensor.power_consumption", @"graph": @"line", @"hours_to_show": @24}
                    ]
                },
                @{
                    @"title": @"Gauges",
                    @"cards": @[
                        @{@"type": @"gauge", @"entity": @"sensor.living_room_humidity", @"min": @0, @"max": @100, @"name": @"Humidity"},
                        @{@"type": @"gauge", @"entity": @"sensor.cpu_temperature", @"min": @0, @"max": @100, @"name": @"CPU Temp",
                          @"severity": @{@"green": @40, @"yellow": @70, @"red": @90}}
                    ]
                },
                @{
                    @"title": @"Counters & Timers",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"counter.litterbox_visits"},
                        @{@"type": @"tile", @"entity": @"timer.laundry"},
                        @{@"type": @"tile", @"entity": @"timer.oven"}
                    ]
                }
            ]
        },
        // Inputs
        @{
            @"title": @"Inputs",
            @"path": @"inputs",
            @"type": @"sections",
            @"max_columns": @3,
            @"sections": @[
                @{
                    @"title": @"Selects",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"input_select.media_source"},
                        @{@"type": @"tile", @"entity": @"input_select.living_room_app"}
                    ]
                },
                @{
                    @"title": @"Numbers & Text",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"input_number.target_temperature"},
                        @{@"type": @"tile", @"entity": @"input_text.greeting"},
                        @{@"type": @"tile", @"entity": @"input_datetime.morning_alarm"}
                    ]
                },
                @{
                    @"title": @"Booleans",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"input_boolean.vacation_mode"}
                    ]
                }
            ]
        },
        // All Entities
        @{
            @"title": @"All Entities",
            @"path": @"entities",
            @"type": @"sections",
            @"max_columns": @3,
            @"sections": @[
                @{
                    @"title": @"People",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"person.james"},
                        @{@"type": @"tile", @"entity": @"person.olivia"}
                    ]
                },
                @{
                    @"title": @"Binary Sensors",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"binary_sensor.hallway_motion"},
                        @{@"type": @"tile", @"entity": @"binary_sensor.front_door"},
                        @{@"type": @"tile", @"entity": @"binary_sensor.kitchen_leak"}
                    ]
                },
                @{
                    @"title": @"Updates",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"update.home_assistant_core",
                          @"tap_action": @{@"action": @"url", @"url_path": @"https://www.home-assistant.io/blog/"}}
                    ]
                }
            ]
        }
    ];

    NSDictionary *dict = @{@"title": @"Monitoring", @"views": views};
    return [[HALovelaceDashboard alloc] initWithDictionary:dict];
}

- (HALovelaceDashboard *)createMediaDashboard {
    NSArray *views = @[
        // Media & Entertainment
        @{
            @"title": @"Media Players",
            @"path": @"media",
            @"type": @"sections",
            @"max_columns": @3,
            @"sections": @[
                @{
                    @"title": @"Media Players",
                    @"cards": @[
                        @{@"type": @"media-control", @"entity": @"media_player.living_room_speaker"},
                        @{@"type": @"media-control", @"entity": @"media_player.bedroom_speaker"},
                        @{@"type": @"media-control", @"entity": @"media_player.study_speaker"}
                    ]
                }
            ]
        },
        // Vacuums
        @{
            @"title": @"Vacuums",
            @"path": @"vacuums",
            @"type": @"sections",
            @"max_columns": @3,
            @"sections": @[
                @{
                    @"title": @"Robot Vacuums",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"vacuum.roborock"},
                        @{@"type": @"tile", @"entity": @"vacuum.saros_10"}
                    ]
                }
            ]
        }
    ];

    NSDictionary *dict = @{@"title": @"Media", @"views": views};
    return [[HALovelaceDashboard alloc] initWithDictionary:dict];
}

- (HALovelaceDashboard *)createEntityShowcaseDashboard {
    // Helper macro for tile+features
    #define T(eid) @{@"type": @"tile", @"entity": eid}
    #define TF(eid, ...) @{@"type": @"tile", @"entity": eid, @"features": @[__VA_ARGS__]}
    #define F(t) @{@"type": t}
    #define FS(t, s) @{@"type": t, @"style": s}
    #define A(eid) @{@"type": @"alarm-panel", @"entity": eid}
    #define M(eid) @{@"type": @"media-control", @"entity": eid}
    #define TH(eid) @{@"type": @"thermostat", @"entity": eid}

    NSArray *views = @[
        // ── View 1: Lights & Switches ──
        @{@"title": @"Lights & Switches", @"path": @"lights", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Lights (10)", @"cards": @[
                TF(@"light.sc_basic_on", F(@"light-brightness")),
                T(@"light.sc_basic_off"),
                TF(@"light.sc_color_temp", F(@"light-brightness"), F(@"light-color-temp")),
                TF(@"light.sc_rgb", F(@"light-brightness")),
                TF(@"light.sc_rgbw", F(@"light-brightness")),
                TF(@"light.sc_all_modes", F(@"light-brightness"), F(@"light-color-temp")),
                TF(@"light.sc_effect", F(@"light-brightness")),
                TF(@"light.sc_brightness_only", F(@"light-brightness")),
                TF(@"light.sc_dimmed_low", F(@"light-brightness")),
                TF(@"light.sc_max_bright", F(@"light-brightness"))
            ]},
            @{@"title": @"Switches", @"cards": @[
                T(@"switch.in_meeting"), T(@"switch.driveway"), T(@"switch.decorative_lights")
            ]},
            @{@"title": @"Input Booleans", @"cards": @[
                T(@"input_boolean.sc_on"), T(@"input_boolean.sc_off")
            ]}
        ]},
        // ── View 2: Climate & HVAC ──
        @{@"title": @"Climate & HVAC", @"path": @"climate", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Thermostat Gauges (8)", @"cards": @[
                TH(@"climate.sc_heating"), TH(@"climate.sc_cooling"),
                TH(@"climate.sc_heat_cool"), TH(@"climate.sc_off")
            ]},
            @{@"title": @"Climate Tiles (8)", @"cards": @[
                TF(@"climate.sc_heating", FS(@"climate-hvac-modes", @"icons"), F(@"target-temperature")),
                TF(@"climate.sc_cooling", FS(@"climate-hvac-modes", @"icons"), F(@"target-temperature")),
                TF(@"climate.sc_presets", FS(@"climate-hvac-modes", @"icons"), F(@"target-temperature"), FS(@"climate-preset-modes", @"icons")),
                TF(@"climate.sc_fan", FS(@"climate-hvac-modes", @"icons"), F(@"target-temperature"), FS(@"climate-fan-modes", @"icons")),
                TF(@"climate.sc_swing", FS(@"climate-hvac-modes", @"dropdown"), F(@"target-temperature")),
                TF(@"climate.sc_all", FS(@"climate-hvac-modes", @"icons"), F(@"target-temperature"), FS(@"climate-preset-modes", @"icons"), FS(@"climate-fan-modes", @"icons")),
                TF(@"climate.sc_heat_cool", FS(@"climate-hvac-modes", @"icons"), F(@"target-temperature")),
                TF(@"climate.sc_off", FS(@"climate-hvac-modes", @"icons"))
            ]},
            @{@"title": @"Humidifiers & Water", @"cards": @[
                TF(@"humidifier.sc_on", F(@"target-humidity")),
                TF(@"humidifier.sc_eco", F(@"target-humidity")),
                T(@"humidifier.sc_off"),
                TF(@"water_heater.sc", F(@"target-temperature"))
            ]}
        ]},
        // ── View 3: Covers & Locks ──
        @{@"title": @"Covers & Locks", @"path": @"covers", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Covers (10)", @"cards": @[
                TF(@"cover.sc_position", F(@"cover-open-close"), F(@"cover-position")),
                TF(@"cover.sc_tilt", F(@"cover-open-close"), F(@"cover-position"), F(@"cover-tilt-position")),
                TF(@"cover.sc_pos_tilt", F(@"cover-open-close"), F(@"cover-position"), F(@"cover-tilt-position")),
                TF(@"cover.sc_no_position", F(@"cover-open-close")),
                TF(@"cover.sc_opening", F(@"cover-open-close"), F(@"cover-position")),
                TF(@"cover.sc_closed", F(@"cover-open-close"), F(@"cover-position")),
                TF(@"cover.sc_blind", F(@"cover-open-close"), F(@"cover-position"), F(@"cover-tilt-position")),
                TF(@"cover.sc_garage", F(@"cover-open-close")),
                TF(@"cover.sc_door", F(@"cover-open-close")),
                TF(@"cover.sc_shutter", F(@"cover-open-close"), F(@"cover-position"))
            ]},
            @{@"title": @"Locks (5)", @"cards": @[
                TF(@"lock.sc_locked", F(@"lock-commands")),
                TF(@"lock.sc_unlocked", F(@"lock-commands")),
                TF(@"lock.sc_jammed", F(@"lock-commands")),
                TF(@"lock.sc_code", F(@"lock-commands")),
                TF(@"lock.sc_locking", F(@"lock-commands"))
            ]}
        ]},
        // ── View 4: Media Players ──
        @{@"title": @"Media Players", @"path": @"media", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Media Players (6)", @"cards": @[
                M(@"media_player.sc_full"), M(@"media_player.sc_paused"),
                M(@"media_player.sc_muted"), M(@"media_player.sc_idle"),
                M(@"media_player.sc_off"), M(@"media_player.sc_no_source")
            ]}
        ]},
        // ── View 5: Sensors ──
        @{@"title": @"Sensors", @"path": @"sensors", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Sensors (10)", @"cards": @[
                T(@"sensor.sc_temperature"), T(@"sensor.sc_humidity"),
                T(@"sensor.sc_power"), T(@"sensor.sc_energy"),
                T(@"sensor.sc_battery"), T(@"sensor.sc_illuminance"),
                T(@"sensor.sc_pressure"), T(@"sensor.sc_gas"),
                T(@"sensor.sc_monetary"), T(@"sensor.sc_text")
            ]},
            @{@"title": @"Binary Sensors (12)", @"cards": @[
                T(@"binary_sensor.sc_door_open"), T(@"binary_sensor.sc_door_closed"),
                T(@"binary_sensor.sc_motion_on"), T(@"binary_sensor.sc_motion_off"),
                T(@"binary_sensor.sc_smoke"), T(@"binary_sensor.sc_moisture"),
                T(@"binary_sensor.sc_window"), T(@"binary_sensor.sc_occupancy"),
                T(@"binary_sensor.sc_presence"), T(@"binary_sensor.sc_battery_low"),
                T(@"binary_sensor.sc_plug"), T(@"binary_sensor.sc_generic")
            ]},
            @{@"title": @"Glance", @"cards": @[
                @{@"type": @"glance", @"title": @"All Sensors", @"columns": @5,
                  @"show_name": @YES, @"show_state": @YES, @"state_color": @YES,
                  @"entities": @[
                    @{@"entity": @"sensor.sc_temperature"}, @{@"entity": @"sensor.sc_humidity"},
                    @{@"entity": @"sensor.sc_power"}, @{@"entity": @"sensor.sc_battery"},
                    @{@"entity": @"sensor.sc_illuminance"}, @{@"entity": @"sensor.sc_pressure"},
                    @{@"entity": @"sensor.sc_energy"}, @{@"entity": @"sensor.sc_gas"},
                    @{@"entity": @"sensor.sc_monetary"}, @{@"entity": @"sensor.sc_text"}
                ]}
            ]},
            @{@"title": @"Weather", @"cards": @[
                @{@"type": @"weather-forecast", @"entity": @"weather.home", @"forecast_type": @"daily"}
            ]}
        ]},
        // ── View 6: Inputs & Controls ──
        @{@"title": @"Inputs & Controls", @"path": @"inputs", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Numbers", @"cards": @[
                T(@"input_number.sc_slider"), T(@"input_number.sc_box")
            ]},
            @{@"title": @"Selects", @"cards": @[T(@"input_select.sc")]},
            @{@"title": @"Text", @"cards": @[
                T(@"input_text.sc_text"), T(@"input_text.sc_password")
            ]},
            @{@"title": @"Date & Time", @"cards": @[
                T(@"input_datetime.sc_date"), T(@"input_datetime.sc_time"), T(@"input_datetime.sc_both")
            ]},
            @{@"title": @"Counters & Timers", @"cards": @[
                TF(@"counter.sc", F(@"counter-actions")),
                T(@"timer.sc_active"), T(@"timer.sc_paused"), T(@"timer.sc_idle")
            ]}
        ]},
        // ── View 7: Alarms & Vacuum ──
        @{@"title": @"Alarms & Vacuum", @"path": @"alarms", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Alarms (7)", @"cards": @[
                A(@"alarm_control_panel.sc_disarmed"), A(@"alarm_control_panel.sc_home"),
                A(@"alarm_control_panel.sc_away"), A(@"alarm_control_panel.sc_night"),
                A(@"alarm_control_panel.sc_vacation"), A(@"alarm_control_panel.sc_triggered"),
                A(@"alarm_control_panel.sc_no_code")
            ]},
            @{@"title": @"Vacuums (4)", @"cards": @[
                TF(@"vacuum.sc_docked", F(@"vacuum-commands")),
                TF(@"vacuum.sc_cleaning", F(@"vacuum-commands")),
                TF(@"vacuum.sc_returning", F(@"vacuum-commands")),
                TF(@"vacuum.sc_error", F(@"vacuum-commands"))
            ]}
        ]},
        // ── View 8: Fans & Misc ──
        @{@"title": @"Fans & Misc", @"path": @"fans", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Fans (5)", @"cards": @[
                TF(@"fan.sc_basic", F(@"fan-speed")),
                TF(@"fan.sc_presets", F(@"fan-speed")),
                TF(@"fan.sc_oscillating", F(@"fan-speed")),
                TF(@"fan.sc_reverse", F(@"fan-speed")),
                T(@"fan.sc_off")
            ]},
            @{@"title": @"People", @"cards": @[
                T(@"person.sc_home"), T(@"person.sc_away"), T(@"person.sc_zone")
            ]},
            @{@"title": @"Actions", @"cards": @[
                T(@"scene.sc"), T(@"script.sc"), T(@"automation.sc"),
                T(@"button.restart"), T(@"update.sc_available"), T(@"update.sc_current")
            ]}
        ]},
        // ── View 9: New Domains ──
        @{@"title": @"New Domains", @"path": @"new-domains", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Valves", @"cards": @[T(@"valve.sc_open"), T(@"valve.sc_closed")]},
            @{@"title": @"Lawn Mowers", @"cards": @[T(@"lawn_mower.sc_docked"), T(@"lawn_mower.sc_mowing")]},
            @{@"title": @"Other", @"cards": @[
                T(@"remote.sc"), T(@"image.sc"), T(@"todo.sc"),
                T(@"event.sc"), T(@"device_tracker.sc_home"), T(@"device_tracker.sc_away")
            ]}
        ]},
        // ── View 10: Card Types ──
        @{@"title": @"Card Types", @"path": @"card-types", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Entities Card (secondary_info)", @"cards": @[
                @{@"type": @"entities", @"title": @"Entity Rows", @"show_header_toggle": @NO,
                  @"entities": @[
                    @{@"entity": @"light.sc_basic_on", @"secondary_info": @"last-changed"},
                    @{@"entity": @"sensor.sc_temperature", @"secondary_info": @"entity-id"},
                    @{@"entity": @"cover.sc_position", @"secondary_info": @"position"},
                    @{@"entity": @"light.sc_brightness_only", @"secondary_info": @"brightness"},
                    @{@"entity": @"binary_sensor.sc_door_open", @"secondary_info": @"last-updated"}
                ]}
            ]},
            @{@"title": @"Entities Card (state_color)", @"cards": @[
                @{@"type": @"entities", @"title": @"State Colors",
                  @"entities": @[
                    @{@"entity": @"light.sc_basic_on", @"state_color": @YES},
                    @{@"entity": @"light.sc_basic_off", @"state_color": @YES},
                    @{@"entity": @"switch.in_meeting", @"state_color": @YES},
                    @{@"entity": @"binary_sensor.sc_motion_on", @"state_color": @YES},
                    @{@"type": @"divider"},
                    @{@"entity": @"sensor.sc_temperature"},
                    @{@"type": @"section", @"label": @"Covers"},
                    @{@"entity": @"cover.sc_position", @"state_color": @YES}
                ]}
            ]},
            @{@"title": @"Entity Card", @"cards": @[
                @{@"type": @"entity", @"entity": @"sensor.sc_temperature"},
                @{@"type": @"entity", @"entity": @"light.sc_basic_on", @"attribute": @"brightness"}
            ]},
            @{@"title": @"Statistic Card", @"cards": @[
                @{@"type": @"statistic", @"entity": @"sensor.sc_energy", @"stat_type": @"max"},
                @{@"type": @"statistic", @"entity": @"sensor.sc_temperature", @"stat_type": @"mean"}
            ]},
            @{@"title": @"Markdown Card", @"cards": @[
                @{@"type": @"markdown", @"content": @"## Dashboard Info\n**Status**: Online\n\n- Lights: 10\n- Sensors: 10\n- Automations: Active\n\n> Built with HA Dashboard"}
            ]},
            @{@"title": @"Glance Card (state_color)", @"cards": @[
                @{@"type": @"glance", @"title": @"Quick Status", @"columns": @3,
                  @"show_name": @YES, @"show_state": @YES, @"state_color": @YES,
                  @"entities": @[
                    @{@"entity": @"light.sc_basic_on"}, @{@"entity": @"light.sc_basic_off"},
                    @{@"entity": @"switch.in_meeting"}, @{@"entity": @"binary_sensor.sc_door_open"},
                    @{@"entity": @"sensor.sc_temperature"}, @{@"entity": @"person.sc_home"}
                ]}
            ]},
            @{@"title": @"Entity Filter Card", @"cards": @[
                @{@"type": @"entity-filter",
                  @"state_filter": @[@"on"],
                  @"card": @{@"type": @"entities", @"title": @"Active Entities"},
                  @"entities": @[
                    @"light.sc_basic_on", @"light.sc_basic_off",
                    @"switch.in_meeting", @"switch.driveway",
                    @"input_boolean.sc_on", @"input_boolean.sc_off"
                ]}
            ]},
            @{@"title": @"Area Card", @"cards": @[
                @{@"type": @"area", @"area": @"living_room"}
            ]},
            @{@"title": @"Picture Glance", @"cards": @[
                @{@"type": @"picture-glance", @"title": @"Living Room",
                  @"entities": @[@"light.sc_basic_on", @"sensor.sc_temperature", @"binary_sensor.sc_motion_on"]}
            ]},
            @{@"title": @"Map Card", @"cards": @[
                @{@"type": @"map", @"entities": @[@"person.sc_home", @"person.sc_away", @"device_tracker.sc_home"],
                  @"default_zoom": @14}
            ]},
            @{@"title": @"Camera Cards", @"cards": @[
                @{@"type": @"tile", @"entity": @"camera.sc_streaming"},
                @{@"type": @"tile", @"entity": @"camera.sc_idle"}
            ]}
        ]},
        // ── View 11: Display Options ──
        @{@"title": @"Display Options", @"path": @"display-opts", @"type": @"sections", @"max_columns": @3, @"sections": @[
            @{@"title": @"Tile: state_content", @"cards": @[
                @{@"type": @"tile", @"entity": @"light.sc_basic_on", @"state_content": @"last-changed"},
                @{@"type": @"tile", @"entity": @"sensor.sc_temperature", @"state_content": @[@"state", @"last-changed"]}
            ]},
            @{@"title": @"Tile: attribute display", @"cards": @[
                @{@"type": @"tile", @"entity": @"light.sc_brightness_only", @"attribute": @"brightness"},
                @{@"type": @"tile", @"entity": @"climate.sc_heating", @"attribute": @"current_temperature"}
            ]},
            @{@"title": @"Tile: vertical layout", @"cards": @[
                @{@"type": @"tile", @"entity": @"light.sc_basic_on", @"vertical": @YES,
                  @"features": @[@{@"type": @"light-brightness"}]},
                @{@"type": @"tile", @"entity": @"fan.sc_basic", @"vertical": @YES,
                  @"features": @[@{@"type": @"fan-speed"}]}
            ]},
            @{@"title": @"Tile: hide_state", @"cards": @[
                @{@"type": @"tile", @"entity": @"switch.in_meeting", @"hide_state": @YES},
                @{@"type": @"tile", @"entity": @"light.sc_basic_on", @"hide_state": @YES}
            ]},
            @{@"title": @"Tile: show_entity_picture", @"cards": @[
                @{@"type": @"tile", @"entity": @"person.sc_home", @"show_entity_picture": @YES},
                @{@"type": @"tile", @"entity": @"person.sc_away", @"show_entity_picture": @YES}
            ]},
            @{@"title": @"Media With Art", @"cards": @[
                M(@"media_player.sc_with_art"), M(@"media_player.sc_full")
            ]}
        ]}
    ];

    #undef T
    #undef TF
    #undef F
    #undef FS
    #undef A
    #undef M
    #undef TH

    NSDictionary *dict = @{@"title": @"Entity Showcase", @"views": views};
    return [[HALovelaceDashboard alloc] initWithDictionary:dict];
}

#pragma mark - Entity Access

- (NSDictionary<NSString *, HAEntity *> *)allEntities {
    return [_entityStore copy];
}

- (HAEntity *)entityForId:(NSString *)entityId {
    return _entityStore[entityId];
}

#pragma mark - Fake History Generation

- (NSArray *)historyPointsForEntityId:(NSString *)entityId hoursBack:(NSInteger)hours {
    // Generate 100 fake data points over the requested time range
    NSMutableArray *points = [NSMutableArray arrayWithCapacity:100];

    HAEntity *entity = _entityStore[entityId];
    double baseValue = [entity.state doubleValue];
    if (baseValue == 0) baseValue = 22.0; // Default for non-numeric sensors

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval startTime = now - (hours * 3600);
    NSTimeInterval interval = (hours * 3600.0) / 100.0;

    // Seed based on entity ID for consistent but varied results
    srand48((long)[entityId hash]);

    for (NSInteger i = 0; i < 100; i++) {
        NSTimeInterval timestamp = startTime + (i * interval);

        // Generate realistic variation: sine wave + noise
        double sineComponent = sin(i * 0.1) * (baseValue * 0.1);
        double noise = (drand48() - 0.5) * (baseValue * 0.05);
        double value = baseValue + sineComponent + noise;

        [points addObject:@{
            @"value": @(value),
            @"timestamp": @(timestamp)
        }];
    }

    return [points copy];
}

- (NSArray *)timelineSegmentsForEntityId:(NSString *)entityId hoursBack:(NSInteger)hours {
    // Generate fake state timeline segments
    NSMutableArray *segments = [NSMutableArray array];

    HAEntity *entity = _entityStore[entityId];
    NSArray *possibleStates;

    // Determine possible states based on domain
    NSString *domain = [entity domain];
    if ([domain isEqualToString:@"light"] || [domain isEqualToString:@"switch"]) {
        possibleStates = @[@"on", @"off"];
    } else if ([domain isEqualToString:@"lock"]) {
        possibleStates = @[@"locked", @"unlocked"];
    } else if ([domain isEqualToString:@"cover"]) {
        possibleStates = @[@"open", @"closed"];
    } else if ([domain isEqualToString:@"binary_sensor"]) {
        possibleStates = @[@"on", @"off"];
    } else {
        possibleStates = @[entity.state ?: @"unknown"];
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval startTime = now - (hours * 3600);

    // Create 5-10 state segments
    srand48((long)[entityId hash]);
    NSInteger numSegments = 5 + (NSInteger)(drand48() * 5);
    NSTimeInterval segmentDuration = (hours * 3600.0) / numSegments;

    for (NSInteger i = 0; i < numSegments; i++) {
        NSString *state = possibleStates[(NSUInteger)(drand48() * possibleStates.count)];
        NSTimeInterval segStart = startTime + (i * segmentDuration);
        NSTimeInterval segEnd = segStart + segmentDuration;

        [segments addObject:@{
            @"state": state,
            @"start": @(segStart),
            @"end": @(segEnd)
        }];
    }

    return [segments copy];
}

#pragma mark - State Simulation

- (void)startSimulation {
    if (_simulating) return;

    _simulating = YES;

    // Update entities every 15 seconds (use target/selector API for iOS 9 compatibility)
    _simulationTimer = [NSTimer scheduledTimerWithTimeInterval:15.0
                                                        target:self
                                                      selector:@selector(simulationTimerFired:)
                                                      userInfo:nil
                                                       repeats:YES];

    NSLog(@"[HADemo] Started state simulation");
}

- (void)stopSimulation {
    if (!_simulating) return;

    [_simulationTimer invalidate];
    _simulationTimer = nil;
    _simulating = NO;

    NSLog(@"[HADemo] Stopped state simulation");
}

- (void)simulationTimerFired:(NSTimer *)timer {
    [self simulateStateChanges];
}

- (void)simulateStateChanges {
    // Update temperature sensors with small variations
    [self updateNumericSensor:@"sensor.living_room_temperature" variation:0.3];
    [self updateNumericSensor:@"sensor.living_room_humidity" variation:1.0];
    [self updateNumericSensor:@"sensor.power_consumption" variation:50.0];
    [self updateNumericSensor:@"sensor.cpu_temperature" variation:2.0];

    // Update climate current temperatures
    [self updateClimateCurrentTemp:@"climate.living_room" variation:0.2];
    [self updateClimateCurrentTemp:@"climate.office" variation:0.2];
    [self updateClimateCurrentTemp:@"climate.bedroom" variation:0.2];

    // Occasionally toggle binary sensors (10% chance each)
    if (arc4random_uniform(10) == 0) {
        [self toggleBinarySensor:@"binary_sensor.hallway_motion"];
    }

    // Update timer remaining time
    [self updateTimerRemaining:@"timer.laundry"];
}

- (void)updateNumericSensor:(NSString *)entityId variation:(double)maxVariation {
    HAEntity *entity = _entityStore[entityId];
    if (!entity) return;

    double currentValue = [entity.state doubleValue];
    double change = ((double)arc4random_uniform(1000) / 500.0 - 1.0) * maxVariation;
    double newValue = currentValue + change;

    NSString *newState = [NSString stringWithFormat:@"%.1f", newValue];
    [entity applyOptimisticState:newState attributeOverrides:nil];

    [self postEntityUpdateNotification:entity];
}

- (void)updateClimateCurrentTemp:(NSString *)entityId variation:(double)maxVariation {
    HAEntity *entity = _entityStore[entityId];
    if (!entity) return;

    NSNumber *currentTemp = entity.attributes[@"current_temperature"];
    if (!currentTemp) return;

    double change = ((double)arc4random_uniform(1000) / 500.0 - 1.0) * maxVariation;
    double newTemp = [currentTemp doubleValue] + change;

    NSMutableDictionary *newAttrs = [entity.attributes mutableCopy];
    newAttrs[@"current_temperature"] = @(newTemp);
    entity.attributes = newAttrs;

    [self postEntityUpdateNotification:entity];
}

- (void)toggleBinarySensor:(NSString *)entityId {
    HAEntity *entity = _entityStore[entityId];
    if (!entity) return;

    NSString *newState = [entity.state isEqualToString:@"on"] ? @"off" : @"on";
    [entity applyOptimisticState:newState attributeOverrides:nil];

    [self postEntityUpdateNotification:entity];
}

- (void)updateTimerRemaining:(NSString *)entityId {
    HAEntity *entity = _entityStore[entityId];
    if (!entity || ![entity.state isEqualToString:@"active"]) return;

    NSString *remaining = entity.attributes[@"remaining"];
    if (!remaining) return;

    // Parse HH:MM:SS and subtract 15 seconds
    NSArray *parts = [remaining componentsSeparatedByString:@":"];
    if (parts.count != 3) return;

    NSInteger hours = [parts[0] integerValue];
    NSInteger minutes = [parts[1] integerValue];
    NSInteger seconds = [parts[2] integerValue];

    NSInteger totalSeconds = hours * 3600 + minutes * 60 + seconds - 15;
    if (totalSeconds < 0) totalSeconds = 0;

    NSInteger newHours = totalSeconds / 3600;
    NSInteger newMinutes = (totalSeconds % 3600) / 60;
    NSInteger newSeconds = totalSeconds % 60;

    NSString *newRemaining = [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)newHours, (long)newMinutes, (long)newSeconds];

    NSMutableDictionary *newAttrs = [entity.attributes mutableCopy];
    newAttrs[@"remaining"] = newRemaining;
    entity.attributes = newAttrs;

    if (totalSeconds == 0) {
        [entity applyOptimisticState:@"idle" attributeOverrides:nil];
    }

    [self postEntityUpdateNotification:entity];
}

- (void)postEntityUpdateNotification:(HAEntity *)entity {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerEntityDidUpdateNotification
                      object:nil
                    userInfo:@{@"entity": entity}];
}

@end
