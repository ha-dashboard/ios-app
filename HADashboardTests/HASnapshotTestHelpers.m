#import "HASnapshotTestHelpers.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"

@implementation HASnapshotTestHelpers

#pragma mark - Core Factories

+ (HAEntity *)entityWithId:(NSString *)entityId
                     state:(NSString *)state
                attributes:(NSDictionary *)attributes {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"entity_id"] = entityId;
    dict[@"state"] = state;
    dict[@"attributes"] = attributes ?: @{};
    dict[@"last_changed"] = @"2026-01-01T00:00:00Z";
    dict[@"last_updated"] = @"2026-01-01T00:00:00Z";
    return [[HAEntity alloc] initWithDictionary:dict];
}

+ (HADashboardConfigItem *)itemWithEntityId:(NSString *)entityId
                                   cardType:(NSString *)cardType
                                 columnSpan:(NSInteger)columnSpan
                                headingIcon:(NSString *)headingIcon
                                displayName:(NSString *)displayName {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = entityId;
    item.cardType = cardType;
    item.columnSpan = columnSpan;
    item.rowSpan = 1;
    item.displayName = displayName;
    if (headingIcon) {
        NSMutableDictionary *props = [NSMutableDictionary dictionary];
        props[@"headingIcon"] = headingIcon;
        item.customProperties = [props copy];
    }
    return item;
}

+ (HADashboardConfigSection *)sectionWithTitle:(NSString *)title
                                          icon:(NSString *)icon
                                     entityIds:(NSArray<NSString *> *)entityIds {
    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.title = title;
    section.icon = icon;
    section.entityIds = entityIds;
    return section;
}

+ (NSDictionary<NSString *, HAEntity *> *)livingRoomEntities {
    NSMutableDictionary *entities = [NSMutableDictionary dictionary];

    // Thermostat
    entities[@"climate.aidoo"] = [self entityWithId:@"climate.aidoo"
        state:@"heat"
        attributes:@{
            @"friendly_name": @"Aidoo",
            @"current_temperature": @22.0,
            @"temperature": @22.0,
            @"hvac_action": @"idle",
            @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
            @"temperature_unit": @"\u00B0C"
        }];

    // Vacuum
    entities[@"vacuum.saros_10"] = [self entityWithId:@"vacuum.saros_10"
        state:@"docked"
        attributes:@{
            @"friendly_name": @"Ribbit",
            @"battery_level": @100,
            @"status": @"Docked"
        }];

    // Lights
    entities[@"light.office_3"] = [self entityWithId:@"light.office_3"
        state:@"on"
        attributes:@{@"friendly_name": @"Office", @"brightness": @255}];

    entities[@"light.downstairs"] = [self entityWithId:@"light.downstairs"
        state:@"off"
        attributes:@{@"friendly_name": @"Downstairs"}];

    entities[@"light.upstairs"] = [self entityWithId:@"light.upstairs"
        state:@"off"
        attributes:@{@"friendly_name": @"Upstairs"}];

    return [entities copy];
}

#pragma mark - Light (4 variants)

+ (HAEntity *)lightEntityOnBrightness {
    return [self entityWithId:@"light.kitchen"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"Kitchen",
        @"brightness": @178,
        @"color_temp_kelvin": @2583,
        @"color_mode": @"color_temp",
        @"supported_color_modes": @[@"color_temp", @"xy"],
        @"icon": @"mdi:ceiling-light"
    }];
}

+ (HAEntity *)lightEntityOnRGB {
    return [self entityWithId:@"light.living_room_accent"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"Living Room Accent",
        @"brightness": @200,
        @"rgb_color": @[@255, @175, @96],
        @"color_mode": @"rgb",
        @"supported_color_modes": @[@"rgb"],
        @"icon": @"mdi:led-strip-variant"
    }];
}

+ (HAEntity *)lightEntityOnDimmed {
    return [self entityWithId:@"light.bedroom"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"Bedroom",
        @"brightness": @50,
        @"color_mode": @"brightness",
        @"supported_color_modes": @[@"brightness"]
    }];
}

+ (HAEntity *)lightEntityOff {
    return [self entityWithId:@"light.hallway"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Hallway",
        @"supported_color_modes": @[@"brightness"]
    }];
}

#pragma mark - Climate (4 variants)

+ (HAEntity *)climateEntityHeat {
    return [self entityWithId:@"climate.living_room"
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
}

+ (HAEntity *)climateEntityCool {
    return [self entityWithId:@"climate.office"
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
}

+ (HAEntity *)climateEntityAuto {
    return [self entityWithId:@"climate.bedroom"
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
}

+ (HAEntity *)climateEntityOff {
    return [self entityWithId:@"climate.guest_room"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Guest Room",
        @"current_temperature": @19.5,
        @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7,
        @"max_temp": @35,
        @"temperature_unit": @"\u00B0C"
    }];
}

#pragma mark - Switch (2 variants)

+ (HAEntity *)switchEntityOn {
    return [self entityWithId:@"switch.in_meeting"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"In Meeting",
        @"icon": @"mdi:laptop-account"
    }];
}

+ (HAEntity *)switchEntityOff {
    return [self entityWithId:@"switch.driveway"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Driveway",
        @"icon": @"mdi:driveway"
    }];
}

#pragma mark - Cover (3 variants)

+ (HAEntity *)coverEntityOpenShutter {
    return [self entityWithId:@"cover.living_room_shutter"
                        state:@"open"
                   attributes:@{
        @"friendly_name": @"Living Room Shutter",
        @"current_position": @100,
        @"device_class": @"shutter"
    }];
}

+ (HAEntity *)coverEntityClosedGarage {
    return [self entityWithId:@"cover.garage_door"
                        state:@"closed"
                   attributes:@{
        @"friendly_name": @"Garage Door",
        @"device_class": @"garage"
    }];
}

+ (HAEntity *)coverEntityPartial {
    return [self entityWithId:@"cover.office_blinds"
                        state:@"open"
                   attributes:@{
        @"friendly_name": @"Office Blinds",
        @"current_position": @50,
        @"device_class": @"blind"
    }];
}

#pragma mark - Media Player (3 variants)

