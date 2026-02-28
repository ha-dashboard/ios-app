#import "HALovelaceParser.h"
#import "HADashboardConfig.h"

#pragma mark - HALovelaceView

@implementation HALovelaceView
@end


#pragma mark - HALovelaceDashboard

@implementation HALovelaceDashboard

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _title = dict[@"title"] ?: @"Home";

        NSArray *viewDicts = dict[@"views"];
        if ([viewDicts isKindOfClass:[NSArray class]]) {
            NSMutableArray *views = [NSMutableArray arrayWithCapacity:viewDicts.count];
            for (NSDictionary *vd in viewDicts) {
                if (![vd isKindOfClass:[NSDictionary class]]) continue;
                HALovelaceView *view = [[HALovelaceView alloc] init];
                view.title = vd[@"title"] ?: [NSString stringWithFormat:@"View %lu", (unsigned long)(views.count + 1)];
                view.path  = vd[@"path"];
                view.icon  = vd[@"icon"];
                // Collect cards from both "cards" (classic) and "sections" (HA 2024+)
                NSMutableArray *allCards = [NSMutableArray array];
                NSArray *directCards = vd[@"cards"];
                if ([directCards isKindOfClass:[NSArray class]]) {
                    [allCards addObjectsFromArray:directCards];
                }
                NSArray *sections = vd[@"sections"];
                if ([sections isKindOfClass:[NSArray class]]) {
                    NSMutableArray *parsedSections = [NSMutableArray arrayWithCapacity:sections.count];
                    for (NSDictionary *section in sections) {
                        if (![section isKindOfClass:[NSDictionary class]]) continue;
                        NSString *sectionTitle = nil;
                        if ([section[@"title"] isKindOfClass:[NSString class]]) {
                            sectionTitle = section[@"title"];
                        }
                        NSArray *sectionCards = section[@"cards"];
                        if (![sectionCards isKindOfClass:[NSArray class]]) sectionCards = @[];
                        [allCards addObjectsFromArray:sectionCards];

                        NSString *sectionIcon = nil;
                        if ([section[@"icon"] isKindOfClass:[NSString class]]) {
                            sectionIcon = section[@"icon"];
                        }
                        [parsedSections addObject:@{
                            @"title": sectionTitle ?: @"",
                            @"icon": sectionIcon ?: @"",
                            @"cards": sectionCards
                        }];
                    }
                    view.rawSections = [parsedSections copy];
                }
                view.rawCards = [allCards copy];
                // Parse max_columns from HA view config (sections layout column cap)
                if ([vd[@"max_columns"] isKindOfClass:[NSNumber class]]) {
                    view.maxColumns = [vd[@"max_columns"] integerValue];
                }
                // Determine view type: explicit "type" field, or inferred from content
                NSString *explicitType = nil;
                if ([vd[@"type"] isKindOfClass:[NSString class]]) {
                    explicitType = vd[@"type"];
                }
                if ([explicitType isEqualToString:@"panel"]) {
                    view.viewType = @"panel";
                } else if ([explicitType isEqualToString:@"sidebar"]) {
                    view.viewType = @"sidebar";
                } else if (view.rawSections.count > 0) {
                    view.viewType = @"sections";
                } else {
                    view.viewType = @"masonry";
                }
                [views addObject:view];
            }
            _views = [views copy];
        } else {
            _views = @[];
        }
    }
    return self;
}

- (HALovelaceView *)viewAtIndex:(NSUInteger)index {
    if (index >= self.views.count) return nil;
    return self.views[index];
}

@end


#pragma mark - HALovelaceParser

@implementation HALovelaceParser

+ (HALovelaceDashboard *)parseDashboardFromDictionary:(NSDictionary *)dict {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    return [[HALovelaceDashboard alloc] initWithDictionary:dict];
}

