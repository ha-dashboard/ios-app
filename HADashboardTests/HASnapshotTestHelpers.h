#import <Foundation/Foundation.h>

@class HAEntity;
@class HADashboardConfigItem;
@class HADashboardConfigSection;

/// Factory methods for creating mock data in snapshot tests.
/// Avoids needing a live HA connection — creates entities and config items
/// with known, deterministic values.
@interface HASnapshotTestHelpers : NSObject

#pragma mark - Core Factories

/// Create a mock entity with the given ID, state, and attributes.
+ (HAEntity *)entityWithId:(NSString *)entityId
                     state:(NSString *)state
                attributes:(NSDictionary *)attributes;

/// Create a config item for a single-entity card with optional heading.
+ (HADashboardConfigItem *)itemWithEntityId:(NSString *)entityId
                                   cardType:(NSString *)cardType
                                 columnSpan:(NSInteger)columnSpan
                                headingIcon:(NSString *)headingIcon
                                displayName:(NSString *)displayName;

/// Create an entities section for composite cards.
+ (HADashboardConfigSection *)sectionWithTitle:(NSString *)title
                                          icon:(NSString *)icon
                                     entityIds:(NSArray<NSString *> *)entityIds;

/// Create a dictionary of mock entities for the standard test dashboards.
+ (NSDictionary<NSString *, HAEntity *> *)livingRoomEntities;

#pragma mark - Light (4 variants)

+ (HAEntity *)lightEntityOnBrightness;
+ (HAEntity *)lightEntityOnRGB;
+ (HAEntity *)lightEntityOnDimmed;
+ (HAEntity *)lightEntityOff;

#pragma mark - Climate (4 variants)

+ (HAEntity *)climateEntityHeat;
+ (HAEntity *)climateEntityCool;
+ (HAEntity *)climateEntityAuto;
+ (HAEntity *)climateEntityOff;

#pragma mark - Switch (2 variants)

+ (HAEntity *)switchEntityOn;
+ (HAEntity *)switchEntityOff;

#pragma mark - Cover (3 variants)

+ (HAEntity *)coverEntityOpenShutter;
+ (HAEntity *)coverEntityClosedGarage;
+ (HAEntity *)coverEntityPartial;

#pragma mark - Media Player (3 variants)

+ (HAEntity *)mediaPlayerPlaying;
+ (HAEntity *)mediaPlayerPaused;
+ (HAEntity *)mediaPlayerOff;

#pragma mark - Sensor (6 variants)

+ (HAEntity *)sensorTemperature;
+ (HAEntity *)sensorHumidity;
+ (HAEntity *)sensorEnergy;
+ (HAEntity *)sensorBattery;
+ (HAEntity *)sensorIlluminance;
+ (HAEntity *)sensorGenericText;

#pragma mark - Alarm Control Panel (4 variants)

+ (HAEntity *)alarmDisarmed;
+ (HAEntity *)alarmArmedHome;
+ (HAEntity *)alarmArmedAway;
+ (HAEntity *)alarmTriggered;

#pragma mark - Person (2 variants)

+ (HAEntity *)personHome;
+ (HAEntity *)personNotHome;

#pragma mark - Lock (3 variants)

+ (HAEntity *)lockLocked;
+ (HAEntity *)lockUnlocked;
+ (HAEntity *)lockJammed;

#pragma mark - Weather (3 variants)

+ (HAEntity *)weatherSunny;
+ (HAEntity *)weatherCloudy;
+ (HAEntity *)weatherRainy;

#pragma mark - Input Select (2 variants)

+ (HAEntity *)inputSelectThreeOptions;
+ (HAEntity *)inputSelectFiveOptions;

#pragma mark - Input Number (2 variants)

+ (HAEntity *)inputNumberSlider;
+ (HAEntity *)inputNumberBox;

#pragma mark - Button (2 variants)

+ (HAEntity *)buttonDefault;
+ (HAEntity *)buttonPressed;

#pragma mark - Update (2 variants)

+ (HAEntity *)updateAvailable;
+ (HAEntity *)updateUpToDate;

#pragma mark - Counter (2 variants)

+ (HAEntity *)counterLow;
+ (HAEntity *)counterHigh;

#pragma mark - Binary Sensor (3 variants)

+ (HAEntity *)binarySensorMotionOn;
+ (HAEntity *)binarySensorDoorOff;
+ (HAEntity *)binarySensorMoistureOff;

#pragma mark - Device Tracker (1 variant)

+ (HAEntity *)deviceTrackerNotHome;

#pragma mark - Fan (3 variants)

+ (HAEntity *)fanEntityOnHalf;
+ (HAEntity *)fanEntityOnFull;
+ (HAEntity *)fanEntityOff;

#pragma mark - Vacuum (4 variants)

+ (HAEntity *)vacuumDocked;
+ (HAEntity *)vacuumCleaning;
+ (HAEntity *)vacuumReturning;
+ (HAEntity *)vacuumError;

