#import "HABaseEntityCell.h"

NS_ASSUME_NONNULL_BEGIN

/// Native rendering of Home Assistant's built-in `clock` Lovelace card
/// (frontend hui-clock-card / -digital / -analog), digital and analog styles.
///
/// The parser copies the card config onto the item's customProperties
/// (clock_style, clock_size, show_seconds, seconds_motion, time_format,
/// time_zone, no_background, date_format, border, ticks, face_style, and the
/// card title as clock_title). The cell never has an entity.
///
/// Time updates come from one one-shot NSTimer per visible cell, re-armed on
/// every tick for the next wall-clock second boundary. The timer targets a
/// weak proxy, runs only while the cell is configured, displayed and in a
/// window, and is torn down by -endTicking, -prepareForReuse and window
/// removal.
@interface HAClockCardCell : HABaseEntityCell

/// Content height (excluding any grid heading) for the item's config.
+ (CGFloat)preferredHeightForConfigItem:(HADashboardConfigItem *)configItem width:(CGFloat)width;

/// Resume ticking (the dashboard calls this from willDisplayCell:). Cells
/// also start on configure, since iOS 9 may skip willDisplayCell: for the
/// initially visible cells.
- (void)beginTicking;

/// Stop ticking (didEndDisplayingCell:). Safe to call repeatedly.
- (void)endTicking;

/// YES while a tick timer is scheduled.
@property (nonatomic, readonly, getter=isTicking) BOOL ticking;

/// Test hook: when set, the cell renders this instant and never schedules a
/// timer, so snapshots are deterministic. Set before configuring.
@property (nonatomic, copy, nullable) NSDate *fixedDate;

/// Test hook: the HA language code to format with instead of the app's
/// current HA content language. Set before configuring.
@property (nonatomic, copy, nullable) NSString *languageCodeOverride;

/// The currently rendered digital time ("20:06"), seconds ("47"), AM/PM
/// marker and date text. Exposed for tests.
@property (nonatomic, readonly, nullable) NSString *renderedTimeText;
@property (nonatomic, readonly, nullable) NSString *renderedSecondsText;
@property (nonatomic, readonly, nullable) NSString *renderedAmPmText;
@property (nonatomic, readonly, nullable) NSString *renderedDateText;

/// Uniform scale currently applied to the digital time group (1 = HA's full
/// size; shrinks, never below 0.4, when the cell is too narrow). Exposed for tests.
@property (nonatomic, readonly) CGFloat timeScale;

@end

NS_ASSUME_NONNULL_END
