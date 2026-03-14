#import <UIKit/UIKit.h>
#import "HACellCompat.h"

@class HAEntity;
@class HADashboardConfigItem;

@interface HABaseEntityCell : HACollectionViewCellBase

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, weak)   HAEntity *entity;

/// Heading label rendered above the card (for grid headings like
/// "House Climate", "Ribbit"). Added to the cell itself (not contentView).
/// When visible, contentView is pushed down to make room.
@property (nonatomic, strong) UILabel *headingLabel;

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem;
- (void)setupSubviews;

/// Returns the extra height needed for the heading area (0 if no heading).
+ (CGFloat)headingHeight;

#pragma mark - Theme Helpers

/// Reset theme-dependent colors for reuse. Base implementation resets
/// contentView.backgroundColor, nameLabel, stateLabel, headingLabel colors.
/// Override in subclasses (call super) to reset additional controls.
- (void)resetThemeColors;

/// Set contentView background based on on/off state.
/// YES → onTintColor, NO → cellBackgroundColor.
- (void)applyOnStateTint:(BOOL)isOn;

#pragma mark - Factory Helpers

/// Create a UILabel, add it to contentView, and configure for autolayout.
/// @param font Label font
/// @param color Text color
/// @param lines Maximum number of lines (1 for single-line)
- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines;

/// Call a Home Assistant service for this cell's entity.
/// No-op if self.entity is nil.
- (void)callService:(NSString *)service inDomain:(NSString *)domain;
- (void)callService:(NSString *)service inDomain:(NSString *)domain withData:(NSDictionary *)data;

/// Create a styled action button, add it to contentView, and configure for autolayout.
- (UIButton *)actionButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action;

#pragma mark - Slider Helpers

/// YES while the user is dragging a slider.  Subclasses can check this to
/// suppress external state updates during a drag gesture.
@property (nonatomic, assign) BOOL sliderDragging;

/// Wire to UIControlEventTouchDown on any slider.  Sets sliderDragging = YES.
- (void)sliderTouchDown:(UISlider *)sender;

/// Wire to UIControlEventTouchUpInside / TouchUpOutside.  Sets sliderDragging = NO.
/// Subclasses should override and call super to perform the service call.
- (void)sliderTouchUp:(UISlider *)sender;

#pragma mark - Option Sheet

/// Present an action-sheet picker.
/// @param title  Optional sheet title (may be nil).
/// @param options  Display strings to show.
/// @param current  The currently-selected option (gets a checkmark), or nil.
/// @param sourceView  Anchor view for iPad popover.
/// @param handler  Called with the selected option string.
- (void)presentOptionsWithTitle:(NSString *)title
                        options:(NSArray<NSString *> *)options
                        current:(NSString *)current
                     sourceView:(UIView *)sourceView
                        handler:(void(^)(NSString *selected))handler;

@end
