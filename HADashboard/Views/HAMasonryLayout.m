#import "HAMasonryLayout.h"

/// HA masonry spacing constants (matching hui-masonry-view.ts)
static const CGFloat kContainerPaddingTop = 4.0;
static const CGFloat kColumnMarginLR = 4.0;   // column left/right margin
static const CGFloat kCardMarginTop = 4.0;
static const CGFloat kCardMarginLR = 4.0;      // card left/right within column
static const CGFloat kCardMarginBottom = 8.0;
static const CGFloat kMaxColumnWidth = 500.0;
static const CGFloat kBadgesMarginLR = 8.0;    // hui-view-badges margin: 4px 8px
static const CGFloat kBadgesMarginTB = 4.0;

@interface HAMasonryLayout ()
@property (nonatomic, strong) NSMutableArray<UICollectionViewLayoutAttributes *> *itemAttributes;
@property (nonatomic, assign) CGSize cachedContentSize;
@end

@implementation HAMasonryLayout

- (instancetype)init {
    self = [super init];
    if (self) {
        _itemAttributes = [NSMutableArray array];
    }
    return self;
}

#pragma mark - Column Count (HA Breakpoints)

/// Determine column count from viewport width using HA's matchMedia breakpoints.
/// < 300 → 1, 300-599 → 1, 600-899 → 2, 900-1199 → 3, >= 1200 → 4
- (NSInteger)columnCountForWidth:(CGFloat)width {
    if (width >= 1200.0) return 4;
    if (width >= 900.0) return 3;
    if (width >= 600.0) return 2;
    return 1;
}

#pragma mark - Card Size Estimation

/// Abstract size units for column assignment (from HA's computeCardSize).
/// These are NOT pixel heights — they determine which column a card goes to.
- (NSInteger)cardSizeUnitsForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionView *cv = self.collectionView;
    if (!cv) return 1;

    NSString *cardType = nil;
    if ([self.delegate respondsToSelector:@selector(collectionView:layout:cardTypeForItemAtIndexPath:)]) {
        cardType = [self.delegate collectionView:cv layout:self cardTypeForItemAtIndexPath:indexPath];
    }
    if (!cardType) return 1;

    if ([cardType isEqualToString:@"thermostat"]) return 7;
    if ([cardType isEqualToString:@"weather-forecast"] || [cardType isEqualToString:@"weather"]) return 4;
    if ([cardType isEqualToString:@"history-graph"] || [cardType isEqualToString:@"graph"]) return 4;
    if ([cardType isEqualToString:@"sensor"]) return 2;
    if ([cardType isEqualToString:@"clock"]) return 2; // hui-clock-card getCardSize (1 only for explicit small)
    if ([cardType isEqualToString:@"media-control"] || [cardType containsString:@"media-player"]) return 3;
    if ([cardType isEqualToString:@"alarm-panel"] || [cardType containsString:@"alarm"]) return 3;

    if ([cardType isEqualToString:@"entities"]) {
        NSInteger entityCount = 0;
        if ([self.delegate respondsToSelector:@selector(collectionView:layout:entityCountForItemAtIndexPath:)]) {
            entityCount = [self.delegate collectionView:cv layout:self entityCountForItemAtIndexPath:indexPath];
        }
        return 2 + entityCount;
    }

    return 1;
}

#pragma mark - Layout

