#import "HAStrategyResolver.h"
#import "HALovelaceParser.h"
#import "HAEntity.h"

@implementation HAStrategyResolver

+ (HALovelaceDashboard *)resolveDashboardWithStrategy:(NSDictionary *)strategyConfig
                                             entities:(NSDictionary<NSString *, HAEntity *> *)entities
                                            areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                                        entityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                       deviceAreaMap:(NSDictionary<NSString *, NSString *> *)deviceAreaMap
                                               floors:(NSArray *)floors
                                       entityRegistry:(NSArray *)entityRegistry {
    NSString *type = strategyConfig[@"type"];
    if (![type isKindOfClass:[NSString class]]) return nil;

    if ([type isEqualToString:@"original-states"]) {
        return [self resolveOriginalStatesWithConfig:strategyConfig
                                            entities:entities
                                           areaNames:areaNames
                                       entityAreaMap:entityAreaMap
                                      deviceAreaMap:deviceAreaMap];
    }

    if ([type isEqualToString:@"home"]) {
        return [self resolveHomeWithConfig:strategyConfig
                                  entities:entities
                                 areaNames:areaNames
                             entityAreaMap:entityAreaMap
                            deviceAreaMap:deviceAreaMap
                                    floors:floors];
    }

    NSLog(@"[HAStrategy] Unknown strategy type: %@", type);
    return nil;
}

#pragma mark - Original-States Strategy

+ (HALovelaceDashboard *)resolveOriginalStatesWithConfig:(NSDictionary *)strategyConfig
                                                entities:(NSDictionary<NSString *, HAEntity *> *)entities
                                               areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                                           entityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                          deviceAreaMap:(NSDictionary<NSString *, NSString *> *)deviceAreaMap {
    NSLog(@"[HAStrategy] Resolving original-states strategy");

    // 1. Filter entities using shouldShowInDefaultView
    NSMutableArray<HAEntity *> *filtered = [NSMutableArray array];
    for (HAEntity *entity in entities.allValues) {
        if ([entity shouldShowInDefaultView]) {
            [filtered addObject:entity];
        }
    }

    // 2. Parse strategy config for area ordering/hiding
    NSDictionary *areasConfig = strategyConfig[@"areas"];
    NSArray *areaOrder = nil;
    NSSet *hiddenAreas = nil;
    BOOL hideEntitiesWithoutArea = NO;

    if ([areasConfig isKindOfClass:[NSDictionary class]]) {
        if ([areasConfig[@"order"] isKindOfClass:[NSArray class]]) {
            areaOrder = areasConfig[@"order"];
        }
        if ([areasConfig[@"hidden"] isKindOfClass:[NSArray class]]) {
            hiddenAreas = [NSSet setWithArray:areasConfig[@"hidden"]];
        }
    }
    if ([strategyConfig[@"hide_entities_without_area"] isKindOfClass:[NSNumber class]]) {
        hideEntitiesWithoutArea = [strategyConfig[@"hide_entities_without_area"] boolValue];
    }

    // 3. Group entities by area_id
    NSMutableDictionary<NSString *, NSMutableArray<HAEntity *> *> *areaGroups = [NSMutableDictionary dictionary];
    NSMutableArray<HAEntity *> *ungrouped = [NSMutableArray array];

    for (HAEntity *entity in filtered) {
        NSString *areaId = entityAreaMap[entity.entityId];
        if (areaId.length > 0) {
            if (!areaGroups[areaId]) {
                areaGroups[areaId] = [NSMutableArray array];
            }
            [areaGroups[areaId] addObject:entity];
        } else {
            [ungrouped addObject:entity];
        }
    }

    // 4. Remove hidden areas
    if (hiddenAreas.count > 0) {
        for (NSString *hiddenId in hiddenAreas) {
            [areaGroups removeObjectForKey:hiddenId];
        }
    }

    // 5. Order areas: config order first, then alphabetically
    NSMutableArray<NSString *> *orderedAreaIds = [NSMutableArray array];
    if (areaOrder.count > 0) {
        for (NSString *areaId in areaOrder) {
            if (areaGroups[areaId]) {
                [orderedAreaIds addObject:areaId];
            }
        }
    }
    // Add remaining areas alphabetically
    NSMutableArray<NSString *> *remainingIds = [[areaGroups allKeys] mutableCopy];
    [remainingIds removeObjectsInArray:orderedAreaIds];
    [remainingIds sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *nameA = [areaNames[a] isKindOfClass:[NSString class]] ? areaNames[a] : a;
        NSString *nameB = [areaNames[b] isKindOfClass:[NSString class]] ? areaNames[b] : b;
        return [nameA caseInsensitiveCompare:nameB];
    }];
    [orderedAreaIds addObjectsFromArray:remainingIds];

    // 6. Generate card configs for each area
    NSMutableArray<NSDictionary *> *allCards = [NSMutableArray array];

    for (NSString *areaId in orderedAreaIds) {
        NSArray<HAEntity *> *areaEntities = areaGroups[areaId];
        NSString *areaName = areaNames[areaId] ?: areaId;

        NSArray<NSDictionary *> *cards = [self computeCardsForEntities:areaEntities areaTitle:areaName];
        [allCards addObjectsFromArray:cards];
    }

    // 7. Append ungrouped entities if not hidden
    if (!hideEntitiesWithoutArea && ungrouped.count > 0) {
        NSArray<NSDictionary *> *cards = [self computeCardsForEntities:ungrouped areaTitle:nil];
        [allCards addObjectsFromArray:cards];
    }

    // 8. Build HALovelaceDashboard with a single view
    NSMutableDictionary *viewDict = [NSMutableDictionary dictionary];
    viewDict[@"title"] = @"Overview";
    viewDict[@"cards"] = allCards;

    NSDictionary *dashDict = @{
        @"title": @"Overview",
        @"views": @[viewDict],
    };

    return [[HALovelaceDashboard alloc] initWithDictionary:dashDict];
}

