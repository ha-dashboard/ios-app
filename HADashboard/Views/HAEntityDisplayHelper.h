#import <UIKit/UIKit.h>

@class HAEntity, HADashboardConfigItem, HADashboardConfigSection;

/// Shared entity display logic — single source of truth for name resolution,
/// state formatting, icon rendering, and toggle detection.
/// All container views (badges, entity rows, sensor cells, graph cards)
/// should use these methods instead of reimplementing display logic.
@interface HAEntityDisplayHelper : NSObject

/// Resolve the display name for an entity.
/// Priority: nameOverride > configItem.displayName > entity.friendlyName > entityId
+ (NSString *)displayNameForEntity:(HAEntity *)entity
                        configItem:(HADashboardConfigItem *)configItem
                      nameOverride:(NSString *)nameOverride;

/// Convenience: resolve display name from a section's nameOverrides dict
+ (NSString *)displayNameForEntity:(HAEntity *)entity
                          entityId:(NSString *)entityId
                           section:(HADashboardConfigSection *)section;

/// Format the entity's state value with rounding.
/// @param decimals Number of decimal places (1 for badges, 2 for detail views)
+ (NSString *)formattedStateForEntity:(HAEntity *)entity decimals:(NSInteger)decimals;

/// YES for device_class timestamp/uptime or an ISO 8601-shaped state string.
+ (BOOL)isTimestampState:(NSString *)state deviceClass:(NSString *)deviceClass;

/// As above, rendering timestamp states (device_class timestamp/uptime or an
/// ISO 8601 state) with a card's HA `time_format` (string or {type, style});
/// nil uses HA's default (relative, or total for uptime).
+ (NSString *)formattedStateForEntity:(HAEntity *)entity decimals:(NSInteger)decimals timeFormat:(id)timeFormat;

/// Format state + unit as a single string (e.g. "21.5 °C")
+ (NSString *)stateWithUnitForEntity:(HAEntity *)entity decimals:(NSInteger)decimals;

/// Get the MDI icon glyph for an entity.
/// Checks entity attributes["icon"] first, falls back to domain icon.
+ (NSString *)iconGlyphForEntity:(HAEntity *)entity;

/// Get the icon color for an entity based on domain and state.
+ (UIColor *)iconColorForEntity:(HAEntity *)entity;

/// Whether the entity's domain supports toggle (switch, light, fan, etc.)
+ (BOOL)isEntityToggleable:(HAEntity *)entity;

/// Device-class-aware state string for binary_sensor entities.
/// Maps device_class + on/off to friendly names (e.g. door → "Open"/"Closed").
+ (NSString *)binarySensorStateForDeviceClass:(NSString *)deviceClass isOn:(BOOL)isOn;

/// Convert a raw state string to human-readable form.
/// Splits camelCase and underscores into separate capitalized words.
/// E.g. "readyForCharging" → "Ready For Charging", "heat_cool" → "Heat Cool"
+ (NSString *)humanReadableState:(NSString *)state;

/// Format a numeric state with locale-aware thousands separators.
/// E.g. 4908.6 → "4,908.6", 12096 → "12,096"
+ (NSString *)formattedNumberString:(double)value decimals:(NSInteger)decimals;

/// Format a duration value given in the specified unit to human-readable form.
/// E.g. 116.23 h → "4d 20h", 3600 s → "1h 0m"
+ (NSString *)formattedDurationFromValue:(double)value unit:(NSString *)unit;

/// Format an ISO 8601 timestamp string as relative time.
/// E.g. "2026-02-11T10:15:30+00:00" → "5 minutes ago"
+ (NSString *)relativeTimeFromISO8601:(NSString *)isoString;

/// Text for a Lovelace "state_content" option (a string or array of strings,
/// as on tile cards and entity badges): each part is "state" (→ stateText),
/// "name" (→ name, when non-nil), "last_changed"/"last-changed",
/// "last_updated"/"last-updated" (relative time), or an attribute name.
/// Non-empty parts are joined with " · ". Returns nil when nothing resolves,
/// so the caller keeps its default state text.
+ (NSString *)stateContentText:(id)stateContent
                     forEntity:(HAEntity *)entity
                     stateText:(NSString *)stateText
                          name:(NSString *)name;

/// Approximation of HA's stateActive(): whether a badge's custom "color"
/// applies (entity and heading badges only use it while the entity is active).
+ (BOOL)isEntityStateActive:(HAEntity *)entity;

/// Check whether a string represents a numeric value.
/// Returns NO for nil, empty, "unavailable", "unknown", "on", "off".
+ (BOOL)isNumericString:(NSString *)string;

/// Format an ISO 8601 timestamp or state value per HA's format option.
/// Supports: "relative" (e.g. "5 min ago"), "total" (duration since epoch),
/// "date" (date only), "time" (time only), "datetime" (date + time), either as
/// a string or as HA's {type, style} object (date/datetime "short" = numeric,
/// time "long" = with seconds).
/// Returns the original value if format is unknown or parsing fails.
+ (NSString *)formattedValue:(NSString *)value withFormat:(id)format;

@end