- (void)prepareLayout {
    [super prepareLayout];

    [self.itemAttributes removeAllObjects];

    UICollectionView *cv = self.collectionView;
    if (!cv) return;

    NSInteger sectionCount = [cv numberOfSections];
    if (sectionCount == 0) {
        self.cachedContentSize = CGSizeZero;
        return;
    }

    // All masonry items are in section 0
    NSInteger itemCount = [cv numberOfItemsInSection:0];
    if (itemCount == 0) {
        self.cachedContentSize = CGSizeMake(cv.bounds.size.width, kContainerPaddingTop);
        return;
    }

    CGFloat viewportWidth = cv.bounds.size.width;
    NSInteger columnCount = [self columnCountForWidth:viewportWidth];

    // Available width for columns (after column margins)
    // Each column has kColumnMarginLR on left and right
    CGFloat totalColumnMargins = columnCount * 2.0 * kColumnMarginLR;
    CGFloat availableWidth = viewportWidth - totalColumnMargins;

    // Column width capped at kMaxColumnWidth
    CGFloat columnWidth = floor(availableWidth / columnCount);
    if (columnWidth > kMaxColumnWidth) {
        columnWidth = kMaxColumnWidth;
    }

    // Actual card width within column (after card L/R margins)
    CGFloat cardWidth = columnWidth - 2.0 * kCardMarginLR;

    // Total columns width for centering
    CGFloat totalColumnsWidth = columnCount * (columnWidth + 2.0 * kColumnMarginLR);
    CGFloat leftOffset = floor((viewportWidth - totalColumnsWidth) / 2.0);
    if (leftOffset < 0) leftOffset = 0;

    // Column heights (abstract units for assignment) and Y offsets (pixels for placement)
    // Leading full-width items (the view badge row) span the viewport above the columns
    CGFloat columnsTop = kContainerPaddingTop;
    NSInteger firstColumnItem = 0;
    if ([self.delegate respondsToSelector:@selector(collectionView:layout:isFullWidthItemAtIndexPath:)]) {
        CGFloat fullWidth = MAX(0, viewportWidth - 2.0 * kBadgesMarginLR);
        while (firstColumnItem < itemCount) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:firstColumnItem inSection:0];
            if (![self.delegate collectionView:cv layout:self isFullWidthItemAtIndexPath:indexPath]) break;
            CGFloat itemHeight = 100.0;
            if ([self.delegate respondsToSelector:@selector(collectionView:layout:heightForItemAtIndexPath:itemWidth:)]) {
                itemHeight = [self.delegate collectionView:cv layout:self heightForItemAtIndexPath:indexPath itemWidth:fullWidth];
            }
            UICollectionViewLayoutAttributes *attr =
                [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
            attr.frame = CGRectMake(kBadgesMarginLR, columnsTop + kBadgesMarginTB, fullWidth, itemHeight);
            [self.itemAttributes addObject:attr];
            columnsTop += kBadgesMarginTB + itemHeight + kBadgesMarginTB;
            firstColumnItem++;
        }
    }

    NSInteger *columnUnits = calloc(columnCount, sizeof(NSInteger));
    CGFloat *columnY = calloc(columnCount, sizeof(CGFloat));
    for (NSInteger i = 0; i < columnCount; i++) {
        columnY[i] = columnsTop;
    }

    for (NSInteger item = firstColumnItem; item < itemCount; item++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:0];

        // Compute abstract size units for this card
        NSInteger sizeUnits = [self cardSizeUnitsForItemAtIndexPath:indexPath];

        // Find shortest column (HA: prefer columns with total < 5 units)
        NSInteger targetColumn = 0;
        NSInteger minUnits = columnUnits[0];
        CGFloat minY = columnY[0];
        for (NSInteger c = 1; c < columnCount; c++) {
            BOOL currentUnder5 = (columnUnits[targetColumn] < 5);
            BOOL candidateUnder5 = (columnUnits[c] < 5);

            if (candidateUnder5 && !currentUnder5) {
                // Prefer under-5 columns
                targetColumn = c;
                minUnits = columnUnits[c];
                minY = columnY[c];
            } else if (candidateUnder5 == currentUnder5) {
                // Both under or both over: pick shortest by pixel height
                if (columnY[c] < minY) {
                    targetColumn = c;
                    minUnits = columnUnits[c];
                    minY = columnY[c];
                }
            }
        }

        // Calculate X position for target column
        CGFloat columnX = leftOffset + targetColumn * (columnWidth + 2.0 * kColumnMarginLR) + kColumnMarginLR + kCardMarginLR;

        // Get actual pixel height from delegate
        CGFloat itemHeight = 100.0; // fallback
        if ([self.delegate respondsToSelector:@selector(collectionView:layout:heightForItemAtIndexPath:itemWidth:)]) {
            itemHeight = [self.delegate collectionView:cv layout:self heightForItemAtIndexPath:indexPath itemWidth:cardWidth];
        }

        // Create layout attributes
        UICollectionViewLayoutAttributes *attr =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        attr.frame = CGRectMake(columnX, columnY[targetColumn] + kCardMarginTop, cardWidth, itemHeight);
        [self.itemAttributes addObject:attr];

        // Advance column tracking
        columnUnits[targetColumn] += sizeUnits;
        columnY[targetColumn] += kCardMarginTop + itemHeight + kCardMarginBottom;
    }

    // Content height = tallest column
    CGFloat maxY = 0;
    for (NSInteger c = 0; c < columnCount; c++) {
        if (columnY[c] > maxY) maxY = columnY[c];
    }

    free(columnUnits);
    free(columnY);

    self.cachedContentSize = CGSizeMake(viewportWidth, maxY);
}

- (CGSize)collectionViewContentSize {
    return self.cachedContentSize;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray *result = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes *attr in self.itemAttributes) {
        if (CGRectIntersectsRect(attr.frame, rect)) {
            [result addObject:attr];
        }
    }
    return result;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    for (UICollectionViewLayoutAttributes *attr in self.itemAttributes) {
        if ([attr.indexPath isEqual:indexPath]) {
            return attr;
        }
    }
    return nil;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return YES; // Always recalculate on rotation or resize
}

@end
