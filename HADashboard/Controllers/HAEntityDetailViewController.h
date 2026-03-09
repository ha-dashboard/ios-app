#import <UIKit/UIKit.h>
#import "HAStackView.h"

@class HAEntity;
@class HAEntityDetailViewController;

/// Delegate for service calls and dismiss requests from the detail view.
/// The presenting controller implements this to route calls through HAConnectionManager.
@protocol HAEntityDetailDelegate <NSObject>
- (void)entityDetail:(HAEntityDetailViewController *)detail
      didCallService:(NSString *)service
            inDomain:(NSString *)domain
            withData:(NSDictionary *)data
            entityId:(NSString *)entityId;
- (void)entityDetailDidRequestDismiss:(HAEntityDetailViewController *)detail;
@end

/// Base entity detail view controller presented as a bottom sheet.
/// Shows a grabber handle, entity header (icon + name + state + close),
/// and a scroll view containing domain controls, history graph, and attributes.
@interface HAEntityDetailViewController : UIViewController

/// The entity to display. Must be set before presentation.
/// For multi-entity graph cards, this is the primary (first) entity.
@property (nonatomic, strong) HAEntity *entity;

/// Optional: multiple entities for multi-series graph display.
/// Each dict: @{@"entityId", @"color" (UIColor), @"label" (NSString), @"unit" (NSString)}.
/// When set, loadHistory fetches all entities and uses dataSeries.
@property (nonatomic, copy) NSArray<NSDictionary *> *graphEntities;

/// Optional: title for multi-entity graph (e.g., "Soil Moisture").
/// Shown in header instead of single entity name when set.
@property (nonatomic, copy) NSString *graphTitle;

/// Optional: initial hours of history to display (from card config, e.g., 72 for 3 days).
/// When set, the history segment control defaults to this range.
@property (nonatomic, assign) NSInteger hoursToShow;

/// Delegate for service calls and dismiss requests.
@property (nonatomic, weak) id<HAEntityDetailDelegate> delegate;

/// The scroll view used for content. Exposed so the presentation controller
/// can coordinate pan-to-dismiss with scroll position.
@property (nonatomic, strong, readonly) UIScrollView *scrollView;

/// Container view inside the scroll view where domain sections, history,
/// and attributes are added. Subclasses and external code add views here.
@property (nonatomic, strong, readonly) HAStackView *contentStack;

@end
