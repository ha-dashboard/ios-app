#import "HALogbookManager.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "NSMutableURLRequest+HAHelpers.h"
#import "HALog.h"

@implementation HALogbookManager

+ (instancetype)sharedManager {
    static HALogbookManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HALogbookManager alloc] init];
    });
    return instance;
}

- (void)fetchRecentEntries:(NSInteger)hours
                completion:(void (^)(NSArray *, NSError *))completion {
    [self fetchEntriesForEntityId:nil hoursBack:hours completion:completion];
}

- (void)fetchEntriesForEntityId:(NSString *)entityId
                      hoursBack:(NSInteger)hours
                     completion:(void (^)(NSArray *, NSError *))completion {
    if (!completion) return;

    // Demo mode — return sample logbook entries
    if ([HAAuthManager sharedManager].isDemoMode) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([self demoLogbookEntriesForEntityId:entityId], nil);
        });
        return;
    }

    NSString *serverURL = [[HAAuthManager sharedManager] serverURL];
    NSString *token = [[HAAuthManager sharedManager] accessToken];
    if (!serverURL || !token) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"HALogbookManager" code:-1
                                           userInfo:@{NSLocalizedDescriptionKey: @"Not configured"}]);
        });
        return;
    }

    // Build timestamp for start time
    static NSDateFormatter *fmt;
    static dispatch_once_t fmtOnce;
    dispatch_once(&fmtOnce, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
        fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });

    NSDate *startDate = [NSDate dateWithTimeIntervalSinceNow:-hours * 3600];
    NSString *startStr = [fmt stringFromDate:startDate];

    NSMutableString *urlStr = [NSMutableString stringWithFormat:@"%@/api/logbook/%@", serverURL, startStr];
    if (entityId.length > 0) {
        [urlStr appendFormat:@"?entity=%@", entityId];
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"HALogbookManager" code:-2
                                           userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        });
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request ha_setAuthHeaders:token];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
                return;
            }

            NSError *jsonError = nil;
            NSArray *entries = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError) {
                HALogW(@"HALogbookManager", @"JSON parse error: %@", jsonError.localizedDescription);
            }
            if (![entries isKindOfClass:[NSArray class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(@[], nil);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                completion(entries, nil);
            });
        }];
    [task resume];
}

- (void)fetchEntriesForEntityIds:(NSArray<NSString *> *)entityIds
                       hoursBack:(NSInteger)hours
                      completion:(void (^)(NSArray *, NSError *))completion {
    if (!completion) return;

    // Demo mode
    if ([HAAuthManager sharedManager].isDemoMode) {
        NSMutableArray *entries = [NSMutableArray array];
        for (NSString *eid in entityIds) {
            [entries addObjectsFromArray:[self demoLogbookEntriesForEntityId:eid]];
        }
        // Sort by "when" descending
        [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"when"] compare:a[@"when"]];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(entries, nil); });
        return;
    }

    // Try WebSocket first (logbook/get_events) if connected
    HAConnectionManager *cm = [HAConnectionManager sharedManager];
    if (cm.isConnected) {
        NSString *startTime = [self iso8601StringForHoursAgo:hours];
        NSString *endTime   = [self iso8601StringForHoursAgo:0];

        NSMutableDictionary *command = [NSMutableDictionary dictionary];
        command[@"type"] = @"logbook/get_events";
        command[@"start_time"] = startTime;
        command[@"end_time"]   = endTime;
        if (entityIds.count > 0) {
            command[@"entity_ids"] = entityIds;
        }

        [cm sendCommand:command completion:^(id result, NSError *error) {
            if (error || ![result isKindOfClass:[NSArray class]]) {
                // WebSocket failed — fall back to REST
                [self fetchEntriesForEntityIdsViaREST:entityIds hoursBack:hours completion:completion];
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result, nil);
            });
        }];
        return;
    }

    // No WebSocket — use REST
    [self fetchEntriesForEntityIdsViaREST:entityIds hoursBack:hours completion:completion];
}

- (void)fetchEntriesForEntityIdsViaREST:(NSArray<NSString *> *)entityIds
                              hoursBack:(NSInteger)hours
                             completion:(void (^)(NSArray *, NSError *))completion {
    if (entityIds.count == 0) {
        [self fetchRecentEntries:hours completion:completion];
        return;
    }
    if (entityIds.count == 1) {
        [self fetchEntriesForEntityId:entityIds.firstObject hoursBack:hours completion:completion];
        return;
    }

    // REST API only supports single entity filter — fetch all and filter client-side
    NSSet *filterSet = [NSSet setWithArray:entityIds];
    [self fetchRecentEntries:hours completion:^(NSArray *entries, NSError *error) {
        if (error || !entries) {
            completion(entries, error);
            return;
        }
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *entry in entries) {
            NSString *eid = entry[@"entity_id"];
            if ([eid isKindOfClass:[NSString class]] && [filterSet containsObject:eid]) {
                [filtered addObject:entry];
            }
        }
        completion(filtered, nil);
    }];
}

- (NSArray *)demoLogbookEntriesForEntityId:(NSString *)entityId {
    // Generate realistic logbook entries with timestamps relative to now
    NSMutableArray *entries = [NSMutableArray array];

    NSDictionary *templates = @{
        @"light.sc_basic_on": @[
            @{@"name": @"Kitchen Light", @"state": @"on", @"message": @"turned on", @"hoursAgo": @(0.5)},
            @{@"name": @"Kitchen Light", @"state": @"off", @"message": @"turned off", @"hoursAgo": @(2.0)},
            @{@"name": @"Kitchen Light", @"state": @"on", @"message": @"turned on by automation", @"hoursAgo": @(6.0)},
        ],
        @"switch.in_meeting": @[
            @{@"name": @"In Meeting", @"state": @"on", @"message": @"turned on", @"hoursAgo": @(1.0)},
            @{@"name": @"In Meeting", @"state": @"off", @"message": @"turned off", @"hoursAgo": @(3.5)},
        ],
        @"cover.sc_position": @[
            @{@"name": @"Living Room Shutter", @"state": @"open", @"message": @"opened", @"hoursAgo": @(0.25)},
            @{@"name": @"Living Room Shutter", @"state": @"closed", @"message": @"closed by schedule", @"hoursAgo": @(8.0)},
        ],
    };

    NSArray *templateEntries = templates[entityId];
    if (!templateEntries) {
        // Generic entry for unknown entities
        templateEntries = @[
            @{@"name": entityId ?: @"Unknown", @"state": @"on", @"message": @"changed", @"hoursAgo": @(1.0)},
        ];
    }

    for (NSDictionary *tmpl in templateEntries) {
        NSString *when = [self iso8601StringForHoursAgo:[tmpl[@"hoursAgo"] doubleValue]];
        [entries addObject:@{
            @"entity_id": entityId ?: @"",
            @"name": tmpl[@"name"],
            @"state": tmpl[@"state"],
            @"message": tmpl[@"message"],
            @"when": when,
        }];
    }

    return entries;
}

- (NSString *)iso8601StringForHoursAgo:(double)hours {
    static NSDateFormatter *fmt;
    static dispatch_once_t fmtOnce;
    dispatch_once(&fmtOnce, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
        fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });
    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:-hours * 3600];
    return [fmt stringFromDate:date];
}

@end
