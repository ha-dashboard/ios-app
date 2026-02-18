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
        @{@"title": @"Media",      @"url_path": @"demo-media"}
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
                        @{@"type": @"tile", @"entity": @"light.kitchen"},
                        @{@"type": @"tile", @"entity": @"light.living_room_accent"},
                        @{@"type": @"tile", @"entity": @"light.bedroom"},
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
                        @{@"type": @"tile", @"entity": @"scene.movie_night"},
                        @{@"type": @"tile", @"entity": @"scene.good_morning"}
                    ]
                },
                @{
                    @"title": @"Fans",
                    @"cards": @[
                        @{@"type": @"tile", @"entity": @"fan.living_room"},
                        @{@"type": @"tile", @"entity": @"fan.bedroom"}
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
                        @{@"type": @"tile", @"entity": @"lock.frontdoor"},
                        @{@"type": @"tile", @"entity": @"lock.back_door"},
                        @{@"type": @"tile", @"entity": @"lock.garage"}
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
                        @{@"type": @"tile", @"entity": @"cover.living_room_shutter"},
                        @{@"type": @"tile", @"entity": @"cover.garage_door"},
                        @{@"type": @"tile", @"entity": @"cover.office_blinds"}
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
                        @{@"type": @"tile", @"entity": @"update.home_assistant_core"}
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
