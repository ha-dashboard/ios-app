#import <UIKit/UIKit.h>

@protocol HAColumnarLayoutDelegate <UICollectionViewDelegate>

/// Return the height for an item at the given index path
- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath
                itemWidth:(CGFloat)itemWidth;

/// Return the height for the header in the given section (0 to hide)
- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
heightForHeaderInSection:(NSInteger)section;

/// Return the sub-grid column span (out of 12) for an item (default 12 = full width)
- (NSInteger)collectionView:(UICollectionView *)collectionView
                     layout:(UICollectionViewLayout *)layout
  gridColumnsForItemAtIndexPath:(NSIndexPath *)indexPath;

@optional
/// Return YES if this item is a heading cell that should be laid out like a section header
/// (reduced height, no inter-item spacing below).
- (BOOL)collectionView:(UICollectionView *)collectionView
                 layout:(UICollectionViewLayout *)layout
  isHeadingItemAtIndexPath:(NSIndexPath *)indexPath;

/// Return YES for a leading section (e.g. the view's badge row) that spans the
/// full content width above the columns instead of occupying a column. Only
/// consulted for the first sections; laid out stacked, items at full width.
- (BOOL)collectionView:(UICollectionView *)collectionView
                layout:(UICollectionViewLayout *)layout
    isFullWidthSection:(NSInteger)section;

@end

/// A multi-column collection view layout where each section is a vertical column.
/// Used for HA 2024+ "sections" view type where sections represent page columns.
@interface HAColumnarLayout : UICollectionViewLayout

@property (nonatomic, weak) id<HAColumnarLayoutDelegate> delegate;

/// Spacing between columns
@property (nonatomic, assign) CGFloat interColumnSpacing;

/// Spacing between items within a column
@property (nonatomic, assign) CGFloat interItemSpacing;

/// Insets around the entire content area
@property (nonatomic, assign) UIEdgeInsets contentInsets;

/// Maximum number of columns visible horizontally. Sections beyond this wrap to rows below.
/// 0 = use default (4, matching HA's default for sections views).
@property (nonatomic, assign) NSInteger maxColumns;

@end