+ (HAEntity *)mediaPlayerPlaying {
    return [self entityWithId:@"media_player.living_room_speaker"
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
}

+ (HAEntity *)mediaPlayerPaused {
    return [self entityWithId:@"media_player.bedroom_speaker"
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
}

+ (HAEntity *)mediaPlayerOff {
    return [self entityWithId:@"media_player.study_speaker"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Study Speaker",
        @"volume_level": @0.18,
        @"is_volume_muted": @NO,
        @"icon": @"mdi:speaker"
    }];
}

#pragma mark - Sensor (6 variants)

+ (HAEntity *)sensorTemperature {
    return [self entityWithId:@"sensor.living_room_temperature"
                        state:@"22.8"
                   attributes:@{
        @"friendly_name": @"Living Room Temperature",
        @"unit_of_measurement": @"\u00B0C",
        @"device_class": @"temperature",
        @"state_class": @"measurement",
        @"icon": @"mdi:thermometer"
    }];
}

+ (HAEntity *)sensorHumidity {
    return [self entityWithId:@"sensor.living_room_humidity"
                        state:@"57"
                   attributes:@{
        @"friendly_name": @"Living Room Humidity",
        @"unit_of_measurement": @"%",
        @"device_class": @"humidity",
        @"state_class": @"measurement",
        @"icon": @"mdi:water-percent"
    }];
}

+ (HAEntity *)sensorEnergy {
    return [self entityWithId:@"sensor.power_consumption"
                        state:@"797.86"
                   attributes:@{
        @"friendly_name": @"Power Consumption",
        @"unit_of_measurement": @"W",
        @"device_class": @"power",
        @"state_class": @"measurement",
        @"icon": @"mdi:flash"
    }];
}

+ (HAEntity *)sensorBattery {
    return [self entityWithId:@"sensor.phone_battery"
                        state:@"11"
                   attributes:@{
        @"friendly_name": @"Phone Battery",
        @"unit_of_measurement": @"%",
        @"device_class": @"battery",
        @"icon": @"mdi:battery-charging"
    }];
}

+ (HAEntity *)sensorIlluminance {
    return [self entityWithId:@"sensor.office_illuminance"
                        state:@"555"
                   attributes:@{
        @"friendly_name": @"Office Illuminance",
        @"unit_of_measurement": @"lx",
        @"device_class": @"illuminance",
        @"icon": @"mdi:brightness-5"
    }];
}

+ (HAEntity *)sensorGenericText {
    return [self entityWithId:@"sensor.living_room_source"
                        state:@"YouTube"
                   attributes:@{
        @"friendly_name": @"Living Room",
        @"icon": @"mdi:television"
    }];
}

#pragma mark - Alarm Control Panel (4 variants)

+ (HAEntity *)alarmDisarmed {
    return [self entityWithId:@"alarm_control_panel.home_alarm"
                        state:@"disarmed"
                   attributes:@{
        @"friendly_name": @"Home Alarm",
        @"code_arm_required": @YES,
        @"supported_features": @31,
        @"icon": @"mdi:shield-check"
    }];
}

+ (HAEntity *)alarmArmedHome {
    return [self entityWithId:@"alarm_control_panel.home_alarm"
                        state:@"armed_home"
                   attributes:@{
        @"friendly_name": @"Home Alarm",
        @"code_arm_required": @YES,
        @"supported_features": @31,
        @"icon": @"mdi:shield-home"
    }];
}

+ (HAEntity *)alarmArmedAway {
    return [self entityWithId:@"alarm_control_panel.home_alarm"
                        state:@"armed_away"
                   attributes:@{
        @"friendly_name": @"Home Alarm",
        @"code_arm_required": @YES,
        @"supported_features": @31,
        @"icon": @"mdi:shield-lock"
    }];
}

+ (HAEntity *)alarmTriggered {
    return [self entityWithId:@"alarm_control_panel.home_alarm"
                        state:@"triggered"
                   attributes:@{
        @"friendly_name": @"Home Alarm",
        @"code_arm_required": @YES,
        @"supported_features": @31,
        @"icon": @"mdi:bell-ring"
    }];
}

#pragma mark - Person (2 variants)

+ (HAEntity *)personHome {
    return [self entityWithId:@"person.james"
                        state:@"home"
                   attributes:@{
        @"friendly_name": @"James",
        @"entity_picture": @"/local/james.jpg",
        @"latitude": @52.363,
        @"longitude": @4.890,
        @"gps_accuracy": @10,
        @"icon": @"mdi:account"
    }];
}

+ (HAEntity *)personNotHome {
    return [self entityWithId:@"person.olivia"
                        state:@"not_home"
                   attributes:@{
        @"friendly_name": @"Olivia",
        @"entity_picture": @"/local/olivia.jpg",
        @"latitude": @52.357,
        @"longitude": @4.866,
        @"gps_accuracy": @25,
        @"icon": @"mdi:account"
    }];
}

#pragma mark - Lock (3 variants)

+ (HAEntity *)lockLocked {
    return [self entityWithId:@"lock.frontdoor"
                        state:@"locked"
                   attributes:@{
        @"friendly_name": @"Frontdoor",
        @"icon": @"mdi:lock"
    }];
}

+ (HAEntity *)lockUnlocked {
    return [self entityWithId:@"lock.frontdoor"
                        state:@"unlocked"
                   attributes:@{
        @"friendly_name": @"Frontdoor",
        @"icon": @"mdi:lock-open"
    }];
}

+ (HAEntity *)lockJammed {
    return [self entityWithId:@"lock.frontdoor"
                        state:@"jammed"
                   attributes:@{
        @"friendly_name": @"Frontdoor",
        @"icon": @"mdi:lock-alert"
    }];
}

#pragma mark - Weather (3 variants)

+ (HAEntity *)weatherSunny {
    return [self entityWithId:@"weather.home"
                        state:@"sunny"
                   attributes:@{
        @"friendly_name": @"Home",
        @"temperature": @-5,
        @"humidity": @75,
        @"pressure": @1012,
        @"wind_speed": @8,
        @"wind_bearing": @"NW",
        @"temperature_unit": @"\u00B0C",
        @"forecast": [self forecastArrayForDays:9],
        @"icon": @"mdi:weather-sunny"
    }];
}

+ (HAEntity *)weatherCloudy {
    return [self entityWithId:@"weather.office"
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
}

+ (HAEntity *)weatherRainy {
    return [self entityWithId:@"weather.garden"
                        state:@"rainy"
                   attributes:@{
        @"friendly_name": @"Garden",
        @"temperature": @8,
        @"humidity": @95,
        @"pressure": @1002,
        @"wind_speed": @22,
        @"wind_bearing": @"S",
        @"temperature_unit": @"\u00B0C",
        @"icon": @"mdi:weather-pouring"
    }];
}

#pragma mark - Input Select (2 variants)

+ (HAEntity *)inputSelectThreeOptions {
    return [self entityWithId:@"input_select.media_source"
                        state:@"Shield"
                   attributes:@{
        @"friendly_name": @"Media Source",
        @"options": @[@"AppleTV", @"FireTV", @"Shield"],
        @"icon": @"mdi:remote"
    }];
}

+ (HAEntity *)inputSelectFiveOptions {
    return [self entityWithId:@"input_select.living_room_app"
                        state:@"YouTube"
                   attributes:@{
        @"friendly_name": @"Living Room App",
        @"options": @[@"PowerOff", @"YouTube", @"Netflix", @"Plex", @"AppleTV"],
        @"icon": @"mdi:application"
    }];
}

#pragma mark - Input Number (2 variants)

+ (HAEntity *)inputNumberSlider {
    return [self entityWithId:@"input_number.target_temperature"
                        state:@"18.0"
                   attributes:@{
        @"friendly_name": @"Target Temperature",
        @"min": @1,
        @"max": @100,
        @"step": @1,
        @"mode": @"slider",
        @"icon": @"mdi:thermometer"
    }];
}

+ (HAEntity *)inputNumberBox {
    return [self entityWithId:@"input_number.standing_desk_height"
                        state:@"72"
                   attributes:@{
        @"friendly_name": @"Standing Desk Height",
        @"min": @60,
        @"max": @120,
        @"step": @1,
        @"mode": @"box",
        @"unit_of_measurement": @"cm",
        @"icon": @"mdi:desk"
    }];
}

#pragma mark - Button (2 variants)

+ (HAEntity *)buttonDefault {
    return [self entityWithId:@"button.tv_off"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"TV Off",
        @"icon": @"mdi:television-off"
    }];
}

+ (HAEntity *)buttonPressed {
    return [self entityWithId:@"button.restart"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"Restart",
        @"icon": @"mdi:restart"
    }];
}

#pragma mark - Update (2 variants)

+ (HAEntity *)updateAvailable {
    return [self entityWithId:@"update.home_assistant_core"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"Home Assistant Core",
        @"installed_version": @"2024.2.0",
        @"latest_version": @"2024.4.0",
        @"title": @"Home Assistant Core",
        @"release_url": @"https://www.home-assistant.io/blog/",
        @"icon": @"mdi:package-up"
    }];
}

+ (HAEntity *)updateUpToDate {
    return [self entityWithId:@"update.home_assistant_core"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Home Assistant Core",
        @"installed_version": @"2024.4.0",
        @"latest_version": @"2024.4.0",
        @"title": @"Home Assistant Core",
        @"icon": @"mdi:package-check"
    }];
}

#pragma mark - Counter (2 variants)

+ (HAEntity *)counterLow {
    return [self entityWithId:@"counter.litterbox_visits"
                        state:@"3"
                   attributes:@{
        @"friendly_name": @"Litterbox Visits",
        @"icon": @"mdi:cat",
        @"step": @1
    }];
}

+ (HAEntity *)counterHigh {
    return [self entityWithId:@"counter.page_views"
                        state:@"42"
                   attributes:@{
        @"friendly_name": @"Page Views",
        @"icon": @"mdi:counter",
        @"step": @1
    }];
}

#pragma mark - Binary Sensor (3 variants)

+ (HAEntity *)binarySensorMotionOn {
    return [self entityWithId:@"binary_sensor.hallway_motion"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"Hallway Motion",
        @"device_class": @"motion",
        @"icon": @"mdi:motion-sensor"
    }];
}

+ (HAEntity *)binarySensorDoorOff {
    return [self entityWithId:@"binary_sensor.front_door"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Front Door",
        @"device_class": @"door",
        @"icon": @"mdi:door-closed"
    }];
}

+ (HAEntity *)binarySensorMoistureOff {
    return [self entityWithId:@"binary_sensor.kitchen_leak"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Kitchen Leak",
        @"device_class": @"moisture",
        @"battery_level": @47,
        @"icon": @"mdi:water-off"
    }];
}

#pragma mark - Device Tracker (1 variant)

