#import <UIKit/UIKit.h>

@protocol HAMasonryLayoutDelegate <UICollectionViewDelegate>

/// Return the height for an item at the given index path
- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath
                itemWidth:(CGFloat)itemWidth;

/// Return the card type string for an item (used for column size estimation)
- (NSString *)collectionView:(UICollectionView *)collectionView
                      layout:(UICollectionViewLayout *)layout
     cardTypeForItemAtIndexPath:(NSIndexPath *)indexPath;

/// Return the entity count for composite cards (entities card row count)
- (NSInteger)collectionView:(UICollectionView *)collectionView
                     layout:(UICollectionViewLayout *)layout
  entityCountForItemAtIndexPath:(NSIndexPath *)indexPath;

@optional
/// Return YES for a leading item (e.g. the view's badge row) that spans the
/// viewport above the columns, like HA's hui-view-badges. Only consulted for
/// the first items of section 0.
- (BOOL)collectionView:(UICollectionView *)collectionView
                layout:(UICollectionViewLayout *)layout
isFullWidthItemAtIndexPath:(NSIndexPath *)indexPath;

@end

/// Masonry (shortest-column-first) collection view layout matching HA's classic view.
/// Uses HA breakpoints for column count, 500px max column width, and abstract card size
/// units for column assignment. All items in a single section (section 0).
/// Compatible with iOS 9+ (UICollectionViewLayout subclass).
@interface HAMasonryLayout : UICollectionViewLayout

@property (nonatomic, weak) id<HAMasonryLayoutDelegate> delegate;

@end