#pragma mark - Humidifier (2 variants)

+ (HAEntity *)humidifierOn;
+ (HAEntity *)humidifierOff;

#pragma mark - Timer (3 variants)

+ (HAEntity *)timerActive;
+ (HAEntity *)timerPaused;
+ (HAEntity *)timerIdle;

#pragma mark - Input Text (2 variants)

+ (HAEntity *)inputTextWithValue;
+ (HAEntity *)inputTextEmpty;

#pragma mark - Input DateTime (3 variants)

+ (HAEntity *)inputDateTimeDate;
+ (HAEntity *)inputDateTimeTime;
+ (HAEntity *)inputDateTimeBoth;

#pragma mark - Camera (2 variants)

+ (HAEntity *)cameraStreaming;
+ (HAEntity *)cameraUnavailable;

#pragma mark - Scene (2 variants)

+ (HAEntity *)sceneDefault;
+ (HAEntity *)sceneActivated;

#pragma mark - Clock Weather (2 variants)

+ (HAEntity *)clockWeatherSunny;
+ (HAEntity *)clockWeatherCloudy;

#pragma mark - Showcase: Light (10 variants)

+ (HAEntity *)lightScBasicOn;
+ (HAEntity *)lightScBasicOff;
+ (HAEntity *)lightScColorTemp;
+ (HAEntity *)lightScRgb;
+ (HAEntity *)lightScRgbw;
+ (HAEntity *)lightScAllModes;
+ (HAEntity *)lightScEffect;
+ (HAEntity *)lightScBrightnessOnly;
+ (HAEntity *)lightScDimmedLow;
+ (HAEntity *)lightScMaxBright;

#pragma mark - Showcase: Climate (8 variants)

+ (HAEntity *)climateScHeating;
+ (HAEntity *)climateScCooling;
+ (HAEntity *)climateScHeatCool;
+ (HAEntity *)climateScPresets;
+ (HAEntity *)climateScFan;
+ (HAEntity *)climateScSwing;
+ (HAEntity *)climateScAll;
+ (HAEntity *)climateScOff;

#pragma mark - Showcase: Cover (10 variants)

+ (HAEntity *)coverScPosition;
+ (HAEntity *)coverScTilt;
+ (HAEntity *)coverScPosTilt;
+ (HAEntity *)coverScNoPosition;
+ (HAEntity *)coverScOpening;
+ (HAEntity *)coverScClosed;
+ (HAEntity *)coverScBlind;
+ (HAEntity *)coverScGarage;
+ (HAEntity *)coverScDoor;
+ (HAEntity *)coverScShutter;

#pragma mark - Showcase: Lock (5 variants)

+ (HAEntity *)lockScLocked;
+ (HAEntity *)lockScUnlocked;
+ (HAEntity *)lockScJammed;
+ (HAEntity *)lockScCode;
+ (HAEntity *)lockScLocking;

#pragma mark - Showcase: Media Player (6 variants)

+ (HAEntity *)mediaPlayerScFull;
+ (HAEntity *)mediaPlayerScPaused;
+ (HAEntity *)mediaPlayerScMuted;
+ (HAEntity *)mediaPlayerScIdle;
+ (HAEntity *)mediaPlayerScOff;
+ (HAEntity *)mediaPlayerScNoSource;

#pragma mark - Showcase: Alarm (7 variants)

+ (HAEntity *)alarmScDisarmed;
+ (HAEntity *)alarmScHome;
+ (HAEntity *)alarmScAway;
+ (HAEntity *)alarmScNight;
+ (HAEntity *)alarmScVacation;
+ (HAEntity *)alarmScTriggered;
+ (HAEntity *)alarmScNoCode;

#pragma mark - Showcase: Fan (5 variants)

+ (HAEntity *)fanScBasic;
+ (HAEntity *)fanScPresets;
+ (HAEntity *)fanScOscillating;
+ (HAEntity *)fanScReverse;
+ (HAEntity *)fanScOff;

#pragma mark - Showcase: Sensor (10 variants)

+ (HAEntity *)sensorScTemperature;
+ (HAEntity *)sensorScHumidity;
+ (HAEntity *)sensorScPower;
+ (HAEntity *)sensorScEnergy;
+ (HAEntity *)sensorScBattery;
+ (HAEntity *)sensorScIlluminance;
+ (HAEntity *)sensorScPressure;
+ (HAEntity *)sensorScGas;
+ (HAEntity *)sensorScMonetary;
+ (HAEntity *)sensorScText;

#pragma mark - Showcase: Binary Sensor (12 variants)

+ (HAEntity *)binarySensorScDoorOpen;
+ (HAEntity *)binarySensorScDoorClosed;
+ (HAEntity *)binarySensorScMotionOn;
+ (HAEntity *)binarySensorScMotionOff;
+ (HAEntity *)binarySensorScSmoke;
+ (HAEntity *)binarySensorScMoisture;
+ (HAEntity *)binarySensorScWindow;
+ (HAEntity *)binarySensorScOccupancy;
+ (HAEntity *)binarySensorScPresence;
+ (HAEntity *)binarySensorScBatteryLow;
+ (HAEntity *)binarySensorScPlug;
+ (HAEntity *)binarySensorScGeneric;

