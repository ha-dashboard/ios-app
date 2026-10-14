#import "HAColumnarLayout.h"

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

    NSInteger totalSectionCount = [cv numberOfSections];
    if (totalSectionCount == 0) {
        self.cachedContentSize = CGSizeZero;
        return;
    }

    CGFloat totalWidth = cv.bounds.size.width - self.contentInsets.left - self.contentInsets.right;

    // Leading full-width sections (the view badge row) sit above the columns
    // and don't take a column; the rest are laid out as before, offset below.
    NSInteger firstColumnSection = 0;
    CGFloat sectionRowStartY = self.contentInsets.top;
    if ([self.delegate respondsToSelector:@selector(collectionView:layout:isFullWidthSection:)]) {
        while (firstColumnSection < totalSectionCount &&
               [self.delegate collectionView:cv layout:self isFullWidthSection:firstColumnSection]) {
            NSInteger itemCount = [cv numberOfItemsInSection:firstColumnSection];
            for (NSInteger item = 0; item < itemCount; item++) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:firstColumnSection];
                CGFloat itemHeight = 100.0;
                if ([self.delegate respondsToSelector:@selector(collectionView:layout:heightForItemAtIndexPath:itemWidth:)]) {
                    itemHeight = [self.delegate collectionView:cv layout:self heightForItemAtIndexPath:indexPath itemWidth:totalWidth];
                }
                UICollectionViewLayoutAttributes *attr =
                    [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
                attr.frame = CGRectMake(self.contentInsets.left, sectionRowStartY, totalWidth, itemHeight);
                [self.itemAttributes addObject:attr];
                self.itemAttributesByIndexPath[indexPath] = attr;
                sectionRowStartY += itemHeight + self.interItemSpacing;
            }
            firstColumnSection++;
        }
    }

    NSInteger sectionCount = totalSectionCount - firstColumnSection;
    if (sectionCount == 0) {
        self.cachedContentSize = CGSizeMake(cv.bounds.size.width, sectionRowStartY + self.contentInsets.bottom);
        return;
    }

    // Section spans (HA column_span, default 1).
    BOOL canQuerySpan = [self.delegate respondsToSelector:@selector(collectionView:layout:columnSpanForSection:)];
    NSInteger *sectionSpans = calloc(sectionCount, sizeof(NSInteger));
    NSInteger totalSpan = 0;
    for (NSInteger i = 0; i < sectionCount; i++) {
        NSInteger span = canQuerySpan
            ? [self.delegate collectionView:cv layout:self columnSpanForSection:firstColumnSection + i]
            : 1;
        sectionSpans[i] = MAX(span, 1);
        totalSpan += sectionSpans[i];
    }

    // Column capping: maxColumns limits the number of visible columns per row,
    // and (like HA) a view never has more columns than its sections span in total.
    NSInteger maxCols = self.maxColumns > 0 ? self.maxColumns : 4; // HA default is 4
    NSInteger effectiveCols = MIN(totalSpan, maxCols);

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

    // Pack sections into rows the way HA's sections grid does (CSS grid
    // auto-placement, grid-auto-flow: row): each section spans
    // min(column_span, columns) columns and goes to the next free slot at or
    // after the previous one, wrapping to a new row when it doesn't fit; a
    // gap it leaves behind stays empty. With every span 1 this is the old
    // "effectiveCols sections per row" grouping.
    NSInteger *sectionCol = calloc(sectionCount, sizeof(NSInteger));
    NSInteger *rowStarts = calloc(sectionCount + 1, sizeof(NSInteger)); // index of each row's first section
    NSInteger sectionRowCount = 0;
    NSInteger cursorCol = 0;
    for (NSInteger i = 0; i < sectionCount; i++) {
        sectionSpans[i] = MIN(sectionSpans[i], effectiveCols);
        if (i == 0 || cursorCol + sectionSpans[i] > effectiveCols) {
            rowStarts[sectionRowCount++] = i;
            cursorCol = 0;
        }
        sectionCol[i] = cursorCol;
        cursorCol += sectionSpans[i];
    }
    rowStarts[sectionRowCount] = sectionCount;

    for (NSInteger sectionRow = 0; sectionRow < sectionRowCount; sectionRow++) {
        NSInteger firstInRow = rowStarts[sectionRow];
        NSInteger lastInRow = rowStarts[sectionRow + 1];
        CGFloat sectionRowMaxY = sectionRowStartY;

        for (NSInteger i = firstInRow; i < lastInRow; i++) {
            NSInteger section = firstColumnSection + i;
            NSInteger span = sectionSpans[i];
            CGFloat columnX = self.contentInsets.left + sectionCol[i] * (columnWidth + self.interColumnSpacing);
            CGFloat sectionWidth = span * columnWidth + (span - 1) * self.interColumnSpacing;
            CGFloat columnY = sectionRowStartY;

            // Section header
            CGFloat headerHeight = 0;
            if ([self.delegate respondsToSelector:@selector(collectionView:layout:heightForHeaderInSection:)]) {
                headerHeight = [self.delegate collectionView:cv layout:self heightForHeaderInSection:section];
            }

            if (headerHeight > 0) {
                NSIndexPath *headerIndexPath = [NSIndexPath indexPathForItem:0 inSection:section];
                UICollectionViewLayoutAttributes *headerAttr =
                    [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                                                                  withIndexPath:headerIndexPath];
                headerAttr.frame = CGRectMake(columnX, columnY, sectionWidth, headerHeight);
                [self.headerAttributes addObject:headerAttr];
                self.headerAttributesByIndexPath[headerIndexPath] = headerAttr;
                columnY += headerHeight;
            }

            // Items in this section — sub-grid row packing (12 columns per spanned column)
            const NSInteger subGridColumns = 12 * span;
            CGFloat subGridSpacing = 8.0;
            NSInteger itemCount = [cv numberOfItemsInSection:section];
            NSInteger rowUsed = 0;     // sub-grid columns consumed in current row
            CGFloat rowStartY = columnY;
            CGFloat rowMaxHeight = 0;  // tallest item in current row

            BOOL canQueryHeading = [self.delegate respondsToSelector:@selector(collectionView:layout:isHeadingItemAtIndexPath:)];
            BOOL lastRowWasHeading = NO;

            for (NSInteger item = 0; item < itemCount; item++) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];

                // Get this item's sub-grid span
                NSInteger gridCols = subGridColumns; // default full width
                if ([self.delegate respondsToSelector:@selector(collectionView:layout:gridColumnsForItemAtIndexPath:)]) {
                    gridCols = [self.delegate collectionView:cv layout:self gridColumnsForItemAtIndexPath:indexPath];
                }
                gridCols = MAX(1, MIN(gridCols, subGridColumns));

                BOOL isHeading = canQueryHeading &&
                    [self.delegate collectionView:cv layout:self isHeadingItemAtIndexPath:indexPath];

                // Check if this item fits in the current row
                if (rowUsed > 0 && rowUsed + gridCols > subGridColumns) {
                    // Start a new row — skip spacing after heading rows
                    CGFloat rowGap = lastRowWasHeading ? 0 : self.interItemSpacing;
                    columnY = rowStartY + rowMaxHeight + rowGap;
                    rowStartY = columnY;
                    rowUsed = 0;
                    rowMaxHeight = 0;
                }

                // Calculate item width from sub-grid fraction
                CGFloat itemWidth;
                if (gridCols >= subGridColumns) {
                    itemWidth = sectionWidth;
                } else {
                    // Proportional width minus spacing between sub-grid items
                    itemWidth = floor((sectionWidth * gridCols) / subGridColumns - subGridSpacing * 0.5);
                }

                CGFloat itemX = columnX + (sectionWidth * rowUsed) / subGridColumns;
                if (rowUsed > 0) itemX += subGridSpacing * 0.5;

                CGFloat itemHeight = 100.0;
                if ([self.delegate respondsToSelector:@selector(collectionView:layout:heightForItemAtIndexPath:itemWidth:)]) {
                    itemHeight = [self.delegate collectionView:cv layout:self heightForItemAtIndexPath:indexPath itemWidth:itemWidth];
                }

                UICollectionViewLayoutAttributes *attr =
                    [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
                attr.frame = CGRectMake(itemX, rowStartY, itemWidth, itemHeight);
                [self.itemAttributes addObject:attr];
                self.itemAttributesByIndexPath[indexPath] = attr;

                rowUsed += gridCols;
                if (itemHeight > rowMaxHeight) rowMaxHeight = itemHeight;
                lastRowWasHeading = isHeading;
            }

            // Finalize the last row
            if (rowMaxHeight > 0) {
                columnY = rowStartY + rowMaxHeight + self.interItemSpacing;
            }
            // The section row is as tall as its tallest section
            if (columnY > sectionRowMaxY) sectionRowMaxY = columnY;
        }

        // Next section row starts after the tallest column in this row
        // Add inter-column spacing as inter-row spacing between section rows
        sectionRowStartY = sectionRowMaxY + (sectionRow < sectionRowCount - 1 ? self.interColumnSpacing : 0);
    }

    free(sectionSpans);
    free(sectionCol);
    free(rowStarts);

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