+ (HAEntity *)deviceTrackerNotHome {
    return [self entityWithId:@"device_tracker.car"
                        state:@"not_home"
                   attributes:@{
        @"friendly_name": @"Car",
        @"icon": @"mdi:car",
        @"source_type": @"gps"
    }];
}

#pragma mark - Fan (3 variants)

+ (HAEntity *)fanEntityOnHalf {
    return [self entityWithId:@"fan.living_room"
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
}

+ (HAEntity *)fanEntityOnFull {
    return [self entityWithId:@"fan.bedroom"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"Bedroom Fan",
        @"percentage": @100,
        @"oscillating": @YES,
        @"percentage_step": @(100.0 / 3.0),
        @"icon": @"mdi:fan"
    }];
}

+ (HAEntity *)fanEntityOff {
    return [self entityWithId:@"fan.office"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Office Fan",
        @"percentage": @0,
        @"oscillating": @NO,
        @"icon": @"mdi:fan-off"
    }];
}

#pragma mark - Vacuum (4 variants)

+ (HAEntity *)vacuumDocked {
    return [self entityWithId:@"vacuum.roborock"
                        state:@"docked"
                   attributes:@{
        @"friendly_name": @"Roborock",
        @"battery_level": @100,
        @"status": @"Docked",
        @"icon": @"mdi:robot-vacuum"
    }];
}

+ (HAEntity *)vacuumCleaning {
    return [self entityWithId:@"vacuum.roborock"
                        state:@"cleaning"
                   attributes:@{
        @"friendly_name": @"Roborock",
        @"battery_level": @65,
        @"status": @"Cleaning",
        @"fan_speed": @"balanced",
        @"icon": @"mdi:robot-vacuum"
    }];
}

+ (HAEntity *)vacuumReturning {
    return [self entityWithId:@"vacuum.roborock"
                        state:@"returning"
                   attributes:@{
        @"friendly_name": @"Roborock",
        @"battery_level": @20,
        @"status": @"Returning to dock",
        @"icon": @"mdi:robot-vacuum"
    }];
}

+ (HAEntity *)vacuumError {
    return [self entityWithId:@"vacuum.roborock"
                        state:@"error"
                   attributes:@{
        @"friendly_name": @"Roborock",
        @"battery_level": @45,
        @"status": @"Error",
        @"icon": @"mdi:robot-vacuum-alert"
    }];
}

#pragma mark - Humidifier (2 variants)

+ (HAEntity *)humidifierOn {
    return [self entityWithId:@"humidifier.bedroom"
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
}

+ (HAEntity *)humidifierOff {
    return [self entityWithId:@"humidifier.bedroom"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Bedroom Humidifier",
        @"min_humidity": @30,
        @"max_humidity": @80,
        @"icon": @"mdi:air-humidifier-off"
    }];
}

#pragma mark - Timer (3 variants)

+ (HAEntity *)timerActive {
    return [self entityWithId:@"timer.laundry"
                        state:@"active"
                   attributes:@{
        @"friendly_name": @"Laundry",
        @"duration": @"0:10:00",
        @"remaining": @"0:05:23",
        @"icon": @"mdi:timer-outline"
    }];
}

+ (HAEntity *)timerPaused {
    return [self entityWithId:@"timer.oven"
                        state:@"paused"
                   attributes:@{
        @"friendly_name": @"Oven",
        @"duration": @"0:30:00",
        @"remaining": @"0:15:00",
        @"icon": @"mdi:timer-pause"
    }];
}

+ (HAEntity *)timerIdle {
    return [self entityWithId:@"timer.meditation"
                        state:@"idle"
                   attributes:@{
        @"friendly_name": @"Meditation",
        @"duration": @"0:10:00",
        @"icon": @"mdi:timer-outline"
    }];
}

#pragma mark - Input Text (2 variants)

+ (HAEntity *)inputTextWithValue {
    return [self entityWithId:@"input_text.greeting"
                        state:@"Hello World"
                   attributes:@{
        @"friendly_name": @"Greeting",
        @"mode": @"text",
        @"min": @0,
        @"max": @100,
        @"icon": @"mdi:form-textbox"
    }];
}

+ (HAEntity *)inputTextEmpty {
    return [self entityWithId:@"input_text.notes"
                        state:@""
                   attributes:@{
        @"friendly_name": @"Notes",
        @"mode": @"text",
        @"min": @0,
        @"max": @100,
        @"icon": @"mdi:form-textbox"
    }];
}

#pragma mark - Input DateTime (3 variants)

+ (HAEntity *)inputDateTimeDate {
    return [self entityWithId:@"input_datetime.vacation_start"
                        state:@"2026-01-15"
                   attributes:@{
        @"friendly_name": @"Vacation Start",
        @"has_date": @YES,
        @"has_time": @NO,
        @"year": @2026,
        @"month": @1,
        @"day": @15,
        @"icon": @"mdi:calendar"
    }];
}

+ (HAEntity *)inputDateTimeTime {
    return [self entityWithId:@"input_datetime.morning_alarm"
                        state:@"14:30:00"
                   attributes:@{
        @"friendly_name": @"Morning Alarm",
        @"has_date": @NO,
        @"has_time": @YES,
        @"hour": @14,
        @"minute": @30,
        @"second": @0,
        @"icon": @"mdi:clock-outline"
    }];
}

+ (HAEntity *)inputDateTimeBoth {
    return [self entityWithId:@"input_datetime.appointment"
                        state:@"2026-01-15 14:30:00"
                   attributes:@{
        @"friendly_name": @"Appointment",
        @"has_date": @YES,
        @"has_time": @YES,
        @"year": @2026,
        @"month": @1,
        @"day": @15,
        @"hour": @14,
        @"minute": @30,
        @"second": @0,
        @"icon": @"mdi:calendar-clock"
    }];
}

#pragma mark - Camera (2 variants)

+ (HAEntity *)cameraStreaming {
    return [self entityWithId:@"camera.patio"
                        state:@"idle"
                   attributes:@{
        @"friendly_name": @"Patio",
        @"entity_picture": @"/api/camera_proxy/camera.patio",
        @"icon": @"mdi:cctv"
    }];
}

+ (HAEntity *)cameraUnavailable {
    return [self entityWithId:@"camera.driveway"
                        state:@"unavailable"
                   attributes:@{
        @"friendly_name": @"Driveway",
        @"icon": @"mdi:cctv"
    }];
}

#pragma mark - Scene (2 variants)

+ (HAEntity *)sceneDefault {
    return [self entityWithId:@"scene.movie_night"
                        state:@"off"
                   attributes:@{
        @"friendly_name": @"Movie Night",
        @"icon": @"mdi:movie-open"
    }];
}

+ (HAEntity *)sceneActivated {
    return [self entityWithId:@"scene.good_morning"
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"Good Morning",
        @"icon": @"mdi:weather-sunny"
    }];
}

#pragma mark - Clock Weather (2 variants)

+ (HAEntity *)clockWeatherSunny {
    return [self entityWithId:@"weather.clock_weather_home"
                        state:@"sunny"
                   attributes:@{
        @"friendly_name": @"Home",
        @"temperature": @22,
        @"humidity": @57,
        @"condition": @"sunny",
        @"pressure": @1015,
        @"wind_speed": @10,
        @"wind_bearing": @"E",
        @"temperature_unit": @"\u00B0C",
        @"forecast": [self forecastArrayForDays:5],
        @"icon": @"mdi:weather-sunny"
    }];
}

+ (HAEntity *)clockWeatherCloudy {
    return [self entityWithId:@"weather.clock_weather_home"
                        state:@"cloudy"
                   attributes:@{
        @"friendly_name": @"Home",
        @"temperature": @8,
        @"humidity": @85,
        @"condition": @"cloudy",
        @"pressure": @1005,
        @"wind_speed": @18,
        @"wind_bearing": @"W",
        @"temperature_unit": @"\u00B0C",
        @"forecast": [self forecastArrayForDays:5],
        @"icon": @"mdi:weather-cloudy"
    }];
}

#pragma mark - Showcase: Light (10 variants)

+ (HAEntity *)lightScBasicOn {
    return [self entityWithId:@"light.sc_basic_on" state:@"on" attributes:@{
        @"friendly_name": @"Basic On", @"brightness": @204, @"color_mode": @"brightness",
        @"supported_color_modes": @[@"brightness"], @"icon": @"mdi:lightbulb"}];
}

