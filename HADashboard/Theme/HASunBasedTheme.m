#import "HASunBasedTheme.h"
#import "HATheme.h"
#import "HAConnectionManager.h"
#import "HAEntity.h"

static NSString *const kSunEntityId = @"sun.sun";

@interface HASunBasedTheme ()
@property (nonatomic, assign) BOOL running;
@property (nonatomic, readwrite, assign) BOOL isSunBelowHorizon;
@property (nonatomic, strong) NSTimer *transitionTimer;
@end

@implementation HASunBasedTheme

+ (instancetype)sharedInstance {
    static HASunBasedTheme *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HASunBasedTheme alloc] init];
    });
    return instance;
}

- (void)start {
    // iOS 13+ has native dark mode — don't interfere.
    // Use NSProcessInfo version check instead of @available because
    // @available checks the SDK version on x86_64 simulators running
    // legacy runtimes under RosettaSim, causing it to return YES even
    // on iOS 9.3.
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 13) {
        return;
    }

    if (self.running) return;
    self.running = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(entityDidUpdate:)
                                                 name:HAConnectionManagerEntityDidUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:HAThemeDidChangeNotification
                                               object:nil];

    [self evaluate];
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    [self.transitionTimer invalidate];
    self.transitionTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Evaluation

- (void)evaluate {
    if ([HATheme currentMode] != HAThemeModeAuto) return;

    HAEntity *sun = [[HAConnectionManager sharedManager] entityForId:kSunEntityId];
    if (!sun) return;

    // sun.sun state is "above_horizon" or "below_horizon"
    BOOL belowHorizon = [sun.state isEqualToString:@"below_horizon"];
    BOOL changed = (belowHorizon != self.isSunBelowHorizon);
    self.isSunBelowHorizon = belowHorizon;

    if (changed) {
        NSLog(@"[HASunBasedTheme] Sun is now %@ — switching to %@ mode",
              belowHorizon ? @"below horizon" : @"above horizon",
              belowHorizon ? @"dark" : @"light");
        [[NSNotificationCenter defaultCenter] postNotificationName:HAThemeDidChangeNotification object:nil];
    }

    // Schedule timer for the next transition
    [self scheduleNextTransition:sun];
}

- (void)scheduleNextTransition:(HAEntity *)sun {
    [self.transitionTimer invalidate];
    self.transitionTimer = nil;

    // Determine the next event: if below horizon → next_rising, else → next_setting
    NSString *key = self.isSunBelowHorizon ? @"next_rising" : @"next_setting";
    NSString *dateStr = sun.attributes[key];
    if (!dateStr) return;

    NSDate *nextEvent = [self parseISO8601:dateStr];
    if (!nextEvent) return;

    NSTimeInterval delay = [nextEvent timeIntervalSinceNow];
    if (delay <= 0) {
        // Already past — re-evaluate shortly (entity may be stale)
        delay = 30.0;
    }

    NSLog(@"[HASunBasedTheme] Next %@ in %.0f seconds", key, delay);

    __weak typeof(self) weakSelf = self;
    self.transitionTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                           target:weakSelf
                                                         selector:@selector(timerFired)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)timerFired {
    [self evaluate];
}

#pragma mark - Notifications

- (void)entityDidUpdate:(NSNotification *)notification {
    HAEntity *entity = notification.userInfo[@"entity"];
    if ([entity.entityId isEqualToString:kSunEntityId]) {
        [self evaluate];
    }
}

- (void)themeDidChange:(NSNotification *)notification {
    if ([HATheme currentMode] == HAThemeModeAuto) {
        [self evaluate];
    } else {
        // User switched away from Auto — cancel timer
        [self.transitionTimer invalidate];
        self.transitionTimer = nil;
    }
}

#pragma mark - Date Parsing

- (NSDate *)parseISO8601:(NSString *)string {
    if (!string) return nil;

    // NSDateFormatter with ISO 8601 format — available on all iOS versions
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        // HA sends: "2026-02-28T07:12:34+00:00" or "2026-02-28T07:12:34.123456+00:00"
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    });

    NSDate *date = [formatter dateFromString:string];
    if (!date) {
        // Try with fractional seconds
        static NSDateFormatter *fracFormatter;
        static dispatch_once_t fracOnce;
        dispatch_once(&fracOnce, ^{
            fracFormatter = [[NSDateFormatter alloc] init];
            fracFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            fracFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            fracFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ";
        });
        date = [fracFormatter dateFromString:string];
    }
    return date;
}

@end
