#import "HAColumnarLayout.h"
#import "HACellCompat.h"
#import "HAAutoLayout.h"

@interface HAColumnarLayout ()
@property (nonatomic, strong) NSMutableArray<UICollectionViewLayoutAttributes *> *itemAttributes;
@property (nonatomic, strong) NSMutableArray<UICollectionViewLayoutAttributes *> *headerAttributes;
@property (nonatomic, strong) NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *itemAttributesByIndexPath;
@property (nonatomic, strong) NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *headerAttributesByIndexPath;
@property (nonatomic, assign) CGSize cachedContentSize;
@end

@implementation HAColumnarLayout

- (instancetype)init {
    self = [super init];
    if (self) {
        _interColumnSpacing = 6.0;
        _interItemSpacing = 6.0;
        _contentInsets = UIEdgeInsetsMake(8, 8, 8, 8);
        _itemAttributes = [NSMutableArray array];
        _headerAttributes = [NSMutableArray array];
        _itemAttributesByIndexPath = [NSMutableDictionary dictionary];
        _headerAttributesByIndexPath = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)prepareLayout {
    [super prepareLayout];

    [self.itemAttributes removeAllObjects];
    [self.headerAttributes removeAllObjects];
    [self.itemAttributesByIndexPath removeAllObjects];
    [self.headerAttributesByIndexPath removeAllObjects];

    UICollectionView *cv = self.collectionView;
    if (!cv) return;

    NSInteger sectionCount = [cv numberOfSections];
    if (sectionCount == 0) {
        self.cachedContentSize = CGSizeZero;
        return;
    }

    // Column capping: maxColumns limits the number of visible columns per row.
    // Sections beyond maxColumns wrap into additional rows below.
    NSInteger maxCols = self.maxColumns > 0 ? self.maxColumns : 4; // HA default is 4
    NSInteger effectiveCols = MIN(sectionCount, maxCols);

    CGFloat totalWidth = cv.bounds.size.width - self.contentInsets.left - self.contentInsets.right;

    // Enforce minimum column width: if columns would be narrower than ~180pt,
    // reduce the column count so content remains readable. This handles dashboards
    // like vplants with 8 sections that would otherwise produce unusably narrow columns.
    static const CGFloat kMinColumnWidth = 180.0;
    while (effectiveCols > 1) {
        CGFloat testWidth = floor((totalWidth - self.interColumnSpacing * (effectiveCols - 1)) / effectiveCols);
        if (testWidth >= kMinColumnWidth) break;
        effectiveCols--;
    }

    CGFloat columnWidth = floor((totalWidth - self.interColumnSpacing * (effectiveCols - 1)) / effectiveCols);

    // Number of section rows needed
    NSInteger sectionRowCount = (sectionCount + effectiveCols - 1) / effectiveCols;

    // Track Y offset across section rows
    CGFloat sectionRowStartY = self.contentInsets.top;

    for (NSInteger sectionRow = 0; sectionRow < sectionRowCount; sectionRow++) {
        NSInteger firstSection = sectionRow * effectiveCols;
        NSInteger lastSection = MIN(firstSection + effectiveCols, sectionCount);
        NSInteger colsInRow = lastSection - firstSection;

        // Track the Y offset for each column within this section row
        CGFloat *columnY = calloc(colsInRow, sizeof(CGFloat));
        for (NSInteger c = 0; c < colsInRow; c++) {
            columnY[c] = sectionRowStartY;
        }

        for (NSInteger section = firstSection; section < lastSection; section++) {
            NSInteger col = section - firstSection; // column index within this row
            CGFloat columnX = self.contentInsets.left + col * (columnWidth + self.interColumnSpacing);

            // Section header
            CGFloat headerHeight = 0;
            if ([self.delegate respondsToSelector:@selector(collectionView:layout:heightForHeaderInSection:)]) {
                headerHeight = [self.delegate collectionView:cv layout:self heightForHeaderInSection:section];
            }

            if (headerHeight > 0) {
                NSIndexPath *headerIndexPath = [NSIndexPath indexPathForItem:0 inSection:section];
                UICollectionViewLayoutAttributes *headerAttr =
                    [HACollectionViewLayoutAttributesBase layoutAttributesForSupplementaryViewOfKind:HACollectionElementKindSectionHeader()
                                                                                  withIndexPath:headerIndexPath];
                headerAttr.frame = CGRectMake(columnX, columnY[col], columnWidth, headerHeight);
                [self.headerAttributes addObject:headerAttr];
                self.headerAttributesByIndexPath[headerIndexPath] = headerAttr;
                columnY[col] += headerHeight;
            }

            // Items in this section — sub-grid row packing (12-column grid within each column)
            static const NSInteger kSubGridColumns = 12;
            CGFloat subGridSpacing = 8.0;
            NSInteger itemCount = [cv numberOfItemsInSection:section];
            NSInteger rowUsed = 0;     // sub-grid columns consumed in current row
            CGFloat rowStartY = columnY[col];
            CGFloat rowMaxHeight = 0;  // tallest item in current row

            for (NSInteger item = 0; item < itemCount; item++) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];

                // Get this item's sub-grid span (out of 12)
                NSInteger gridCols = kSubGridColumns; // default full width
                if ([self.delegate respondsToSelector:@selector(collectionView:layout:gridColumnsForItemAtIndexPath:)]) {
                    gridCols = [self.delegate collectionView:cv layout:self gridColumnsForItemAtIndexPath:indexPath];
                }
                gridCols = MAX(1, MIN(gridCols, kSubGridColumns));

                // Check if this item fits in the current row
                if (rowUsed > 0 && rowUsed + gridCols > kSubGridColumns) {
                    // Start a new row
                    columnY[col] = rowStartY + rowMaxHeight + self.interItemSpacing;
                    rowStartY = columnY[col];
                    rowUsed = 0;
                    rowMaxHeight = 0;
                }

                // Calculate item width from sub-grid fraction
                CGFloat itemWidth;
                if (gridCols >= kSubGridColumns) {
                    itemWidth = columnWidth;
                } else {
                    // Proportional width minus spacing between sub-grid items
                    CGFloat usableWidth = columnWidth;
                    itemWidth = floor((usableWidth * gridCols) / kSubGridColumns - subGridSpacing * 0.5);
                }

                CGFloat itemX = columnX + (columnWidth * rowUsed) / kSubGridColumns;
                if (rowUsed > 0) itemX += subGridSpacing * 0.5;

                CGFloat itemHeight = 100.0;
                if ([self.delegate respondsToSelector:@selector(collectionView:layout:heightForItemAtIndexPath:itemWidth:)]) {
                    itemHeight = [self.delegate collectionView:cv layout:self heightForItemAtIndexPath:indexPath itemWidth:itemWidth];
                }

                UICollectionViewLayoutAttributes *attr =
                    [HACollectionViewLayoutAttributesBase layoutAttributesForCellWithIndexPath:indexPath];
                attr.frame = CGRectMake(itemX, rowStartY, itemWidth, itemHeight);
                [self.itemAttributes addObject:attr];
                self.itemAttributesByIndexPath[indexPath] = attr;

                rowUsed += gridCols;
                if (itemHeight > rowMaxHeight) rowMaxHeight = itemHeight;
            }

            // Finalize the last row
            if (rowMaxHeight > 0) {
                columnY[col] = rowStartY + rowMaxHeight + self.interItemSpacing;
            }
        }

        // Find the tallest column in this section row to determine the row height
        CGFloat sectionRowMaxY = sectionRowStartY;
        for (NSInteger c = 0; c < colsInRow; c++) {
            if (columnY[c] > sectionRowMaxY) sectionRowMaxY = columnY[c];
        }
        free(columnY);

        // Next section row starts after the tallest column in this row
        // Add inter-column spacing as inter-row spacing between section rows
        sectionRowStartY = sectionRowMaxY + (sectionRow < sectionRowCount - 1 ? self.interColumnSpacing : 0);
    }

    self.cachedContentSize = CGSizeMake(cv.bounds.size.width, sectionRowStartY + self.contentInsets.bottom);
}

- (CGSize)collectionViewContentSize {
    return self.cachedContentSize;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray *result = [NSMutableArray array];

    for (UICollectionViewLayoutAttributes *attr in self.headerAttributes) {
        if (CGRectIntersectsRect(attr.frame, rect)) {
            [result addObject:attr];
        }
    }
    for (UICollectionViewLayoutAttributes *attr in self.itemAttributes) {
        if (CGRectIntersectsRect(attr.frame, rect)) {
            [result addObject:attr];
        }
    }

    return result;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.itemAttributesByIndexPath[indexPath];
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind
                                                                    atIndexPath:(NSIndexPath *)indexPath {
    return self.headerAttributesByIndexPath[indexPath];
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    CGRect old = self.collectionView.bounds;
    return (CGRectGetWidth(newBounds) != CGRectGetWidth(old));
}

@end
