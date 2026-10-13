#import "HABaseEntityCell.h"

@interface HAMediaPlayerEntityCell : HABaseEntityCell

/// Preferred card height (excludes heading) for the entity's current state:
/// rows of controls the player doesn't offer right now (e.g. everything but
/// power while off) are collapsed, so the height depends on state.
+ (CGFloat)preferredHeightForEntity:(HAEntity *)entity;

@end
