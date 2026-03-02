#import <UIKit/UIKit.h>

@class HAEntity;
@class HADashboardConfigItem;

@interface HABaseEntityCell : UICollectionViewCell

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

@end