#pragma mark - Showcase: Vacuum (4 variants)

+ (HAEntity *)vacuumScDocked;
+ (HAEntity *)vacuumScCleaning;
+ (HAEntity *)vacuumScReturning;
+ (HAEntity *)vacuumScError;

#pragma mark - Showcase: Humidifier (3 variants)

+ (HAEntity *)humidifierScOn;
+ (HAEntity *)humidifierScEco;
+ (HAEntity *)humidifierScOff;

#pragma mark - Showcase: Input Boolean (2 variants)

+ (HAEntity *)inputBooleanScOn;
+ (HAEntity *)inputBooleanScOff;

#pragma mark - Showcase: Input Number (2 variants)

+ (HAEntity *)inputNumberScSlider;
+ (HAEntity *)inputNumberScBox;

#pragma mark - Showcase: Input Select (1 variant)

+ (HAEntity *)inputSelectSc;

#pragma mark - Showcase: Input Text (2 variants)

+ (HAEntity *)inputTextScText;
+ (HAEntity *)inputTextScPassword;

#pragma mark - Showcase: Input DateTime (3 variants)

+ (HAEntity *)inputDateTimeScDate;
+ (HAEntity *)inputDateTimeScTime;
+ (HAEntity *)inputDateTimeScBoth;

#pragma mark - Showcase: Counter (1 variant)

+ (HAEntity *)counterSc;

#pragma mark - Showcase: Timer (3 variants)

+ (HAEntity *)timerScActive;
+ (HAEntity *)timerScPaused;
+ (HAEntity *)timerScIdle;

#pragma mark - Showcase: Person (3 variants)

+ (HAEntity *)personScHome;
+ (HAEntity *)personScAway;
+ (HAEntity *)personScZone;

#pragma mark - Showcase: Scene & Script (2 variants)

+ (HAEntity *)sceneSc;
+ (HAEntity *)scriptSc;

#pragma mark - Showcase: Automation (1 variant)

+ (HAEntity *)automationSc;

#pragma mark - Showcase: Update (2 variants)

+ (HAEntity *)updateScAvailable;
+ (HAEntity *)updateScCurrent;

#pragma mark - Showcase: Valve (2 variants)

+ (HAEntity *)valveScOpen;
+ (HAEntity *)valveScClosed;

#pragma mark - Showcase: Lawn Mower (2 variants)

+ (HAEntity *)lawnMowerScDocked;
+ (HAEntity *)lawnMowerScMowing;

#pragma mark - Showcase: Water Heater (1 variant)

+ (HAEntity *)waterHeaterSc;

#pragma mark - Showcase: Misc Domains

+ (HAEntity *)remoteSc;
+ (HAEntity *)imageSc;
+ (HAEntity *)todoSc;
+ (HAEntity *)eventSc;
+ (HAEntity *)deviceTrackerScHome;
+ (HAEntity *)deviceTrackerScAway;

#pragma mark - Edge Cases (Tier C)

+ (HAEntity *)unavailableEntity:(NSString *)entityId;
+ (HAEntity *)longNameEntity:(NSString *)entityId;
+ (HAEntity *)minimalEntity:(NSString *)entityId;

#pragma mark - Section / Config Helpers

/// Entities section with 3 lights (office on, downstairs off, upstairs off).
+ (HADashboardConfigSection *)entitiesSectionWithLights;
/// Entities section with 5 mixed entity rows (light, switch, sensor, cover, lock).
+ (HADashboardConfigSection *)entitiesSectionFiveRows;

/// Badge section with 2 items (temperature + humidity sensors).
+ (HADashboardConfigSection *)badgeSection2Items;
/// Badge section with 4 items (temperature, humidity, motion, door sensors).
+ (HADashboardConfigSection *)badgeSection4Items;

/// Gauge card item at 50%.
+ (HADashboardConfigItem *)gaugeCardItem50Percent;
/// Gauge card item at 0%.
+ (HADashboardConfigItem *)gaugeCardItem0Percent;
/// Gauge card item at 100%.
+ (HADashboardConfigItem *)gaugeCardItem100Percent;
/// Gauge card item with severity color bands (green/yellow/red).
+ (HADashboardConfigItem *)gaugeCardItemSeverity;

/// Graph card item with a single sensor entity.
+ (HADashboardConfigItem *)graphCardSingleEntity;
/// Graph card item with 3 sensor entities.
+ (HADashboardConfigItem *)graphCardMultiEntity;

#pragma mark - Weather Forecast Helper

/// Returns an array of forecast dictionaries for the given number of days.
+ (NSArray *)forecastArrayForDays:(NSInteger)days;

@end
