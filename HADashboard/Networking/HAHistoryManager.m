#import "HAHistoryManager.h"
#import "HAAuthManager.h"
#import "HADemoDataProvider.h"

@interface HAHistoryManager ()
@property (nonatomic, strong) NSCache *cache;
@end

@implementation HAHistoryManager

+ (instancetype)sharedManager {
    static HAHistoryManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HAHistoryManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 30;
        _cache.totalCostLimit = 2 * 1024 * 1024; // 2MB limit
    }
    return self;
}

#pragma mark - Public API (hoursBack convenience wrappers)

- (void)fetchHistoryForEntityId:(NSString *)entityId
                      hoursBack:(NSInteger)hours
                     completion:(void (^)(NSArray *, NSError *))completion {
    NSDate *endDate = [NSDate date];
    NSDate *startDate = [NSDate dateWithTimeIntervalSinceNow:-hours * 3600];
    [self fetchHistoryForEntityId:entityId
                        startDate:startDate
                          endDate:endDate
                        maxPoints:100
                       completion:completion];
}

- (void)fetchTimelineForEntityId:(NSString *)entityId
                       hoursBack:(NSInteger)hours
                      completion:(void (^)(NSArray *, NSError *))completion {
    NSDate *endDate = [NSDate date];
    NSDate *startDate = [NSDate dateWithTimeIntervalSinceNow:-hours * 3600];
    [self fetchTimelineForEntityId:entityId
                         startDate:startDate
                           endDate:endDate
                        completion:completion];
}

#pragma mark - Public API (absolute date range)

- (void)fetchHistoryForEntityId:(NSString *)entityId
                      startDate:(NSDate *)startDate
                        endDate:(NSDate *)endDate
                      maxPoints:(NSUInteger)maxPoints
                     completion:(void (^)(NSArray *, NSError *))completion {
    if (!entityId || !completion) return;

    // In demo mode, return fake history data
    if ([[HAAuthManager sharedManager] isDemoMode]) {
        NSInteger hours = (NSInteger)([endDate timeIntervalSinceDate:startDate] / 3600.0);
        if (hours < 1) hours = 24;
        NSArray *fakePoints = [[HADemoDataProvider sharedProvider] historyPointsForEntityId:entityId hoursBack:hours];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(fakePoints, nil);
        });
        return;
    }

    NSUInteger effectiveMax = (maxPoints == 0) ? 100 : maxPoints;
    long startEpoch = (long)[startDate timeIntervalSince1970];
    long endEpoch = (long)[endDate timeIntervalSince1970];
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%ld_%ld", entityId, startEpoch, endEpoch];

    NSArray *cached = [self.cache objectForKey:cacheKey];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(cached, nil);
        });
        return;
    }

    NSURLRequest *request = [self requestForEntityId:entityId startDate:startDate endDate:endDate minimal:YES];
    if (!request) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [self errorWithMessage:@"Not configured"]);
        });
        return;
    }

    NSString *capturedKey = [cacheKey copy];
    NSUInteger capturedMax = effectiveMax;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }

        NSArray *points = [HAHistoryManager parseHistoryData:data maxPoints:capturedMax];
        if (points.count > 0) {
            [self.cache setObject:points forKey:capturedKey];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(points, nil);
        });
    }];
    [task resume];
}

- (void)fetchTimelineForEntityId:(NSString *)entityId
                       startDate:(NSDate *)startDate
                         endDate:(NSDate *)endDate
                      completion:(void (^)(NSArray *, NSError *))completion {
    if (!entityId || !completion) return;

    // In demo mode, return fake timeline data
    if ([[HAAuthManager sharedManager] isDemoMode]) {
        NSInteger hours = (NSInteger)([endDate timeIntervalSinceDate:startDate] / 3600.0);
        if (hours < 1) hours = 24;
        NSArray *fakeSegments = [[HADemoDataProvider sharedProvider] timelineSegmentsForEntityId:entityId hoursBack:hours];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(fakeSegments, nil);
        });
        return;
    }

    long startEpoch = (long)[startDate timeIntervalSince1970];
    long endEpoch = (long)[endDate timeIntervalSince1970];
    NSString *cacheKey = [NSString stringWithFormat:@"tl_%@_%ld_%ld", entityId, startEpoch, endEpoch];

    NSArray *cached = [self.cache objectForKey:cacheKey];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(cached, nil);
        });
        return;
    }

    NSURLRequest *request = [self requestForEntityId:entityId startDate:startDate endDate:endDate minimal:NO];
    if (!request) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [self errorWithMessage:@"Not configured"]);
        });
        return;
    }

    NSString *capturedKey = [cacheKey copy];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }

        NSArray *segments = [HAHistoryManager parseHistoryStateData:data];
        if (segments.count > 0) {
            [self.cache setObject:segments forKey:capturedKey];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(segments, nil);
        });
    }];
    [task resume];
}

- (void)clearCache {
    [self.cache removeAllObjects];
}

#pragma mark - Request Building