+ (HADashboardConfig *)dashboardConfigFromView:(HALovelaceView *)view columns:(NSInteger)columns {
    if (!view) return nil;

    HADashboardConfig *config = [[HADashboardConfig alloc] init];
    config.title   = view.title;
    config.columns = columns > 0 ? columns : 3;

    NSMutableArray<HADashboardConfigSection *> *sections = [NSMutableArray array];
    NSMutableArray<HADashboardConfigItem *> *allItems = [NSMutableArray array];

    if (view.rawSections.count > 0) {
        // HA 2024+ sections view: each HA section becomes ONE config section (= one column)
        // All cards within an HA section become items within that single config section
        for (NSDictionary *rawSection in view.rawSections) {
            NSString *haSectionTitle = rawSection[@"title"];
            if (haSectionTitle.length == 0) haSectionTitle = nil;
            // Icon from section-level config (HA 2024.12+)
            NSString *haSectionIcon = nil;
            if ([rawSection[@"icon"] isKindOfClass:[NSString class]]) {
                haSectionIcon = rawSection[@"icon"];
            }
            NSArray *sectionCards = rawSection[@"cards"];

            // Look for heading cards to extract section title/icon (fallback)
            for (NSDictionary *card in sectionCards) {
                if (![card isKindOfClass:[NSDictionary class]]) continue;
                if ([card[@"type"] isEqualToString:@"heading"]) {
                    if (!haSectionTitle && [card[@"heading"] isKindOfClass:[NSString class]]) {
                        haSectionTitle = card[@"heading"];
                    }
                    if (!haSectionIcon && [card[@"icon"] isKindOfClass:[NSString class]]) {
                        haSectionIcon = card[@"icon"];
                    }
                }
            }

            // Collect all items from all cards in this HA section into a single config section
            NSMutableArray<HADashboardConfigSection *> *cardSections = [NSMutableArray array];
            NSMutableArray<HADashboardConfigItem *> *cardItems = [NSMutableArray array];
            for (NSDictionary *card in sectionCards) {
                if (![card isKindOfClass:[NSDictionary class]]) continue;
                if ([card[@"type"] isEqualToString:@"heading"]) continue;

                // Sections view: scale grid_options.columns from HA's section grid to our 12-col sub-grid
                NSInteger sectionGridMax = (view.maxColumns > 0) ? view.maxColumns : 4;
                [self processCard:card
                     sectionTitle:nil
                      sectionIcon:nil
                          columns:config.columns
                      gridColumns:0
                   sectionGridMax:sectionGridMax
                         sections:cardSections
                         allItems:cardItems];
            }

            // Merge all card-level sections into one column section
            HADashboardConfigSection *columnSection = [[HADashboardConfigSection alloc] init];
            columnSection.title = haSectionTitle;
            columnSection.icon = haSectionIcon;

            // Collect all items from sub-sections, preserving entities card structure
            NSMutableArray<HADashboardConfigItem *> *mergedItems = [NSMutableArray array];
            NSMutableArray<NSString *> *mergedEntityIds = [NSMutableArray array];
            for (HADashboardConfigSection *cs in cardSections) {
                // For composite cards (entities, badges, mini-graph), create a single item referencing the sub-section
                // Check the section cardType OR the first item's cardType for composite routing
                NSString *effectiveCardType = cs.cardType;
                if (cs.items.count > 0) {
                    NSString *firstItemType = cs.items.firstObject.cardType;
                    if ([firstItemType isEqualToString:@"entities"] || [firstItemType isEqualToString:@"badges"] || [firstItemType isEqualToString:@"graph"]) {
                        effectiveCardType = firstItemType;
                    }
                }
                BOOL isCompositeCard = ([effectiveCardType isEqualToString:@"entities"] ||
                                        [effectiveCardType containsString:@"badge"] ||
                                        [effectiveCardType isEqualToString:@"graph"]) && cs.entityIds.count > 0;
                if (isCompositeCard) {
                    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
                    item.entityId = cs.entityIds.firstObject;
                    // Clear composite card title if it duplicates the section header
                    if (haSectionTitle.length > 0 && [cs.title isEqualToString:haSectionTitle]) {
                        cs.title = nil;
                    }
                    item.displayName = cs.title;
                    item.cardType = (cs.items.count > 0) ? cs.items.firstObject.cardType : @"entities";
                    // Inherit columnSpan from the original card item
                    item.columnSpan = (cs.items.count > 0) ? cs.items.firstObject.columnSpan : 12;
                    item.rowSpan = 1;
                    item.entitiesSection = cs;
                    // For composite cards inside grids with headings, set headingIcon
                    // so the cell renders the heading ABOVE the card (not as internal title).
                    // Graph cards render their title internally (name label), so skip
                    // the headingIcon mechanism — clearing cs.title would lose the name.
                    BOOL isGraphCard = [item.cardType isEqualToString:@"graph"];
                    if (!isGraphCard && cs.icon.length > 0 && item.displayName.length > 0) {
                        item.customProperties = @{@"headingIcon": cs.icon};
                        // Clear the section title so it doesn't also show inside the card
                        cs.title = nil;
                    }
                    [mergedItems addObject:item];
                    [mergedEntityIds addObjectsFromArray:cs.entityIds];
                } else {
                    [mergedItems addObjectsFromArray:cs.items];
                    [mergedEntityIds addObjectsFromArray:cs.entityIds];
                }
            }

            // Dedup: strip inline heading from items whose heading text matches the section header
            // (prevents "House Climate" appearing as both section header AND inline heading)
            if (haSectionTitle.length > 0) {
                for (HADashboardConfigItem *item in mergedItems) {
                    if (item.displayName.length > 0 && [item.displayName isEqualToString:haSectionTitle]) {
                        if (item.customProperties[@"headingIcon"]) {
                            NSMutableDictionary *props = [item.customProperties mutableCopy];
                            [props removeObjectForKey:@"headingIcon"];
                            item.customProperties = [props copy];
                        }
                        item.displayName = nil;
                    }
                }
            }

            columnSection.items = [mergedItems copy];
            columnSection.entityIds = [mergedEntityIds copy];

            if (mergedItems.count > 0) {
                [sections addObject:columnSection];
                [allItems addObjectsFromArray:mergedItems];
            }
        }
    } else {
        // Classic view: one section per card
        for (NSDictionary *card in view.rawCards) {
            if (![card isKindOfClass:[NSDictionary class]]) continue;
            NSString *cardType = card[@"type"];
            if ([cardType isEqualToString:@"heading"]) continue;

            NSString *cardTitle = nil;
            if ([card[@"title"] isKindOfClass:[NSString class]]) {
                cardTitle = card[@"title"];
            }
            if (!cardTitle && [card[@"heading"] isKindOfClass:[NSString class]]) {
                cardTitle = card[@"heading"];
            }

            [self processCard:card
                 sectionTitle:cardTitle
                  sectionIcon:card[@"icon"]
                      columns:config.columns
                  gridColumns:0
               sectionGridMax:0
                     sections:sections
                     allItems:allItems];
        }
    }

    config.sections = [sections copy];
    config.items = [allItems copy];

    return config;
}