+ (HAEntity *)lightScBasicOff {
    return [self entityWithId:@"light.sc_basic_off" state:@"off" attributes:@{
        @"friendly_name": @"Basic Off", @"supported_color_modes": @[@"brightness"],
        @"icon": @"mdi:lightbulb-outline"}];
}

+ (HAEntity *)lightScColorTemp {
    return [self entityWithId:@"light.sc_color_temp" state:@"on" attributes:@{
        @"friendly_name": @"Color Temp", @"brightness": @153, @"color_temp_kelvin": @3000,
        @"min_color_temp_kelvin": @2000, @"max_color_temp_kelvin": @6500,
        @"color_mode": @"color_temp", @"supported_color_modes": @[@"color_temp"],
        @"icon": @"mdi:ceiling-light"}];
}

+ (HAEntity *)lightScRgb {
    return [self entityWithId:@"light.sc_rgb" state:@"on" attributes:@{
        @"friendly_name": @"RGB Blue", @"brightness": @255, @"hs_color": @[@240, @100],
        @"rgb_color": @[@0, @0, @255], @"color_mode": @"hs",
        @"supported_color_modes": @[@"hs"], @"icon": @"mdi:led-strip-variant"}];
}

+ (HAEntity *)lightScRgbw {
    return [self entityWithId:@"light.sc_rgbw" state:@"on" attributes:@{
        @"friendly_name": @"RGBW", @"brightness": @200, @"rgbw_color": @[@255, @0, @0, @128],
        @"color_mode": @"rgbw", @"supported_color_modes": @[@"rgbw"],
        @"icon": @"mdi:led-strip"}];
}

+ (HAEntity *)lightScAllModes {
    return [self entityWithId:@"light.sc_all_modes" state:@"on" attributes:@{
        @"friendly_name": @"All Modes", @"brightness": @191, @"color_temp_kelvin": @4000,
        @"min_color_temp_kelvin": @2000, @"max_color_temp_kelvin": @6500,
        @"color_mode": @"color_temp",
        @"supported_color_modes": @[@"brightness", @"color_temp", @"hs"],
        @"icon": @"mdi:lightbulb-multiple"}];
}

+ (HAEntity *)lightScEffect {
    return [self entityWithId:@"light.sc_effect" state:@"on" attributes:@{
        @"friendly_name": @"With Effect", @"brightness": @255, @"effect": @"rainbow",
        @"effect_list": @[@"rainbow", @"strobe", @"colorloop", @"none"],
        @"color_mode": @"rgb", @"supported_color_modes": @[@"rgb"],
        @"icon": @"mdi:lava-lamp"}];
}

+ (HAEntity *)lightScBrightnessOnly {
    return [self entityWithId:@"light.sc_brightness_only" state:@"on" attributes:@{
        @"friendly_name": @"Brightness Only", @"brightness": @102,
        @"color_mode": @"brightness", @"supported_color_modes": @[@"brightness"],
        @"icon": @"mdi:desk-lamp"}];
}

+ (HAEntity *)lightScDimmedLow {
    return [self entityWithId:@"light.sc_dimmed_low" state:@"on" attributes:@{
        @"friendly_name": @"Dimmed 2%", @"brightness": @5,
        @"color_mode": @"brightness", @"supported_color_modes": @[@"brightness"],
        @"icon": @"mdi:lightbulb-on-10"}];
}

+ (HAEntity *)lightScMaxBright {
    return [self entityWithId:@"light.sc_max_bright" state:@"on" attributes:@{
        @"friendly_name": @"Max Bright", @"brightness": @255,
        @"color_mode": @"brightness", @"supported_color_modes": @[@"brightness"],
        @"icon": @"mdi:lightbulb-on"}];
}

#pragma mark - Showcase: Climate (8 variants)

