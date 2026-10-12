#import <UIKit/UIKit.h>

@class HADashboardConfigSection;

/// Custom section header for the dashboard collection view.
/// Displays an optional MDI icon (as Unicode symbol) and a section title.
@interface HASectionHeaderView : UICollectionReusableView

- (void)configureWithSection:(HADashboardConfigSection *)section;

/// Distance from the header's leading edge to its icon (or to the title when
/// there is no icon), and from its trailing edge to the title. Defaults to 8,
/// the inset of a standalone heading row (HAHeadingCell) inside its item frame,
/// which is right when the header frame starts where the section's items
/// start (HAColumnarLayout). A header spanning the full collection-view width
/// while items are inset (flow layout) adds that inset so both line up.
@property (nonatomic, assign) CGFloat contentInset;

@end