/// Process a single Lovelace card into a config section with items.
/// @param gridColumns If > 0, overrides the item's columnSpan (from a parent grid card's grid_options)
/// @param sectionGridMax HA sections view grid max (typically 4). When > 0 and < 12,
///        grid_options.columns values are scaled to our 12-column sub-grid. Pass 0 for non-sections views.
+ (void)processCard:(NSDictionary *)card
       sectionTitle:(NSString *)sectionTitle
        sectionIcon:(NSString *)sectionIcon
            columns:(NSInteger)maxColumns
        gridColumns:(NSInteger)gridColumns
     sectionGridMax:(NSInteger)sectionGridMax
           sections:(NSMutableArray<HADashboardConfigSection *> *)sections
           allItems:(NSMutableArray<HADashboardConfigItem *> *)allItems {

    NSString *cardType = card[@"type"];

    // Heading cards have no entity — skip them here. They are handled by the
    // grid unwrapping logic below which merges heading info into the first
    // content card. Headings cannot be standalone items because they break
    // sub-grid packing (e.g., thermostat(9) + vacuum(3) need to be on the
    // same row, which requires their headings to be merged into the same items).
    if ([cardType isEqualToString:@"heading"]) return;

    // Conditional cards: unwrap the inner card and attach conditions.
    // The inner card is shown only when all conditions are met (checked at display time).
    if ([cardType isEqualToString:@"conditional"]) {
        NSDictionary *innerCard = card[@"card"];
        NSArray *conditions = card[@"conditions"];
        if ([innerCard isKindOfClass:[NSDictionary class]]) {
            // Process the inner card recursively
            NSMutableArray<HADashboardConfigSection *> *innerSections = [NSMutableArray array];
            NSMutableArray<HADashboardConfigItem *> *innerItems = [NSMutableArray array];
            [self processCard:innerCard
                 sectionTitle:sectionTitle
                  sectionIcon:sectionIcon
                      columns:maxColumns
                  gridColumns:gridColumns
               sectionGridMax:sectionGridMax
                     sections:innerSections
                     allItems:innerItems];
            // Attach conditions to all resulting items
            if ([conditions isKindOfClass:[NSArray class]] && conditions.count > 0) {
                for (HADashboardConfigItem *item in innerItems) {
                    item.visibilityConditions = conditions;
                }
                for (HADashboardConfigSection *sec in innerSections) {
                    for (HADashboardConfigItem *item in sec.items) {
                        item.visibilityConditions = conditions;
                    }
                }
            }
            [sections addObjectsFromArray:innerSections];
            [allItems addObjectsFromArray:innerItems];
        }
        return;
    }

    // Grid cards often wrap [heading, content] pairs — extract heading as title
    // and recursively process the content sub-cards.
    // The grid card's own grid_options.columns determines the sub-grid span of its children.
    if ([cardType isEqualToString:@"grid"] ||
        [cardType isEqualToString:@"horizontal-stack"] ||
        [cardType isEqualToString:@"vertical-stack"]) {
        NSArray *subCards = card[@"cards"];
        if ([subCards isKindOfClass:[NSArray class]] && subCards.count > 0) {
            // Read this grid card's column configuration to determine child spans.
            // "columns" on the grid card = number of columns in the grid layout.
            // Each child gets 12/columns sub-grid span (out of 12-column grid).
            NSInteger parentGridCols = gridColumns; // inherit from above if set
            NSInteger gridCardColumns = [card[@"columns"] integerValue];
            if (gridCardColumns > 1) {
                parentGridCols = 12 / gridCardColumns; // e.g. columns:2 → each child gets 6
            }
            NSDictionary *gridOptions = card[@"grid_options"];
            if ([gridOptions isKindOfClass:[NSDictionary class]]) {
                NSInteger cols = [gridOptions[@"columns"] integerValue];
                if (cols > 0) parentGridCols = cols;
            }
            NSDictionary *layoutOptions = card[@"layout_options"];
            if ([layoutOptions isKindOfClass:[NSDictionary class]]) {
                NSInteger cols = [layoutOptions[@"grid_columns"] integerValue];
                if (cols > 0) parentGridCols = cols;
            }

            // Check if first sub-card is a heading
            NSDictionary *first = subCards.firstObject;
            NSString *gridTitle = sectionTitle;
            NSString *gridIcon = sectionIcon;
            NSUInteger startIdx = 0;
            if ([first isKindOfClass:[NSDictionary class]] &&
                [first[@"type"] isEqualToString:@"heading"]) {
                if (!gridTitle && [first[@"heading"] isKindOfClass:[NSString class]]) {
                    gridTitle = first[@"heading"];
                }
                if (!gridIcon && [first[@"icon"] isKindOfClass:[NSString class]]) {
                    gridIcon = first[@"icon"];
                }
                startIdx = 1;
            }

            // Determine if THIS grid has an explicit narrow column spec
            // (grid_options.columns like 9 or 3). If so, merge the heading into
            // the first content item to preserve sub-grid packing
            // (thermostat(9)+vacuum(3) side-by-side). If the grid has no explicit
            // column spec (like Printy), emit the heading as a standalone full-width
            // item — it won't conflict with packing.
            BOOL gridHasExplicitCols = NO;
            if ([gridOptions isKindOfClass:[NSDictionary class]] && [gridOptions[@"columns"] integerValue] > 0) {
                gridHasExplicitCols = YES;
            }
            if ([layoutOptions isKindOfClass:[NSDictionary class]] && [layoutOptions[@"grid_columns"] integerValue] > 0) {
                gridHasExplicitCols = YES;
            }
            // Also treat inherited gridColumns from parent as explicit
            if (gridColumns > 0) gridHasExplicitCols = YES;

            // Also emit heading as standalone when the first content card is a
            // horizontal-stack — merging the heading into one h-stack child creates
            // height mismatches (one child gets heading extra height, the other doesn't).
            BOOL firstContentIsHStack = NO;
            if (startIdx < subCards.count) {
                NSDictionary *firstContent = subCards[startIdx];
                if ([firstContent isKindOfClass:[NSDictionary class]] &&
                    [firstContent[@"type"] isEqualToString:@"horizontal-stack"]) {
                    firstContentIsHStack = YES;
                }
            }
            BOOL emitHeadingAsItem = (gridTitle && startIdx > 0 &&
                                      (!gridHasExplicitCols || firstContentIsHStack));
            if (emitHeadingAsItem) {
                HADashboardConfigItem *headingItem = [[HADashboardConfigItem alloc] init];
                headingItem.cardType = @"heading";
                headingItem.columnSpan = 12;
                headingItem.rowSpan = 1;
                headingItem.displayName = gridTitle;
                if (gridIcon) {
                    headingItem.customProperties = @{@"icon": gridIcon};
                }
                HADashboardConfigSection *headingSection = [[HADashboardConfigSection alloc] init];
                headingSection.cardType = @"heading";
                headingSection.items = @[headingItem];
                [sections addObject:headingSection];
                [allItems addObject:headingItem];
                // Clear heading so content items don't also get it
                gridTitle = nil;
                gridIcon = nil;
            }

            // For horizontal-stack, always auto-distribute children equally across
            // 12 sub-grid columns. This overrides any inherited gridColumns from a
            // parent grid card — the parent's column config determines the h-stack's
            // OWN width, not how its children are distributed internally.
            BOOL isHorizontalStack = [cardType isEqualToString:@"horizontal-stack"];
            if (isHorizontalStack) {
                // Count content cards (skip headings) to compute per-child span
                NSUInteger contentCount = 0;
                for (NSUInteger i = startIdx; i < subCards.count; i++) {
                    NSDictionary *sc = subCards[i];
                    if (![sc isKindOfClass:[NSDictionary class]]) continue;
                    if ([sc[@"type"] isEqualToString:@"heading"]) continue;
                    contentCount++;
                }
                if (contentCount > 1) {
                    parentGridCols = MAX(1, 12 / (NSInteger)contentCount);
                }
            }

            // Track item count before recursion so we can flag new items from stacks
            NSUInteger itemCountBefore = allItems.count;

            for (NSUInteger i = startIdx; i < subCards.count; i++) {
                NSDictionary *subCard = subCards[i];
                if (![subCard isKindOfClass:[NSDictionary class]]) continue;
                if ([subCard[@"type"] isEqualToString:@"heading"]) continue;

                [self processCard:subCard
                     sectionTitle:emitHeadingAsItem ? nil : gridTitle
                      sectionIcon:emitHeadingAsItem ? nil : gridIcon
                          columns:maxColumns
                      gridColumns:parentGridCols
                   sectionGridMax:sectionGridMax
                         sections:sections
                         allItems:allItems];
                // Only first sub-card gets the heading title
                gridTitle = nil;
                gridIcon = nil;
            }

            // Mark button/tile cards inside horizontal-stack as compact (pill-shaped)
            if (isHorizontalStack) {
                for (NSUInteger idx = itemCountBefore; idx < allItems.count; idx++) {
                    HADashboardConfigItem *stackItem = allItems[idx];
                    if ([stackItem.cardType isEqualToString:@"button"] ||
                        [stackItem.cardType isEqualToString:@"tile"]) {
                        NSMutableDictionary *props = [NSMutableDictionary dictionaryWithDictionary:stackItem.customProperties ?: @{}];
                        props[@"compact"] = @YES;
                        stackItem.customProperties = [props copy];
                    }
                }
            }
            return;
        }
    }

    // Use card title if no section title provided
    if (!sectionTitle) {
        if ([card[@"title"] isKindOfClass:[NSString class]]) {
            sectionTitle = card[@"title"];
        }
        if (!sectionTitle && [card[@"heading"] isKindOfClass:[NSString class]]) {
            sectionTitle = card[@"heading"];
        }
    }

    // Column span and row span from grid_options / layout_options
    NSInteger cardColumnSpan = gridColumns; // from parent grid card, or 0
    NSInteger cardRowSpan = 0; // 0 = auto (use per-card-type height)
    {
        NSDictionary *gridOptions = card[@"grid_options"];
        if ([gridOptions isKindOfClass:[NSDictionary class]]) {
            if (cardColumnSpan <= 0) {
                id colsValue = gridOptions[@"columns"];
                NSInteger cols = 0;
                if ([colsValue isKindOfClass:[NSNumber class]]) {
                    cols = [colsValue integerValue];
                } else if ([colsValue isKindOfClass:[NSString class]]) {
                    if ([[colsValue lowercaseString] isEqualToString:@"full"]) {
                        cols = 12; // full width in our sub-grid
                    } else {
                        cols = [colsValue integerValue];
                    }
                }
                if (cols > 0) {
                    // HA sections view uses a 12-column CSS grid natively.
                    // grid_options.columns values are already in terms of 12 columns.
                    cardColumnSpan = cols;
                }
            }
            // rows: number = explicit row units, "auto" or missing = auto height
            id rowsValue = gridOptions[@"rows"];
            if ([rowsValue isKindOfClass:[NSNumber class]]) {
                cardRowSpan = [rowsValue integerValue];
            } else if ([rowsValue isKindOfClass:[NSString class]] &&
                       ![[rowsValue lowercaseString] isEqualToString:@"auto"]) {
                cardRowSpan = [rowsValue integerValue];
            }
        }
        NSDictionary *layoutOptions = card[@"layout_options"];
        if ([layoutOptions isKindOfClass:[NSDictionary class]]) {
            if (cardColumnSpan <= 0) {
                NSInteger cols = [layoutOptions[@"grid_columns"] integerValue];
                if (cols > 0) cardColumnSpan = cols;
            }
            if (cardRowSpan <= 0) {
                id rowsValue = layoutOptions[@"grid_rows"];
                if ([rowsValue isKindOfClass:[NSNumber class]]) {
                    cardRowSpan = [rowsValue integerValue];
                }
            }
        }
    }
    // Default column span: HA sections view defaults tile/button/sensor to 6 (half-width,
    // two per row). Other card types (including standalone gauge) default to 12 (full width).
    // Gauge cards inside grid cards already have gridColumns set by the parent, so they
    // don't reach this default — only standalone gauges do, which should be full width.
    if (cardColumnSpan <= 0) {
        if ([cardType isEqualToString:@"tile"] ||
            [cardType isEqualToString:@"button"] ||
            [cardType isEqualToString:@"sensor"]) {
            cardColumnSpan = 6;
        } else {
            cardColumnSpan = 12;
        }
    }

    // Parse view_layout.position for sidebar view support
    NSString *viewLayoutPosition = nil;
    NSDictionary *viewLayout = card[@"view_layout"];
    if ([viewLayout isKindOfClass:[NSDictionary class]]) {
        if ([viewLayout[@"position"] isKindOfClass:[NSString class]]) {
            viewLayoutPosition = viewLayout[@"position"];
        }
    }

    // Extract entities from this card
    NSArray<NSDictionary *> *extracted = [self extractEntitiesFromCard:card];
    if (extracted.count == 0) return;

    // Collect all entity IDs and name overrides for this card
    NSMutableArray<NSString *> *entityIds = [NSMutableArray arrayWithCapacity:extracted.count];
    NSMutableDictionary<NSString *, NSString *> *nameOverrides = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in extracted) {
        NSString *eid = entry[@"entity_id"];
        if (eid) {
            [entityIds addObject:eid];
            if ([entry[@"name"] isKindOfClass:[NSString class]] && [entry[@"name"] length] > 0) {
                nameOverrides[eid] = entry[@"name"];
            }
        }
    }

    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.title    = sectionTitle;
    section.cardType = cardType;
    section.icon     = sectionIcon ?: card[@"icon"];
    section.entityIds = [entityIds copy];
    if (nameOverrides.count > 0) section.nameOverrides = [nameOverrides copy];
    // Store view_layout.position for sidebar view card routing
    if (viewLayoutPosition.length > 0) {
        NSMutableDictionary *props = section.customProperties
            ? [section.customProperties mutableCopy]
            : [NSMutableDictionary dictionary];
        props[@"viewLayoutPosition"] = viewLayoutPosition;
        section.customProperties = [props copy];
    }

    // Composite cards: emit ONE item representing the whole card with all entity IDs
    // - "entities": standard entities card
    // - "custom:badge-card": compact badge row
    // - "custom:mini-graph-card": graph card with optional secondary entity values
    BOOL isComposite = [cardType isEqualToString:@"entities"];
    NSString *compositeType = @"entities";
    if ([cardType containsString:@"badge"]) {
        isComposite = YES;
        compositeType = @"badges";
    } else if ([cardType containsString:@"mini-graph"]) {
        // Render as a single composite graph card with all entities
        isComposite = YES;
        compositeType = @"graph";
        if (!section.title && [card[@"name"] isKindOfClass:[NSString class]]) {
            section.title = card[@"name"];
        }
        // Pass mini-graph-card config to section customProperties for rendering
        NSMutableDictionary *graphProps = [NSMutableDictionary dictionary];
        if ([card[@"show"] isKindOfClass:[NSDictionary class]]) {
            graphProps[@"show"] = card[@"show"];
        }
        if ([card[@"color_thresholds"] isKindOfClass:[NSArray class]]) {
            graphProps[@"color_thresholds"] = card[@"color_thresholds"];
        }
        if ([card[@"icon"] isKindOfClass:[NSString class]]) {
            graphProps[@"graphIcon"] = card[@"icon"];
        }
        if ([card[@"line_width"] isKindOfClass:[NSNumber class]]) {
            graphProps[@"line_width"] = card[@"line_width"];
        }
        if ([card[@"lower_bound"] isKindOfClass:[NSNumber class]]) {
            graphProps[@"lower_bound"] = card[@"lower_bound"];
        }
        // Store per-entity display flags (show_state, show_graph, name, color)
        NSArray *rawEntities = card[@"entities"];
        if ([rawEntities isKindOfClass:[NSArray class]]) {
            NSMutableArray *entityConfigs = [NSMutableArray arrayWithCapacity:rawEntities.count];
            for (id entry in rawEntities) {
                if ([entry isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *cfg = [NSMutableDictionary dictionary];
                    NSDictionary *dict = (NSDictionary *)entry;
                    if (dict[@"entity"]) cfg[@"entity"] = dict[@"entity"];
                    if (dict[@"show_state"]) cfg[@"show_state"] = dict[@"show_state"];
                    if (dict[@"show_graph"]) cfg[@"show_graph"] = dict[@"show_graph"];
                    if (dict[@"name"]) cfg[@"name"] = dict[@"name"];
                    if (dict[@"color"]) cfg[@"color"] = dict[@"color"];
                    [entityConfigs addObject:[cfg copy]];
                } else if ([entry isKindOfClass:[NSString class]]) {
                    [entityConfigs addObject:@{@"entity": entry}];
                }
            }
            graphProps[@"entityConfigs"] = [entityConfigs copy];
        }
        if (graphProps.count > 0) {
            section.customProperties = [graphProps copy];
        }
    } else if ([cardType isEqualToString:@"history-graph"]) {
        // HA built-in history-graph: multi-entity graph with hours_to_show
        isComposite = YES;
        compositeType = @"graph";
        // history-graph uses "title" (already captured in sectionTitle/section.title)
        NSMutableDictionary *graphProps = [NSMutableDictionary dictionary];
        // hours_to_show determines the time window (default 24)
        NSNumber *hours = card[@"hours_to_show"];
        if ([hours isKindOfClass:[NSNumber class]]) {
            graphProps[@"hours_to_show"] = hours;
        }
        // Store per-entity name overrides
        NSArray *rawEntities = card[@"entities"];
        if ([rawEntities isKindOfClass:[NSArray class]]) {
            NSMutableArray *entityConfigs = [NSMutableArray arrayWithCapacity:rawEntities.count];
            for (id entry in rawEntities) {
                if ([entry isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *cfg = [NSMutableDictionary dictionary];
                    NSDictionary *dict = (NSDictionary *)entry;
                    if (dict[@"entity"]) cfg[@"entity"] = dict[@"entity"];
                    if (dict[@"name"]) cfg[@"name"] = dict[@"name"];
                    [entityConfigs addObject:[cfg copy]];
                } else if ([entry isKindOfClass:[NSString class]]) {
                    [entityConfigs addObject:@{@"entity": entry}];
                }
            }
            graphProps[@"entityConfigs"] = [entityConfigs copy];
        }
        if (graphProps.count > 0) {
            section.customProperties = [graphProps copy];
        }
    } else if ([cardType containsString:@"mushroom-chips"]) {
        // Render chips as a compact badge row (no name labels, smaller sizing)
        isComposite = YES;
        compositeType = @"badges";
        section.customProperties = @{@"chipStyle": @YES};
    }

    // Entities card: parse show_header_toggle and scene chip metadata
    if ([cardType isEqualToString:@"entities"]) {
        NSMutableDictionary *props = section.customProperties
            ? [section.customProperties mutableCopy]
            : [NSMutableDictionary dictionary];
        BOOL changed = NO;

        id toggle = card[@"show_header_toggle"];
        if ([toggle isKindOfClass:[NSNumber class]] && [toggle boolValue]) {
            props[@"showHeaderToggle"] = @YES;
            changed = YES;
        }

        // Scene chip metadata (from HAStrategyResolver-generated cards)
        NSArray *sceneIds = card[@"scene_entity_ids"];
        if ([sceneIds isKindOfClass:[NSArray class]] && [(NSArray *)sceneIds count] > 0) {
            props[@"sceneEntityIds"] = sceneIds;
            changed = YES;
        }
        NSDictionary *sceneChipNames = card[@"scene_chip_names"];
        if ([sceneChipNames isKindOfClass:[NSDictionary class]] && [(NSDictionary *)sceneChipNames count] > 0) {
            props[@"sceneChipNames"] = sceneChipNames;
            changed = YES;
        }

        if (changed) section.customProperties = [props copy];
    }

    if (isComposite && entityIds.count > 0) {
        HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
        item.entityId    = entityIds.firstObject;
        item.cardType    = compositeType;
        item.columnSpan  = cardColumnSpan;
        item.rowSpan     = cardRowSpan;
        section.items = @[item];
        [allItems addObject:item];
    } else {
        // Standard: one item per entity
        NSMutableArray<HADashboardConfigItem *> *sectionItems = [NSMutableArray arrayWithCapacity:extracted.count];
        for (NSUInteger i = 0; i < extracted.count; i++) {
            NSDictionary *entry = extracted[i];
            HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
            item.entityId    = entry[@"entity_id"];
            // Resolve display name — trim whitespace (HA uses " " as blank name override)
            NSString *entryName = [entry[@"name"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *cardName = [[card[@"name"] description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            // sectionTitle (from grid heading) takes priority for single-entity cards
            if (sectionTitle.length > 0 && extracted.count == 1) {
                item.displayName = sectionTitle;
                // Store heading icon for the cell to render above the card
                NSMutableDictionary *props = [NSMutableDictionary dictionaryWithDictionary:item.customProperties ?: @{}];
                if (sectionIcon) {
                    props[@"headingIcon"] = sectionIcon;
                }
                // Preserve card-level name override when heading claims displayName
                if (entryName.length > 0) {
                    props[@"nameOverride"] = entryName;
                } else if (cardName.length > 0) {
                    props[@"nameOverride"] = cardName;
                }
                if (props.count > 0) item.customProperties = [props copy];
            } else if (entryName.length > 0) {
                item.displayName = entryName;
            } else if (cardName.length > 0) {
                item.displayName = cardName;
            }
            item.cardType = cardType;
            item.columnSpan  = cardColumnSpan;
            item.rowSpan     = cardRowSpan;

            // Extract custom properties from the card config (merge with existing, e.g. headingIcon)
            NSMutableDictionary *props = [NSMutableDictionary dictionaryWithDictionary:item.customProperties ?: @{}];
            NSDictionary *dimensions = card[@"dimensions"];
            if ([dimensions isKindOfClass:[NSDictionary class]]) {
                if (dimensions[@"height"]) props[@"height"] = dimensions[@"height"];
                if (dimensions[@"aspect_ratio"]) props[@"aspect_ratio"] = dimensions[@"aspect_ratio"];
            }
            if (card[@"aspect_ratio"]) props[@"aspect_ratio"] = card[@"aspect_ratio"];
            // Button card icon height (e.g. "36px")
            if ([card[@"icon_height"] isKindOfClass:[NSString class]]) {
                props[@"icon_height"] = card[@"icon_height"];
            }
            // Thermostat: show_current_as_primary
            if (card[@"show_current_as_primary"]) props[@"show_current_as_primary"] = card[@"show_current_as_primary"];

            // Card-level icon override (tile, button, and other card types)
            if ([card[@"icon"] isKindOfClass:[NSString class]]) props[@"icon"] = card[@"icon"];
            // Card-level color override
            if ([card[@"color"] isKindOfClass:[NSString class]]) props[@"color"] = card[@"color"];
            // Button/tile card visibility flags — always set if present in card config.
            // JSON false → @NO (a valid NSNumber, not nil).
            for (NSString *visKey in @[@"show_name", @"show_state", @"show_icon"]) {
                id val = card[visKey];
                if (val) props[visKey] = val;
            }

            // Clock-weather card: extract sensor overrides and display config
            if ([cardType containsString:@"clock-weather"]) {
                if (card[@"temperature_sensor"]) props[@"temperature_sensor"] = card[@"temperature_sensor"];
                if (card[@"humidity_sensor"])    props[@"humidity_sensor"]    = card[@"humidity_sensor"];
                if (card[@"forecast_rows"])      props[@"forecast_rows"]      = card[@"forecast_rows"];
                if (card[@"time_format"])        props[@"time_format"]        = card[@"time_format"];
                if (card[@"date_pattern"])       props[@"date_pattern"]       = card[@"date_pattern"];
                if (card[@"locale"])             props[@"locale"]             = card[@"locale"];
            }

            // Calendar card: extract initial_view configuration
            if ([cardType isEqualToString:@"calendar"]) {
                if ([card[@"initial_view"] isKindOfClass:[NSString class]]) {
                    props[@"initial_view"] = card[@"initial_view"];
                }
            }

            // Camera overlay elements: extract entity IDs and tap actions from "elements" array
            // Used by custom:advanced-camera-card and similar camera card types
            if ([cardType hasPrefix:@"custom:"] && [cardType containsString:@"camera"]) {
                NSArray *elements = card[@"elements"];
                if ([elements isKindOfClass:[NSArray class]] && elements.count > 0) {
                    NSMutableArray *overlayElements = [NSMutableArray arrayWithCapacity:elements.count];
                    for (NSDictionary *elem in elements) {
                        if (![elem isKindOfClass:[NSDictionary class]]) continue;
                        NSString *elemEntity = elem[@"entity"];
                        if (![elemEntity isKindOfClass:[NSString class]] || elemEntity.length == 0) continue;
                        NSMutableDictionary *overlayEntry = [NSMutableDictionary dictionary];
                        overlayEntry[@"entity_id"] = elemEntity;
                        NSDictionary *tapAction = elem[@"tap_action"];
                        if ([tapAction isKindOfClass:[NSDictionary class]]) {
                            NSString *action = tapAction[@"action"];
                            if ([action isKindOfClass:[NSString class]] && action.length > 0) {
                                overlayEntry[@"tap_action"] = action;
                            }
                        }
                        [overlayElements addObject:[overlayEntry copy]];
                    }
                    if (overlayElements.count > 0) {
                        props[@"overlayElements"] = [overlayElements copy];
                    }
                }
            }

            // Vacuum card: extract configured commands and layout
            if ([cardType containsString:@"vacuum"]) {
                NSArray *commands = card[@"commands"];
                if ([commands isKindOfClass:[NSArray class]] && commands.count > 0) {
                    props[@"commands"] = commands;
                }
                if (card[@"icon_animation"]) props[@"icon_animation"] = card[@"icon_animation"];
                if (card[@"layout"]) props[@"layout"] = card[@"layout"];
            }

            // Gauge card: extract min, max, unit, severity, needle
            if ([cardType isEqualToString:@"gauge"]) {
                if ([card[@"min"] isKindOfClass:[NSNumber class]]) props[@"gauge_min"] = card[@"min"];
                if ([card[@"max"] isKindOfClass:[NSNumber class]]) props[@"gauge_max"] = card[@"max"];
                if ([card[@"unit"] isKindOfClass:[NSString class]]) props[@"unit"] = card[@"unit"];
                if ([card[@"needle"] isKindOfClass:[NSNumber class]]) props[@"needle"] = card[@"needle"];
                // Severity: HA supports both array format [{from,to,color},...] and
                // dictionary format {green: 0, yellow: 35, red: 85} where keys are
                // colors and values are the starting threshold for that color.
                id severity = card[@"severity"];
                if ([severity isKindOfClass:[NSArray class]] && [(NSArray *)severity count] > 0) {
                    props[@"severity"] = severity;
                } else if ([severity isKindOfClass:[NSDictionary class]] && [(NSDictionary *)severity count] > 0) {
                    // Convert dict format to sorted array format: [{from, to, color}, ...]
                    NSDictionary *severityDict = (NSDictionary *)severity;
                    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:severityDict.count];
                    for (NSString *color in severityDict) {
                        double threshold = [severityDict[color] doubleValue];
                        [entries addObject:@{@"color": color, @"threshold": @(threshold)}];
                    }
                    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                        return [a[@"threshold"] compare:b[@"threshold"]];
                    }];
                    // Build from/to ranges
                    double gaugeMax = [card[@"max"] isKindOfClass:[NSNumber class]] ? [card[@"max"] doubleValue] : 100.0;
                    NSMutableArray *ranges = [NSMutableArray arrayWithCapacity:entries.count];
                    for (NSUInteger i = 0; i < entries.count; i++) {
                        double from = [entries[i][@"threshold"] doubleValue];
                        double to = (i + 1 < entries.count) ? [entries[i + 1][@"threshold"] doubleValue] : gaugeMax;
                        [ranges addObject:@{@"from": @(from), @"to": @(to), @"color": entries[i][@"color"]}];
                    }
                    props[@"severity"] = ranges;
                }
            }

            if (props.count > 0) item.customProperties = [props copy];

            [sectionItems addObject:item];
        }
        section.items = [sectionItems copy];
        [allItems addObjectsFromArray:sectionItems];
    }

    [sections addObject:section];
}

+ (NSArray<NSDictionary *> *)extractEntitiesFromCard:(NSDictionary *)card {
    if (!card || ![card isKindOfClass:[NSDictionary class]]) return @[];

    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    NSString *type = card[@"type"];

    // Recursive: horizontal-stack, vertical-stack, grid
    if ([type isEqualToString:@"horizontal-stack"] ||
        [type isEqualToString:@"vertical-stack"] ||
        [type isEqualToString:@"grid"]) {
        NSArray *subCards = card[@"cards"];
        if ([subCards isKindOfClass:[NSArray class]]) {
            for (NSDictionary *subCard in subCards) {
                [results addObjectsFromArray:[self extractEntitiesFromCard:subCard]];
            }
        }
        return results;
    }

    // Conditional card
    if ([type isEqualToString:@"conditional"]) {
        NSDictionary *innerCard = card[@"card"];
        if ([innerCard isKindOfClass:[NSDictionary class]]) {
            [results addObjectsFromArray:[self extractEntitiesFromCard:innerCard]];
        }
        return results;
    }

    // Cards with an "entities" array: entities, glance
    NSArray *entities = card[@"entities"];
    if ([entities isKindOfClass:[NSArray class]]) {
        for (id entry in entities) {
            NSDictionary *parsed = [self parseEntityEntry:entry];
            if (parsed) [results addObject:parsed];
        }
    }

    // Cards with a single "entity" field: light, thermostat, button, sensor,
    // weather-forecast, media-control, entity, gauge, humidifier, etc.
    NSString *entity = card[@"entity"];
    if ([entity isKindOfClass:[NSString class]] && entity.length > 0) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"entity_id"] = entity;
        if (card[@"name"]) entry[@"name"] = card[@"name"];
        [results addObject:entry];
    }

    // Custom camera cards: extract camera_entity from cameras array
    if ([type hasPrefix:@"custom:"] && [type containsString:@"camera"]) {
        NSArray *cameras = card[@"cameras"];
        if ([cameras isKindOfClass:[NSArray class]]) {
            for (NSDictionary *cam in cameras) {
                if (![cam isKindOfClass:[NSDictionary class]]) continue;
                NSString *camEntity = cam[@"camera_entity"];
                if ([camEntity isKindOfClass:[NSString class]] && camEntity.length > 0) {
                    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                    entry[@"entity_id"] = camEntity;
                    if (card[@"name"]) entry[@"name"] = card[@"name"];
                    [results addObject:entry];
                }
            }
        }
    }

    // Mushroom chips card: extract entities from chips array
    if ([type isEqualToString:@"custom:mushroom-chips-card"]) {
        NSArray *chips = card[@"chips"];
        if ([chips isKindOfClass:[NSArray class]]) {
            for (NSDictionary *chip in chips) {
                if (![chip isKindOfClass:[NSDictionary class]]) continue;
                NSString *chipEntity = chip[@"entity"];
                if ([chipEntity isKindOfClass:[NSString class]] && chipEntity.length > 0) {
                    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                    entry[@"entity_id"] = chipEntity;
                    if (chip[@"name"]) entry[@"name"] = chip[@"name"];
                    [results addObject:entry];
                }
            }
        }
    }

    // Custom mini-graph, mushroom, and other cards with entities array already handled above.
    // Ensure the card-level "name" is applied to the first extracted entity when present.
    if (results.count > 0 && [card[@"name"] isKindOfClass:[NSString class]]) {
        NSMutableDictionary *first = [results.firstObject mutableCopy];
        if (!first[@"name"]) {
            first[@"name"] = card[@"name"];
            results[0] = first;
        }
    }

    // Picture-elements card: extract entities from elements
    if ([type isEqualToString:@"picture-elements"]) {
        NSArray *elements = card[@"elements"];
        if ([elements isKindOfClass:[NSArray class]]) {
            for (NSDictionary *element in elements) {
                if (![element isKindOfClass:[NSDictionary class]]) continue;
                NSString *elemEntity = element[@"entity"];
                if ([elemEntity isKindOfClass:[NSString class]] && elemEntity.length > 0) {
                    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                    entry[@"entity_id"] = elemEntity;
                    [results addObject:entry];
                }
            }
        }
    }

    return results;
}

#pragma mark - Helpers

/// Parse an entity entry which can be a plain string or a dictionary
+ (NSDictionary *)parseEntityEntry:(id)entry {
    if ([entry isKindOfClass:[NSString class]]) {
        // Plain entity ID string
        NSString *entityId = (NSString *)entry;
        if (entityId.length == 0) return nil;

        // Skip section headers (type: section, type: divider)
        if ([entityId hasPrefix:@"type:"]) return nil;

        return @{@"entity_id": entityId};
    }

    if ([entry isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)entry;

        // Skip non-entity entries like section headers, dividers, buttons, weblinks
        NSString *type = dict[@"type"];
        if (type && ([type isEqualToString:@"section"] ||
                     [type isEqualToString:@"divider"] ||
                     [type isEqualToString:@"weblink"] ||
                     [type isEqualToString:@"call-service"] ||
                     [type isEqualToString:@"cast"])) {
            return nil;
        }

        NSString *entityId = dict[@"entity"];
        if (![entityId isKindOfClass:[NSString class]] || entityId.length == 0) return nil;

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"entity_id"] = entityId;
        if (dict[@"name"]) result[@"name"] = dict[@"name"];
        return result;
    }

    return nil;
}

@end