+ (HAEntity *)climateScHeating {
    return [self entityWithId:@"climate.sc_heating" state:@"heat" attributes:@{
        @"friendly_name": @"Heating", @"temperature": @22, @"current_temperature": @20,
        @"hvac_action": @"heating", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"}];
}

+ (HAEntity *)climateScCooling {
    return [self entityWithId:@"climate.sc_cooling" state:@"cool" attributes:@{
        @"friendly_name": @"Cooling", @"temperature": @24, @"current_temperature": @26,
        @"hvac_action": @"cooling", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"}];
}

+ (HAEntity *)climateScHeatCool {
    return [self entityWithId:@"climate.sc_heat_cool" state:@"heat_cool" attributes:@{
        @"friendly_name": @"Heat/Cool", @"target_temp_high": @24, @"target_temp_low": @20,
        @"current_temperature": @22, @"hvac_action": @"idle",
        @"hvac_modes": @[@"off", @"heat", @"cool", @"heat_cool"],
        @"min_temp": @7, @"max_temp": @35, @"temperature_unit": @"\u00B0C"}];
}

+ (HAEntity *)climateScPresets {
    return [self entityWithId:@"climate.sc_presets" state:@"heat" attributes:@{
        @"friendly_name": @"With Presets", @"temperature": @22, @"current_temperature": @20.5,
        @"hvac_action": @"heating", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"preset_mode": @"eco", @"preset_modes": @[@"eco", @"comfort", @"away", @"boost", @"sleep"],
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"}];
}

+ (HAEntity *)climateScFan {
    return [self entityWithId:@"climate.sc_fan" state:@"cool" attributes:@{
        @"friendly_name": @"With Fan", @"temperature": @24, @"current_temperature": @26,
        @"hvac_action": @"cooling", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"fan_mode": @"medium", @"fan_modes": @[@"auto", @"low", @"medium", @"high"],
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @1,
        @"temperature_unit": @"\u00B0C"}];
}

+ (HAEntity *)climateScSwing {
    return [self entityWithId:@"climate.sc_swing" state:@"heat" attributes:@{
        @"friendly_name": @"With Swing", @"temperature": @21, @"current_temperature": @19,
        @"hvac_action": @"heating", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"swing_mode": @"vertical",
        @"swing_modes": @[@"on", @"off", @"vertical", @"horizontal", @"both"],
        @"min_temp": @7, @"max_temp": @35, @"temperature_unit": @"\u00B0C"}];
}

+ (HAEntity *)climateScAll {
    return [self entityWithId:@"climate.sc_all" state:@"heat" attributes:@{
        @"friendly_name": @"All Features", @"temperature": @22, @"current_temperature": @21,
        @"hvac_action": @"heating", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto", @"dry", @"fan_only"],
        @"preset_mode": @"comfort", @"preset_modes": @[@"eco", @"comfort", @"away", @"boost"],
        @"fan_mode": @"auto", @"fan_modes": @[@"auto", @"low", @"medium", @"high"],
        @"swing_mode": @"off", @"swing_modes": @[@"on", @"off", @"vertical", @"horizontal"],
        @"aux_heat": @YES, @"target_humidity": @50,
        @"min_temp": @7, @"max_temp": @35, @"target_temp_step": @0.5,
        @"temperature_unit": @"\u00B0C"}];
}

+ (HAEntity *)climateScOff {
    return [self entityWithId:@"climate.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Off", @"current_temperature": @18,
        @"hvac_action": @"off", @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
        @"min_temp": @7, @"max_temp": @35, @"temperature_unit": @"\u00B0C"}];
}

#pragma mark - Showcase: Cover (10 variants)

+ (HAEntity *)coverScPosition {
    return [self entityWithId:@"cover.sc_position" state:@"open" attributes:@{
        @"friendly_name": @"Position Only", @"current_position": @50,
        @"supported_features": @15, @"device_class": @"shutter"}];
}

+ (HAEntity *)coverScTilt {
    return [self entityWithId:@"cover.sc_tilt" state:@"open" attributes:@{
        @"friendly_name": @"Tilt Only", @"current_position": @100, @"current_tilt_position": @30,
        @"supported_features": @255, @"device_class": @"blind"}];
}

+ (HAEntity *)coverScPosTilt {
    return [self entityWithId:@"cover.sc_pos_tilt" state:@"open" attributes:@{
        @"friendly_name": @"Position+Tilt", @"current_position": @75, @"current_tilt_position": @60,
        @"supported_features": @255, @"device_class": @"blind"}];
}

+ (HAEntity *)coverScNoPosition {
    return [self entityWithId:@"cover.sc_no_position" state:@"open" attributes:@{
        @"friendly_name": @"No Position", @"supported_features": @3, @"device_class": @"awning"}];
}

+ (HAEntity *)coverScOpening {
    return [self entityWithId:@"cover.sc_opening" state:@"opening" attributes:@{
        @"friendly_name": @"Opening", @"current_position": @65,
        @"supported_features": @15, @"device_class": @"shutter"}];
}

+ (HAEntity *)coverScClosed {
    return [self entityWithId:@"cover.sc_closed" state:@"closed" attributes:@{
        @"friendly_name": @"Closed", @"current_position": @0,
        @"supported_features": @15, @"device_class": @"shutter"}];
}

+ (HAEntity *)coverScBlind {
    return [self entityWithId:@"cover.sc_blind" state:@"open" attributes:@{
        @"friendly_name": @"Blind", @"current_position": @80, @"current_tilt_position": @45,
        @"supported_features": @255, @"device_class": @"blind"}];
}

+ (HAEntity *)coverScGarage {
    return [self entityWithId:@"cover.sc_garage" state:@"closed" attributes:@{
        @"friendly_name": @"Garage", @"supported_features": @3, @"device_class": @"garage",
        @"icon": @"mdi:garage"}];
}

+ (HAEntity *)coverScDoor {
    return [self entityWithId:@"cover.sc_door" state:@"closed" attributes:@{
        @"friendly_name": @"Door", @"supported_features": @3, @"device_class": @"door",
        @"icon": @"mdi:gate"}];
}

+ (HAEntity *)coverScShutter {
    return [self entityWithId:@"cover.sc_shutter" state:@"open" attributes:@{
        @"friendly_name": @"Shutter", @"current_position": @100,
        @"supported_features": @15, @"device_class": @"shutter"}];
}

#pragma mark - Showcase: Lock (5 variants)

+ (HAEntity *)lockScLocked {
    return [self entityWithId:@"lock.sc_locked" state:@"locked" attributes:@{
        @"friendly_name": @"Locked", @"icon": @"mdi:lock"}];
}

+ (HAEntity *)lockScUnlocked {
    return [self entityWithId:@"lock.sc_unlocked" state:@"unlocked" attributes:@{
        @"friendly_name": @"Unlocked", @"icon": @"mdi:lock-open"}];
}

+ (HAEntity *)lockScJammed {
    return [self entityWithId:@"lock.sc_jammed" state:@"jammed" attributes:@{
        @"friendly_name": @"Jammed", @"icon": @"mdi:lock-alert"}];
}

+ (HAEntity *)lockScCode {
    return [self entityWithId:@"lock.sc_code" state:@"locked" attributes:@{
        @"friendly_name": @"With Code", @"code_format": @"^\\d{4}$",
        @"icon": @"mdi:lock-smart"}];
}

+ (HAEntity *)lockScLocking {
    return [self entityWithId:@"lock.sc_locking" state:@"locking" attributes:@{
        @"friendly_name": @"Locking", @"icon": @"mdi:lock-clock"}];
}

#pragma mark - Showcase: Media Player (6 variants)

+ (HAEntity *)mediaPlayerScFull {
    return [self entityWithId:@"media_player.sc_full" state:@"playing" attributes:@{
        @"friendly_name": @"Full Player", @"media_title": @"Interstellar",
        @"media_artist": @"Hans Zimmer", @"media_album_name": @"Soundtrack",
        @"media_content_type": @"music", @"entity_picture": @"/local/interstellar.jpg",
        @"source": @"Spotify", @"source_list": @[@"TV", @"Spotify", @"AirPlay", @"Bluetooth"],
        @"volume_level": @0.65, @"is_volume_muted": @NO,
        @"shuffle": @YES, @"repeat": @"all",
        @"media_duration": @240, @"media_position": @120,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];
}

+ (HAEntity *)mediaPlayerScPaused {
    return [self entityWithId:@"media_player.sc_paused" state:@"paused" attributes:@{
        @"friendly_name": @"Paused", @"media_title": @"Yesterday",
        @"media_artist": @"The Beatles", @"volume_level": @0.5, @"is_volume_muted": @NO,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];
}

+ (HAEntity *)mediaPlayerScMuted {
    return [self entityWithId:@"media_player.sc_muted" state:@"playing" attributes:@{
        @"friendly_name": @"Muted", @"media_title": @"Focus Beats",
        @"media_artist": @"Lo-Fi Radio", @"volume_level": @0.7, @"is_volume_muted": @YES,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];
}

+ (HAEntity *)mediaPlayerScIdle {
    return [self entityWithId:@"media_player.sc_idle" state:@"idle" attributes:@{
        @"friendly_name": @"Idle", @"volume_level": @0.3, @"is_volume_muted": @NO,
        @"supported_features": @152461, @"icon": @"mdi:speaker"}];
}

+ (HAEntity *)mediaPlayerScOff {
    return [self entityWithId:@"media_player.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Off", @"volume_level": @0.5, @"is_volume_muted": @NO,
        @"supported_features": @152461, @"icon": @"mdi:speaker-off"}];
}

+ (HAEntity *)mediaPlayerScNoSource {
    return [self entityWithId:@"media_player.sc_no_source" state:@"playing" attributes:@{
        @"friendly_name": @"No Source", @"media_title": @"Radio Stream",
        @"media_artist": @"BBC Radio 4", @"volume_level": @0.4, @"is_volume_muted": @NO,
        @"supported_features": @21437, @"icon": @"mdi:radio"}];
}

#pragma mark - Showcase: Alarm (7 variants)

+ (HAEntity *)alarmScDisarmed {
    return [self entityWithId:@"alarm_control_panel.sc_disarmed" state:@"disarmed" attributes:@{
        @"friendly_name": @"Disarmed", @"code_arm_required": @YES,
        @"code_format": @"number", @"supported_features": @31, @"icon": @"mdi:shield-check"}];
}

+ (HAEntity *)alarmScHome {
    return [self entityWithId:@"alarm_control_panel.sc_home" state:@"armed_home" attributes:@{
        @"friendly_name": @"Armed Home", @"code_arm_required": @YES,
        @"supported_features": @31, @"icon": @"mdi:shield-home"}];
}

+ (HAEntity *)alarmScAway {
    return [self entityWithId:@"alarm_control_panel.sc_away" state:@"armed_away" attributes:@{
        @"friendly_name": @"Armed Away", @"code_arm_required": @YES,
        @"supported_features": @31, @"icon": @"mdi:shield-lock"}];
}

+ (HAEntity *)alarmScNight {
    return [self entityWithId:@"alarm_control_panel.sc_night" state:@"armed_night" attributes:@{
        @"friendly_name": @"Night", @"code_arm_required": @YES, @"code_format": @"number",
        @"supported_features": @31, @"icon": @"mdi:shield-moon"}];
}

+ (HAEntity *)alarmScVacation {
    return [self entityWithId:@"alarm_control_panel.sc_vacation" state:@"armed_vacation" attributes:@{
        @"friendly_name": @"Vacation", @"code_arm_required": @NO,
        @"supported_features": @31, @"icon": @"mdi:shield-airplane"}];
}

+ (HAEntity *)alarmScTriggered {
    return [self entityWithId:@"alarm_control_panel.sc_triggered" state:@"triggered" attributes:@{
        @"friendly_name": @"TRIGGERED", @"code_arm_required": @YES,
        @"supported_features": @31, @"icon": @"mdi:bell-ring"}];
}

+ (HAEntity *)alarmScNoCode {
    return [self entityWithId:@"alarm_control_panel.sc_no_code" state:@"disarmed" attributes:@{
        @"friendly_name": @"No Code", @"code_arm_required": @NO,
        @"supported_features": @31, @"icon": @"mdi:shield-off"}];
}

#pragma mark - Showcase: Fan (5 variants)

+ (HAEntity *)fanScBasic {
    return [self entityWithId:@"fan.sc_basic" state:@"on" attributes:@{
        @"friendly_name": @"Basic 50%", @"percentage": @50,
        @"percentage_step": @(100.0/3.0), @"icon": @"mdi:fan"}];
}

+ (HAEntity *)fanScPresets {
    return [self entityWithId:@"fan.sc_presets" state:@"on" attributes:@{
        @"friendly_name": @"With Presets", @"percentage": @67,
        @"preset_mode": @"nature", @"preset_modes": @[@"auto", @"sleep", @"nature", @"baby"],
        @"percentage_step": @(100.0/6.0), @"icon": @"mdi:fan"}];
}

+ (HAEntity *)fanScOscillating {
    return [self entityWithId:@"fan.sc_oscillating" state:@"on" attributes:@{
        @"friendly_name": @"Oscillating", @"percentage": @75, @"oscillating": @YES,
        @"direction": @"forward", @"percentage_step": @(100.0/4.0), @"icon": @"mdi:fan"}];
}

+ (HAEntity *)fanScReverse {
    return [self entityWithId:@"fan.sc_reverse" state:@"on" attributes:@{
        @"friendly_name": @"Reverse", @"percentage": @33, @"oscillating": @NO,
        @"direction": @"reverse", @"percentage_step": @(100.0/3.0),
        @"icon": @"mdi:ceiling-fan"}];
}

+ (HAEntity *)fanScOff {
    return [self entityWithId:@"fan.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Off", @"percentage": @0, @"icon": @"mdi:fan-off"}];
}

#pragma mark - Showcase: Sensor (10 variants)

+ (HAEntity *)sensorScTemperature {
    return [self entityWithId:@"sensor.sc_temperature" state:@"22.5" attributes:@{
        @"friendly_name": @"Temperature", @"unit_of_measurement": @"\u00B0C",
        @"device_class": @"temperature", @"state_class": @"measurement", @"icon": @"mdi:thermometer"}];
}

+ (HAEntity *)sensorScHumidity {
    return [self entityWithId:@"sensor.sc_humidity" state:@"65" attributes:@{
        @"friendly_name": @"Humidity", @"unit_of_measurement": @"%",
        @"device_class": @"humidity", @"state_class": @"measurement", @"icon": @"mdi:water-percent"}];
}

+ (HAEntity *)sensorScPower {
    return [self entityWithId:@"sensor.sc_power" state:@"1200" attributes:@{
        @"friendly_name": @"Power", @"unit_of_measurement": @"W",
        @"device_class": @"power", @"state_class": @"measurement", @"icon": @"mdi:flash"}];
}

+ (HAEntity *)sensorScEnergy {
    return [self entityWithId:@"sensor.sc_energy" state:@"45.2" attributes:@{
        @"friendly_name": @"Energy", @"unit_of_measurement": @"kWh",
        @"device_class": @"energy", @"state_class": @"total_increasing", @"icon": @"mdi:lightning-bolt"}];
}

+ (HAEntity *)sensorScBattery {
    return [self entityWithId:@"sensor.sc_battery" state:@"78" attributes:@{
        @"friendly_name": @"Battery", @"unit_of_measurement": @"%",
        @"device_class": @"battery", @"icon": @"mdi:battery-70"}];
}

+ (HAEntity *)sensorScIlluminance {
    return [self entityWithId:@"sensor.sc_illuminance" state:@"350" attributes:@{
        @"friendly_name": @"Illuminance", @"unit_of_measurement": @"lx",
        @"device_class": @"illuminance", @"icon": @"mdi:brightness-5"}];
}

+ (HAEntity *)sensorScPressure {
    return [self entityWithId:@"sensor.sc_pressure" state:@"1013" attributes:@{
        @"friendly_name": @"Pressure", @"unit_of_measurement": @"hPa",
        @"device_class": @"pressure", @"state_class": @"measurement", @"icon": @"mdi:gauge"}];
}

+ (HAEntity *)sensorScGas {
    return [self entityWithId:@"sensor.sc_gas" state:@"2.3" attributes:@{
        @"friendly_name": @"Gas", @"unit_of_measurement": @"m\u00B3",
        @"device_class": @"gas", @"state_class": @"total_increasing", @"icon": @"mdi:meter-gas"}];
}

+ (HAEntity *)sensorScMonetary {
    return [self entityWithId:@"sensor.sc_monetary" state:@"12.50" attributes:@{
        @"friendly_name": @"Cost", @"unit_of_measurement": @"\u00A3",
        @"device_class": @"monetary", @"state_class": @"total", @"icon": @"mdi:currency-gbp"}];
}

+ (HAEntity *)sensorScText {
    return [self entityWithId:@"sensor.sc_text" state:@"Running" attributes:@{
        @"friendly_name": @"Status", @"icon": @"mdi:state-machine"}];
}

#pragma mark - Showcase: Binary Sensor (12 variants)

+ (HAEntity *)binarySensorScDoorOpen {
    return [self entityWithId:@"binary_sensor.sc_door_open" state:@"on" attributes:@{
        @"friendly_name": @"Door Open", @"device_class": @"door", @"icon": @"mdi:door-open"}];
}

+ (HAEntity *)binarySensorScDoorClosed {
    return [self entityWithId:@"binary_sensor.sc_door_closed" state:@"off" attributes:@{
        @"friendly_name": @"Door Closed", @"device_class": @"door", @"icon": @"mdi:door-closed"}];
}

+ (HAEntity *)binarySensorScMotionOn {
    return [self entityWithId:@"binary_sensor.sc_motion_on" state:@"on" attributes:@{
        @"friendly_name": @"Motion Detected", @"device_class": @"motion", @"icon": @"mdi:motion-sensor"}];
}

+ (HAEntity *)binarySensorScMotionOff {
    return [self entityWithId:@"binary_sensor.sc_motion_off" state:@"off" attributes:@{
        @"friendly_name": @"Motion Clear", @"device_class": @"motion", @"icon": @"mdi:motion-sensor"}];
}

+ (HAEntity *)binarySensorScSmoke {
    return [self entityWithId:@"binary_sensor.sc_smoke" state:@"on" attributes:@{
        @"friendly_name": @"Smoke!", @"device_class": @"smoke", @"icon": @"mdi:smoke-detector-alert"}];
}

+ (HAEntity *)binarySensorScMoisture {
    return [self entityWithId:@"binary_sensor.sc_moisture" state:@"on" attributes:@{
        @"friendly_name": @"Moisture!", @"device_class": @"moisture", @"icon": @"mdi:water-alert"}];
}

+ (HAEntity *)binarySensorScWindow {
    return [self entityWithId:@"binary_sensor.sc_window" state:@"on" attributes:@{
        @"friendly_name": @"Window Open", @"device_class": @"window", @"icon": @"mdi:window-open"}];
}

+ (HAEntity *)binarySensorScOccupancy {
    return [self entityWithId:@"binary_sensor.sc_occupancy" state:@"on" attributes:@{
        @"friendly_name": @"Occupied", @"device_class": @"occupancy", @"icon": @"mdi:account"}];
}

+ (HAEntity *)binarySensorScPresence {
    return [self entityWithId:@"binary_sensor.sc_presence" state:@"on" attributes:@{
        @"friendly_name": @"Present", @"device_class": @"presence", @"icon": @"mdi:home-account"}];
}

+ (HAEntity *)binarySensorScBatteryLow {
    return [self entityWithId:@"binary_sensor.sc_battery_low" state:@"on" attributes:@{
        @"friendly_name": @"Battery Low", @"device_class": @"battery", @"icon": @"mdi:battery-alert"}];
}

+ (HAEntity *)binarySensorScPlug {
    return [self entityWithId:@"binary_sensor.sc_plug" state:@"on" attributes:@{
        @"friendly_name": @"Plug", @"device_class": @"plug", @"icon": @"mdi:power-plug"}];
}

+ (HAEntity *)binarySensorScGeneric {
    return [self entityWithId:@"binary_sensor.sc_generic" state:@"on" attributes:@{
        @"friendly_name": @"Generic On", @"icon": @"mdi:check-circle"}];
}

#pragma mark - Showcase: Vacuum (4 variants)

+ (HAEntity *)vacuumScDocked {
    return [self entityWithId:@"vacuum.sc_docked" state:@"docked" attributes:@{
        @"friendly_name": @"Docked", @"battery_level": @80, @"status": @"Docked",
        @"icon": @"mdi:robot-vacuum"}];
}

+ (HAEntity *)vacuumScCleaning {
    return [self entityWithId:@"vacuum.sc_cleaning" state:@"cleaning" attributes:@{
        @"friendly_name": @"Cleaning", @"battery_level": @65, @"status": @"Cleaning",
        @"fan_speed": @"turbo", @"fan_speed_list": @[@"quiet", @"balanced", @"turbo", @"max"],
        @"icon": @"mdi:robot-vacuum"}];
}

+ (HAEntity *)vacuumScReturning {
    return [self entityWithId:@"vacuum.sc_returning" state:@"returning" attributes:@{
        @"friendly_name": @"Returning", @"battery_level": @20, @"status": @"Returning to dock",
        @"icon": @"mdi:robot-vacuum"}];
}

+ (HAEntity *)vacuumScError {
    return [self entityWithId:@"vacuum.sc_error" state:@"error" attributes:@{
        @"friendly_name": @"Error", @"battery_level": @45, @"status": @"Stuck on cable",
        @"icon": @"mdi:robot-vacuum-alert"}];
}

#pragma mark - Showcase: Humidifier (3 variants)

+ (HAEntity *)humidifierScOn {
    return [self entityWithId:@"humidifier.sc_on" state:@"on" attributes:@{
        @"friendly_name": @"Normal", @"humidity": @60, @"current_humidity": @45,
        @"min_humidity": @30, @"max_humidity": @80,
        @"mode": @"normal", @"available_modes": @[@"normal", @"eco", @"sleep"],
        @"icon": @"mdi:air-humidifier"}];
}

+ (HAEntity *)humidifierScEco {
    return [self entityWithId:@"humidifier.sc_eco" state:@"on" attributes:@{
        @"friendly_name": @"Eco Mode", @"humidity": @50, @"current_humidity": @42,
        @"min_humidity": @30, @"max_humidity": @80,
        @"mode": @"eco", @"available_modes": @[@"normal", @"eco", @"sleep"],
        @"icon": @"mdi:air-humidifier"}];
}

+ (HAEntity *)humidifierScOff {
    return [self entityWithId:@"humidifier.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Off", @"min_humidity": @30, @"max_humidity": @80,
        @"icon": @"mdi:air-humidifier-off"}];
}

#pragma mark - Showcase: Input Boolean (2 variants)

+ (HAEntity *)inputBooleanScOn {
    return [self entityWithId:@"input_boolean.sc_on" state:@"on" attributes:@{
        @"friendly_name": @"Guest Mode", @"icon": @"mdi:account-group"}];
}

+ (HAEntity *)inputBooleanScOff {
    return [self entityWithId:@"input_boolean.sc_off" state:@"off" attributes:@{
        @"friendly_name": @"Sleep Mode", @"icon": @"mdi:sleep"}];
}

#pragma mark - Showcase: Input Number (2 variants)

+ (HAEntity *)inputNumberScSlider {
    return [self entityWithId:@"input_number.sc_slider" state:@"42" attributes:@{
        @"friendly_name": @"Slider", @"min": @0, @"max": @100, @"step": @1,
        @"mode": @"slider", @"unit_of_measurement": @"%", @"icon": @"mdi:percent"}];
}

+ (HAEntity *)inputNumberScBox {
    return [self entityWithId:@"input_number.sc_box" state:@"123.5" attributes:@{
        @"friendly_name": @"Box", @"min": @0, @"max": @1000, @"step": @0.1,
        @"mode": @"box", @"unit_of_measurement": @"W", @"icon": @"mdi:flash"}];
}

#pragma mark - Showcase: Input Select (1 variant)

+ (HAEntity *)inputSelectSc {
    return [self entityWithId:@"input_select.sc" state:@"Netflix" attributes:@{
        @"friendly_name": @"App", @"options": @[@"YouTube", @"Netflix", @"Plex", @"Disney+", @"BBC"],
        @"icon": @"mdi:application"}];
}

#pragma mark - Showcase: Input Text (2 variants)

+ (HAEntity *)inputTextScText {
    return [self entityWithId:@"input_text.sc_text" state:@"Hello World" attributes:@{
        @"friendly_name": @"Text", @"mode": @"text", @"min": @0, @"max": @100,
        @"icon": @"mdi:form-textbox"}];
}

+ (HAEntity *)inputTextScPassword {
    return [self entityWithId:@"input_text.sc_password" state:@"secret123" attributes:@{
        @"friendly_name": @"Password", @"mode": @"password", @"min": @0, @"max": @64,
        @"icon": @"mdi:form-textbox-password"}];
}

#pragma mark - Showcase: Input DateTime (3 variants)

+ (HAEntity *)inputDateTimeScDate {
    return [self entityWithId:@"input_datetime.sc_date" state:@"2026-03-15" attributes:@{
        @"friendly_name": @"Date", @"has_date": @YES, @"has_time": @NO,
        @"year": @2026, @"month": @3, @"day": @15, @"icon": @"mdi:calendar"}];
}

+ (HAEntity *)inputDateTimeScTime {
    return [self entityWithId:@"input_datetime.sc_time" state:@"07:30:00" attributes:@{
        @"friendly_name": @"Time", @"has_date": @NO, @"has_time": @YES,
        @"hour": @7, @"minute": @30, @"second": @0, @"icon": @"mdi:clock-outline"}];
}

+ (HAEntity *)inputDateTimeScBoth {
    return [self entityWithId:@"input_datetime.sc_both" state:@"2026-03-15 14:30:00" attributes:@{
        @"friendly_name": @"Date+Time", @"has_date": @YES, @"has_time": @YES,
        @"year": @2026, @"month": @3, @"day": @15, @"hour": @14, @"minute": @30, @"second": @0,
        @"icon": @"mdi:calendar-clock"}];
}

#pragma mark - Showcase: Counter (1 variant)

+ (HAEntity *)counterSc {
    return [self entityWithId:@"counter.sc" state:@"5" attributes:@{
        @"friendly_name": @"Counter", @"step": @1, @"minimum": @0, @"maximum": @100,
        @"icon": @"mdi:counter"}];
}

#pragma mark - Showcase: Timer (3 variants)

+ (HAEntity *)timerScActive {
    return [self entityWithId:@"timer.sc_active" state:@"active" attributes:@{
        @"friendly_name": @"Active", @"duration": @"0:05:00", @"remaining": @"0:03:22",
        @"icon": @"mdi:timer-outline"}];
}

+ (HAEntity *)timerScPaused {
    return [self entityWithId:@"timer.sc_paused" state:@"paused" attributes:@{
        @"friendly_name": @"Paused", @"duration": @"0:30:00", @"remaining": @"0:12:45",
        @"icon": @"mdi:timer-pause"}];
}

+ (HAEntity *)timerScIdle {
    return [self entityWithId:@"timer.sc_idle" state:@"idle" attributes:@{
        @"friendly_name": @"Idle", @"duration": @"0:10:00", @"icon": @"mdi:timer-outline"}];
}

#pragma mark - Showcase: Person (3 variants)

+ (HAEntity *)personScHome {
    return [self entityWithId:@"person.sc_home" state:@"home" attributes:@{
        @"friendly_name": @"Home", @"icon": @"mdi:account"}];
}

+ (HAEntity *)personScAway {
    return [self entityWithId:@"person.sc_away" state:@"not_home" attributes:@{
        @"friendly_name": @"Away", @"icon": @"mdi:account-off"}];
}

+ (HAEntity *)personScZone {
    return [self entityWithId:@"person.sc_zone" state:@"Work" attributes:@{
        @"friendly_name": @"At Zone", @"latitude": @51.507, @"longitude": @-0.127,
        @"gps_accuracy": @15, @"icon": @"mdi:account"}];
}

#pragma mark - Showcase: Scene & Script (2 variants)

+ (HAEntity *)sceneSc {
    return [self entityWithId:@"scene.sc" state:@"off" attributes:@{
        @"friendly_name": @"Movie Night", @"icon": @"mdi:movie-open"}];
}

+ (HAEntity *)scriptSc {
    return [self entityWithId:@"script.sc" state:@"on" attributes:@{
        @"friendly_name": @"Bedtime", @"current": @1, @"last_triggered": @"2026-03-01T22:00:00Z",
        @"icon": @"mdi:script-text"}];
}

#pragma mark - Showcase: Automation (1 variant)

+ (HAEntity *)automationSc {
    return [self entityWithId:@"automation.sc" state:@"on" attributes:@{
        @"friendly_name": @"Motion Lights", @"current": @0,
        @"last_triggered": @"2026-03-01T18:30:00Z", @"icon": @"mdi:robot"}];
}

#pragma mark - Showcase: Update (2 variants)

+ (HAEntity *)updateScAvailable {
    return [self entityWithId:@"update.sc_available" state:@"on" attributes:@{
        @"friendly_name": @"HA Core", @"installed_version": @"2024.2.0",
        @"latest_version": @"2024.4.0", @"title": @"Home Assistant Core",
        @"release_url": @"https://www.home-assistant.io/blog/", @"icon": @"mdi:package-up"}];
}

+ (HAEntity *)updateScCurrent {
    return [self entityWithId:@"update.sc_current" state:@"off" attributes:@{
        @"friendly_name": @"Zigbee", @"installed_version": @"7.4.1",
        @"latest_version": @"7.4.1", @"title": @"Zigbee Coordinator",
        @"icon": @"mdi:package-check"}];
}

#pragma mark - Showcase: Valve (2 variants)

+ (HAEntity *)valveScOpen {
    return [self entityWithId:@"valve.sc_open" state:@"open" attributes:@{
        @"friendly_name": @"Garden Valve", @"current_position": @100, @"icon": @"mdi:valve-open"}];
}

+ (HAEntity *)valveScClosed {
    return [self entityWithId:@"valve.sc_closed" state:@"closed" attributes:@{
        @"friendly_name": @"Pool Valve", @"current_position": @0, @"icon": @"mdi:valve-closed"}];
}

#pragma mark - Showcase: Lawn Mower (2 variants)

+ (HAEntity *)lawnMowerScDocked {
    return [self entityWithId:@"lawn_mower.sc_docked" state:@"docked" attributes:@{
        @"friendly_name": @"Mower Docked", @"icon": @"mdi:robot-mower"}];
}

+ (HAEntity *)lawnMowerScMowing {
    return [self entityWithId:@"lawn_mower.sc_mowing" state:@"mowing" attributes:@{
        @"friendly_name": @"Mowing", @"icon": @"mdi:robot-mower"}];
}

#pragma mark - Showcase: Water Heater (1 variant)

+ (HAEntity *)waterHeaterSc {
    return [self entityWithId:@"water_heater.sc" state:@"eco" attributes:@{
        @"friendly_name": @"Water Heater", @"temperature": @50, @"current_temperature": @48.5,
        @"min_temp": @30, @"max_temp": @65, @"target_temp_step": @1,
        @"operation_mode": @"eco", @"operation_list": @[@"eco", @"electric", @"performance", @"off"],
        @"icon": @"mdi:water-boiler"}];
}

#pragma mark - Showcase: Misc Domains

+ (HAEntity *)remoteSc {
    return [self entityWithId:@"remote.sc" state:@"idle" attributes:@{
        @"friendly_name": @"TV Remote", @"current_activity": @"Watch TV",
        @"activity_list": @[@"Watch TV", @"Gaming", @"Music", @"Off"], @"icon": @"mdi:remote"}];
}

+ (HAEntity *)imageSc {
    return [self entityWithId:@"image.sc" state:@"2026-03-01T10:00:00Z" attributes:@{
        @"friendly_name": @"Snapshot", @"entity_picture": @"/api/image_proxy/image.sc",
        @"icon": @"mdi:image"}];
}

+ (HAEntity *)todoSc {
    return [self entityWithId:@"todo.sc" state:@"3" attributes:@{
        @"friendly_name": @"Shopping List", @"icon": @"mdi:clipboard-list"}];
}

+ (HAEntity *)eventSc {
    return [self entityWithId:@"event.sc" state:@"2026-03-01T15:30:00Z" attributes:@{
        @"friendly_name": @"Doorbell", @"event_type": @"button_press",
        @"device_class": @"doorbell", @"icon": @"mdi:doorbell"}];
}

+ (HAEntity *)deviceTrackerScHome {
    return [self entityWithId:@"device_tracker.sc_home" state:@"home" attributes:@{
        @"friendly_name": @"Car", @"source_type": @"gps", @"icon": @"mdi:car"}];
}

+ (HAEntity *)deviceTrackerScAway {
    return [self entityWithId:@"device_tracker.sc_away" state:@"not_home" attributes:@{
        @"friendly_name": @"Laptop", @"source_type": @"router", @"icon": @"mdi:laptop"}];
}

#pragma mark - Edge Cases (Tier C)

+ (HAEntity *)unavailableEntity:(NSString *)entityId {
    // Derive friendly name from entity ID: "sensor.living_room_temp" -> "Living Room Temp"
    NSString *objectId = [[entityId componentsSeparatedByString:@"."] lastObject];
    NSString *friendlyName = [[objectId stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString];
    return [self entityWithId:entityId
                        state:@"unavailable"
                   attributes:@{
        @"friendly_name": friendlyName
    }];
}

+ (HAEntity *)longNameEntity:(NSString *)entityId {
    return [self entityWithId:entityId
                        state:@"on"
                   attributes:@{
        @"friendly_name": @"This Is An Extremely Long Entity Name That Should Test Truncation Behavior"
    }];
}

+ (HAEntity *)minimalEntity:(NSString *)entityId {
    return [self entityWithId:entityId
                        state:@"unknown"
                   attributes:@{}];
}

#pragma mark - Section / Config Helpers

+ (HADashboardConfigSection *)entitiesSectionWithLights {
    return [self sectionWithTitle:@"Lights"
                             icon:@"mdi:lightbulb-group"
                        entityIds:@[
        @"light.office_3",
        @"light.downstairs",
        @"light.upstairs"
    ]];
}

+ (HADashboardConfigSection *)entitiesSectionFiveRows {
    return [self sectionWithTitle:@"All Devices"
                             icon:@"mdi:devices"
                        entityIds:@[
        @"light.kitchen",
        @"switch.in_meeting",
        @"sensor.living_room_temperature",
        @"cover.office_blinds",
        @"lock.frontdoor"
    ]];
}

+ (HADashboardConfigSection *)badgeSection2Items {
    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.title = @"Environment";
    section.icon = @"mdi:thermometer";
    section.entityIds = @[
        @"sensor.living_room_temperature",
        @"sensor.living_room_humidity"
    ];
    section.customProperties = @{@"chipStyle": @"badge"};
    return section;
}

+ (HADashboardConfigSection *)badgeSection4Items {
    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.title = @"Status";
    section.icon = @"mdi:home";
    section.entityIds = @[
        @"sensor.living_room_temperature",
        @"sensor.living_room_humidity",
        @"binary_sensor.hallway_motion",
        @"binary_sensor.front_door"
    ];
    section.customProperties = @{@"chipStyle": @"badge"};
    return section;
}

+ (HADashboardConfigItem *)gaugeCardItem50Percent {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = @"sensor.living_room_humidity";
    item.cardType = @"gauge";
    item.columnSpan = 1;
    item.rowSpan = 1;
    item.customProperties = @{
        @"min": @0,
        @"max": @100,
        @"name": @"Humidity"
    };
    return item;
}

+ (HADashboardConfigItem *)gaugeCardItem0Percent {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = @"sensor.empty_tank";
    item.cardType = @"gauge";
    item.columnSpan = 1;
    item.rowSpan = 1;
    item.customProperties = @{
        @"min": @0,
        @"max": @100,
        @"name": @"Tank Level"
    };
    return item;
}

+ (HADashboardConfigItem *)gaugeCardItem100Percent {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = @"sensor.full_battery";
    item.cardType = @"gauge";
    item.columnSpan = 1;
    item.rowSpan = 1;
    item.customProperties = @{
        @"min": @0,
        @"max": @100,
        @"name": @"Battery"
    };
    return item;
}

+ (HADashboardConfigItem *)gaugeCardItemSeverity {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = @"sensor.cpu_temperature";
    item.cardType = @"gauge";
    item.columnSpan = 1;
    item.rowSpan = 1;
    item.customProperties = @{
        @"min": @0,
        @"max": @100,
        @"name": @"CPU Temperature",
        @"severity": @{
            @"green": @40,
            @"yellow": @70,
            @"red": @90
        }
    };
    return item;
}

+ (HADashboardConfigItem *)graphCardSingleEntity {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = @"sensor.living_room_temperature";
    item.cardType = @"sensor";
    item.columnSpan = 2;
    item.rowSpan = 1;
    item.customProperties = @{
        @"graph": @"line",
        @"detail": @1,
        @"hours_to_show": @24
    };
    return item;
}

+ (HADashboardConfigItem *)graphCardMultiEntity {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = @"sensor.living_room_temperature";
    item.cardType = @"sensor";
    item.columnSpan = 2;
    item.rowSpan = 1;
    item.customProperties = @{
        @"graph": @"line",
        @"detail": @1,
        @"hours_to_show": @24,
        @"entities": @[
            @"sensor.living_room_temperature",
            @"sensor.living_room_humidity",
            @"sensor.office_illuminance"
        ]
    };
    return item;
}

#pragma mark - Weather Forecast Helper

+ (NSArray *)forecastArrayForDays:(NSInteger)days {
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

        // Generate varying but deterministic temperatures
        NSInteger highTemp = 10 + (i * 3) % 15;   // range ~10-24
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

@end