#pragma mark - Home Strategy

+ (HALovelaceDashboard *)resolveHomeWithConfig:(NSDictionary *)strategyConfig
                                      entities:(NSDictionary<NSString *, HAEntity *> *)entities
                                     areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                                 entityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                deviceAreaMap:(NSDictionary<NSString *, NSString *> *)deviceAreaMap
                                        floors:(NSArray *)floors {
    NSLog(@"[HAStrategy] Resolving home strategy");

    // 1. Filter entities
    NSMutableArray<HAEntity *> *filtered = [NSMutableArray array];
    for (HAEntity *entity in entities.allValues) {
        if ([entity shouldShowInDefaultView]) {
            [filtered addObject:entity];
        }
    }

    // 2. Group by area
    NSMutableDictionary<NSString *, NSMutableArray<HAEntity *> *> *areaGroups = [NSMutableDictionary dictionary];
    NSMutableArray<HAEntity *> *ungrouped = [NSMutableArray array];
    NSMutableArray<HAEntity *> *mediaPlayers = [NSMutableArray array];

    for (HAEntity *entity in filtered) {
        if ([[entity domain] isEqualToString:@"media_player"]) {
            [mediaPlayers addObject:entity];
        }
        NSString *areaId = entityAreaMap[entity.entityId];
        if (areaId.length > 0) {
            if (!areaGroups[areaId]) {
                areaGroups[areaId] = [NSMutableArray array];
            }
            [areaGroups[areaId] addObject:entity];
        } else {
            [ungrouped addObject:entity];
        }
    }

    NSMutableArray<NSDictionary *> *views = [NSMutableArray array];

    // 3. Build overview view
    {
        NSMutableArray<NSDictionary *> *overviewCards = [NSMutableArray array];

        // Group areas by floor if floor data is available
        NSMutableArray<NSString *> *orderedAreaIds = nil;
        if (floors.count > 0) {
            orderedAreaIds = [NSMutableArray array];
            // Sort floors by level
            NSArray *sortedFloors = [floors sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                NSInteger levelA = [[a valueForKey:@"level"] integerValue];
                NSInteger levelB = [[b valueForKey:@"level"] integerValue];
                if (levelA < levelB) return NSOrderedAscending;
                if (levelA > levelB) return NSOrderedDescending;
                return NSOrderedSame;
            }];
            for (id floor in sortedFloors) {
                NSArray *floorAreaIds = [floor valueForKey:@"areaIds"];
                if ([floorAreaIds isKindOfClass:[NSArray class]]) {
                    for (NSString *aId in floorAreaIds) {
                        if (areaGroups[aId]) {
                            [orderedAreaIds addObject:aId];
                        }
                    }
                }
            }
            // Add any areas not on a floor
            for (NSString *aId in [areaGroups allKeys]) {
                if (![orderedAreaIds containsObject:aId]) {
                    [orderedAreaIds addObject:aId];
                }
            }
        } else {
            orderedAreaIds = [[[areaGroups allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                NSString *nameA = [areaNames[a] isKindOfClass:[NSString class]] ? areaNames[a] : a;
                NSString *nameB = [areaNames[b] isKindOfClass:[NSString class]] ? areaNames[b] : b;
                return [nameA caseInsensitiveCompare:nameB];
            }] mutableCopy];
        }

        // Summary counts
        NSInteger lightCount = 0, climateCount = 0, mediaCount = 0;
        for (HAEntity *e in filtered) {
            NSString *d = [e domain];
            if ([d isEqualToString:@"light"] && e.isOn) lightCount++;
            else if ([d isEqualToString:@"climate"]) climateCount++;
            else if ([d isEqualToString:@"media_player"] && (e.isPlaying || e.isPaused)) mediaCount++;
        }

        // Summary entities card
        NSMutableArray *summaryEntities = [NSMutableArray array];
        if (lightCount > 0) {
            [summaryEntities addObject:@{@"entity": @"light.placeholder",
                                         @"name": [NSString stringWithFormat:@"%ld lights on", (long)lightCount]}];
        }
        if (climateCount > 0) {
            [summaryEntities addObject:@{@"entity": @"climate.placeholder",
                                         @"name": [NSString stringWithFormat:@"%ld climate", (long)climateCount]}];
        }
        if (mediaCount > 0) {
            [summaryEntities addObject:@{@"entity": @"media_player.placeholder",
                                         @"name": [NSString stringWithFormat:@"%ld media playing", (long)mediaCount]}];
        }

        // Area cards with domain-specific generation
        for (NSString *areaId in orderedAreaIds) {
            NSArray<HAEntity *> *areaEntities = areaGroups[areaId];
            NSString *areaName = areaNames[areaId] ?: areaId;
            NSArray<NSDictionary *> *cards = [self computeCardsForEntities:areaEntities areaTitle:areaName];
            [overviewCards addObjectsFromArray:cards];
        }

        NSDictionary *overviewView = @{
            @"title": @"Home",
            @"path": @"home",
            @"cards": overviewCards,
        };
        [views addObject:overviewView];
    }

    // 4. Per-area subviews
    NSArray<NSString *> *sortedAreaIds = [[areaGroups allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *nameA = [areaNames[a] isKindOfClass:[NSString class]] ? areaNames[a] : a;
        NSString *nameB = [areaNames[b] isKindOfClass:[NSString class]] ? areaNames[b] : b;
        return [nameA caseInsensitiveCompare:nameB];
    }];
    for (NSString *areaId in sortedAreaIds) {
        NSArray<HAEntity *> *areaEntities = areaGroups[areaId];
        NSString *areaName = areaNames[areaId] ?: areaId;
        NSArray<NSDictionary *> *cards = [self computeCardsForEntities:areaEntities areaTitle:nil];

        NSDictionary *areaView = @{
            @"title": areaName,
            @"path": areaId,
            @"cards": cards,
        };
        [views addObject:areaView];
    }

    // 5. Media players view
    if (mediaPlayers.count > 0) {
        NSMutableArray<NSDictionary *> *mediaCards = [NSMutableArray array];
        for (HAEntity *mp in mediaPlayers) {
            [mediaCards addObject:@{@"type": @"media-control", @"entity": mp.entityId}];
        }
        [views addObject:@{
            @"title": @"Media",
            @"path": @"media",
            @"cards": mediaCards,
        }];
    }

    // 6. Other devices view (ungrouped)
    if (ungrouped.count > 0) {
        NSArray<NSDictionary *> *otherCards = [self computeCardsForEntities:ungrouped areaTitle:@"Other Devices"];
        [views addObject:@{
            @"title": @"Other",
            @"path": @"other",
            @"cards": otherCards,
        }];
    }

    NSDictionary *dashDict = @{
        @"title": @"Home",
        @"views": views,
    };

    return [[HALovelaceDashboard alloc] initWithDictionary:dashDict];
}