- (NSURLRequest *)requestForEntityId:(NSString *)entityId startDate:(NSDate *)startDate endDate:(NSDate *)endDate minimal:(BOOL)minimal {
    NSString *serverURL = [[HAAuthManager sharedManager] serverURL];
    NSString *token = [[HAAuthManager sharedManager] accessToken];
    if (!serverURL || !token) return nil;

    static NSDateFormatter *fmt;
    static dispatch_once_t fmtOnce;
    dispatch_once(&fmtOnce, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
        fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });
    NSString *startStr = [fmt stringFromDate:startDate];
    NSString *endStr = [fmt stringFromDate:endDate];

    NSString *urlStr;
    if (minimal) {
        urlStr = [NSString stringWithFormat:@"%@/api/history/period/%@?end_time=%@&filter_entity_id=%@&minimal_response&no_attributes",
                  serverURL, startStr, endStr, entityId];
    } else {
        urlStr = [NSString stringWithFormat:@"%@/api/history/period/%@?end_time=%@&filter_entity_id=%@&no_attributes",
                  serverURL, startStr, endStr, entityId];
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    return request;
}

- (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"HAHistoryManager" code:-1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - Parsing (extracted from HAGraphCardCell)

+ (NSArray *)parseHistoryData:(NSData *)data {
    return [self parseHistoryData:data maxPoints:100];
}

+ (NSArray *)parseHistoryData:(NSData *)data maxPoints:(NSUInteger)maxPoints {
    if (maxPoints == 0) maxPoints = 100;

    NSArray *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![result isKindOfClass:[NSArray class]] || result.count == 0) return @[];

    NSArray *states = result.firstObject;
    if (![states isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray *points = [NSMutableArray arrayWithCapacity:states.count];
    static NSDateFormatter *parseFmt6, *parseFmt3, *parseFmtNone;
    static dispatch_once_t parseFmtOnce;
    dispatch_once(&parseFmtOnce, ^{
        parseFmt6 = [[NSDateFormatter alloc] init];
        parseFmt6.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ";
        parseFmt6.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

        parseFmt3 = [[NSDateFormatter alloc] init];
        parseFmt3.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
        parseFmt3.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

        parseFmtNone = [[NSDateFormatter alloc] init];
        parseFmtNone.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        parseFmtNone.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });

    for (NSDictionary *entry in states) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *stateStr = entry[@"state"];
        if (!stateStr || [stateStr isEqualToString:@"unknown"] || [stateStr isEqualToString:@"unavailable"]) continue;

        double value = [stateStr doubleValue];
        if (value == 0 && ![stateStr isEqualToString:@"0"] && ![stateStr hasPrefix:@"0."]) continue;

        NSString *timeStr = entry[@"last_changed"] ?: entry[@"last_updated"];
        if (!timeStr) continue;

        NSDate *date = [parseFmt6 dateFromString:timeStr];
        if (!date) date = [parseFmt3 dateFromString:timeStr];
        if (!date) date = [parseFmtNone dateFromString:timeStr];
        if (!date) continue;

        [points addObject:@{
            @"value": @(value),
            @"timestamp": @([date timeIntervalSince1970])
        }];
    }

    // Downsample to maxPoints for performance on older devices
    if (points.count > maxPoints) {
        NSMutableArray *sampled = [NSMutableArray arrayWithCapacity:maxPoints];
        double step = (double)points.count / (double)maxPoints;
        for (NSUInteger i = 0; i < maxPoints; i++) {
            NSUInteger idx = (NSUInteger)(i * step);
            if (idx < points.count) {
                [sampled addObject:points[idx]];
            }
        }
        [sampled addObject:points.lastObject];
        return [sampled copy];
    }

    return [points copy];
}

+ (NSArray *)parseHistoryStateData:(NSData *)data {
    NSArray *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![result isKindOfClass:[NSArray class]] || result.count == 0) return @[];

    NSArray *states = result.firstObject;
    if (![states isKindOfClass:[NSArray class]] || states.count == 0) return @[];

    static NSDateFormatter *tlFmt6, *tlFmt3, *tlFmtNone;
    static dispatch_once_t tlFmtOnce;
    dispatch_once(&tlFmtOnce, ^{
        tlFmt6 = [[NSDateFormatter alloc] init];
        tlFmt6.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ";
        tlFmt6.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

        tlFmt3 = [[NSDateFormatter alloc] init];
        tlFmt3.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
        tlFmt3.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

        tlFmtNone = [[NSDateFormatter alloc] init];
        tlFmtNone.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        tlFmtNone.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });

    NSMutableArray *segments = [NSMutableArray array];
    NSString *prevState = nil;
    NSTimeInterval prevTimestamp = 0;

    for (NSDictionary *entry in states) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *stateStr = entry[@"state"];
        if (!stateStr) continue;

        NSString *timeStr = entry[@"last_changed"] ?: entry[@"last_updated"];
        if (!timeStr) continue;

        NSDate *date = [tlFmt6 dateFromString:timeStr];
        if (!date) date = [tlFmt3 dateFromString:timeStr];
        if (!date) date = [tlFmtNone dateFromString:timeStr];
        if (!date) continue;

        NSTimeInterval timestamp = [date timeIntervalSince1970];

        if (prevState && prevTimestamp > 0) {
            [segments addObject:@{
                @"state": prevState,
                @"start": @(prevTimestamp),
                @"end": @(timestamp),
            }];
        }

        prevState = stateStr;
        prevTimestamp = timestamp;
    }

    if (prevState && prevTimestamp > 0) {
        [segments addObject:@{
            @"state": prevState,
            @"start": @(prevTimestamp),
            @"end": @([[NSDate date] timeIntervalSince1970]),
        }];
    }

    return [segments copy];
}

@end