#pragma mark - Card Generation

/// Generate domain-specific card config dictionaries for a group of entities.
/// Used by both original-states and home strategies.
+ (NSArray<NSDictionary *> *)computeCardsForEntities:(NSArray<HAEntity *> *)entities
                                           areaTitle:(NSString *)areaTitle {
    if (entities.count == 0) return @[];

    // Separate entities by domain for domain-specific card types
    NSMutableArray<HAEntity *> *alarmEntities = [NSMutableArray array];
    NSMutableArray<HAEntity *> *climateEntities = [NSMutableArray array];
    NSMutableArray<HAEntity *> *mediaEntities = [NSMutableArray array];
    NSMutableArray<HAEntity *> *weatherEntities = [NSMutableArray array];
    NSMutableArray<HAEntity *> *cameraEntities = [NSMutableArray array];
    NSMutableArray<HAEntity *> *otherEntities = [NSMutableArray array];

    for (HAEntity *entity in entities) {
        NSString *domain = [entity domain];
        if ([domain isEqualToString:@"alarm_control_panel"]) {
            [alarmEntities addObject:entity];
        } else if ([domain isEqualToString:@"climate"]) {
            [climateEntities addObject:entity];
        } else if ([domain isEqualToString:@"media_player"]) {
            [mediaEntities addObject:entity];
        } else if ([domain isEqualToString:@"weather"]) {
            [weatherEntities addObject:entity];
        } else if ([domain isEqualToString:@"camera"]) {
            [cameraEntities addObject:entity];
        } else {
            [otherEntities addObject:entity];
        }
    }

    NSMutableArray<NSDictionary *> *cards = [NSMutableArray array];

    // Domain-specific cards
    for (HAEntity *e in alarmEntities) {
        [cards addObject:@{@"type": @"alarm-panel", @"entity": e.entityId}];
    }
    for (HAEntity *e in climateEntities) {
        [cards addObject:@{@"type": @"thermostat", @"entity": e.entityId}];
    }
    for (HAEntity *e in mediaEntities) {
        [cards addObject:@{@"type": @"media-control", @"entity": e.entityId}];
    }
    for (HAEntity *e in weatherEntities) {
        [cards addObject:@{@"type": @"weather-forecast", @"entity": e.entityId}];
    }
    for (HAEntity *e in cameraEntities) {
        [cards addObject:@{@"type": @"picture-entity", @"entity": e.entityId}];
    }

    // Separate scene/script entities from other entities for chip treatment
    NSMutableArray<HAEntity *> *sceneEntities = [NSMutableArray array];
    NSMutableArray<HAEntity *> *rowEntities = [NSMutableArray array];
    for (HAEntity *e in otherEntities) {
        NSString *d = [e domain];
        if ([d isEqualToString:@"scene"] || [d isEqualToString:@"script"]) {
            [sceneEntities addObject:e];
        } else {
            [rowEntities addObject:e];
        }
    }

    // Remaining entities go into an "entities" card, sorted by friendly name.
    // Scene/script entities become chip metadata on the same card.
    if (rowEntities.count > 0 || sceneEntities.count > 0) {
        [rowEntities sortUsingComparator:^NSComparisonResult(HAEntity *a, HAEntity *b) {
            return [[a friendlyName] caseInsensitiveCompare:[b friendlyName]];
        }];

        NSMutableArray *entityList = [NSMutableArray arrayWithCapacity:rowEntities.count];
        for (HAEntity *e in rowEntities) {
            [entityList addObject:e.entityId];
        }

        NSMutableDictionary *entitiesCard = [NSMutableDictionary dictionary];
        entitiesCard[@"type"] = @"entities";
        entitiesCard[@"entities"] = entityList;
        if (areaTitle.length > 0) {
            entitiesCard[@"title"] = areaTitle;
        }

        // Attach scene/script entities as chip metadata
        if (sceneEntities.count > 0) {
            [sceneEntities sortUsingComparator:^NSComparisonResult(HAEntity *a, HAEntity *b) {
                return [[a friendlyName] caseInsensitiveCompare:[b friendlyName]];
            }];

            NSMutableArray *sceneIds = [NSMutableArray arrayWithCapacity:sceneEntities.count];
            NSMutableDictionary *chipNames = [NSMutableDictionary dictionaryWithCapacity:sceneEntities.count];
            for (HAEntity *s in sceneEntities) {
                [sceneIds addObject:s.entityId];
                NSString *name = [s friendlyName];
                // Strip area name prefix (e.g. "Dylan's Bedroom Bedtime" -> "Bedtime")
                if (areaTitle.length > 0 && name.length >= areaTitle.length) {
                    NSString *namePrefix = [name substringToIndex:areaTitle.length];
                    if ([namePrefix localizedCaseInsensitiveCompare:areaTitle] == NSOrderedSame) {
                        NSString *stripped = [[name substringFromIndex:areaTitle.length]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        if (stripped.length > 0) name = stripped;
                    }
                }
                chipNames[s.entityId] = name;
            }
            entitiesCard[@"scene_entity_ids"] = sceneIds;
            entitiesCard[@"scene_chip_names"] = chipNames;
        }

        [cards addObject:entitiesCard];
    } else if (cards.count > 0 && areaTitle.length > 0) {
        // If there are only domain-specific cards, we still want the area title.
        // Prepend it to the first card if it doesn't have one.
        NSMutableDictionary *firstCard = [cards.firstObject mutableCopy];
        if (!firstCard[@"title"]) {
            firstCard[@"title"] = areaTitle;
            cards[0] = firstCard;
        }
    }

    return cards;
}

@end
