#import "HAAutoLayout.h"
#import "HACalendarCardCell.h"
#import "HADashboardConfig.h"
#import "HAAuthManager.h"
#import "HAHTTPClient.h"
#import "HADateUtils.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "UIFont+HACompat.h"

static const CGFloat kListHeight  = 280.0;
static const CGFloat kMonthHeight = 380.0;
static const CGFloat kPadding     = 12.0;
static const CGFloat kNavBarHeight = 30.0;
static const CGFloat kDayHeaderHeight = 30.0;
static const CGFloat kEventRowHeight  = 24.0;
static const CGFloat kMonthGridRowHeight = 28.0;

static UIColor *sDefaultEventColor;

#pragma mark - HACalendarEvent (internal model)

@interface HACalendarEvent : NSObject
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic, strong) NSDate *endDate;
@property (nonatomic, assign) BOOL allDay;
@property (nonatomic, copy) NSString *location;
@end

@implementation HACalendarEvent
@end

#pragma mark - HACalendarCardCell

@interface HACalendarCardCell ()
@property (nonatomic, assign) HACalendarViewMode viewMode;
@property (nonatomic, copy) NSArray<NSString *> *entityIds;
@property (nonatomic, strong) NSArray<HACalendarEvent *> *events;
@property (nonatomic, strong) id fetchTask;
@property (nonatomic, assign) BOOL needsEventsLoad;

// Navigation state
@property (nonatomic, strong) NSDate *displayStartDate; // start of current display window

// Navigation bar
@property (nonatomic, strong) UIButton *todayButton;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UILabel *dateRangeLabel;
@property (nonatomic, strong) UIButton *monthViewBtn;
@property (nonatomic, strong) UIButton *listViewBtn;

// Content
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) UIScrollView *listScrollView;

// Date formatting
@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@property (nonatomic, strong) NSCalendar *calendar;
@end

@implementation HACalendarCardCell

+ (void)initialize {
    if (self == [HACalendarCardCell class]) {
        sDefaultEventColor = [UIColor colorWithRed:0.30 green:0.60 blue:1.00 alpha:1.0];
    }
}

+ (CGFloat)preferredHeightForMode:(HACalendarViewMode)mode {
    return (mode == HACalendarViewModeMonth) ? kMonthHeight : kListHeight;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _viewMode = HACalendarViewModeList;
        _calendar = [NSCalendar currentCalendar];
        _displayStartDate = [_calendar startOfDayForDate:[NSDate date]];

        _timeFormatter = [[NSDateFormatter alloc] init];
        _timeFormatter.dateStyle = NSDateFormatterNoStyle;
        _timeFormatter.timeStyle = NSDateFormatterShortStyle;

        [self setupSubviews];
    }
    return self;
}

#pragma mark - Subview Setup

- (void)setupSubviews {
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.contentView.layer.cornerRadius = 14.0;
    self.contentView.clipsToBounds = YES;

    // --- Navigation bar ---
    UIView *navBar = [[UIView alloc] init];
    navBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:navBar];

    // Today button
    self.todayButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.todayButton setTitle:@"Today" forState:UIControlStateNormal];
    self.todayButton.titleLabel.font = [UIFont ha_systemFontOfSize:12 weight:HAFontWeightMedium];
    self.todayButton.layer.cornerRadius = 4;
    self.todayButton.layer.borderWidth = 0.5;
    self.todayButton.layer.borderColor = [[HATheme tertiaryTextColor] colorWithAlphaComponent:0.4].CGColor;
    self.todayButton.contentEdgeInsets = UIEdgeInsetsMake(2, 8, 2, 8);
    [self.todayButton addTarget:self action:@selector(todayTapped) forControlEvents:UIControlEventTouchUpInside];
    self.todayButton.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:self.todayButton];

    // Prev/Next arrows — SF Symbols (iOS 13+), fallback to text for iOS 9
    UIImage *chevLeft = nil;
    UIImage *chevRight = nil;
    if (@available(iOS 13.0, *)) {
        chevLeft = [UIImage systemImageNamed:@"chevron.left"
                     withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium]];
        chevRight = [UIImage systemImageNamed:@"chevron.right"
                      withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium]];
    }

    self.prevButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (chevLeft) {
        [self.prevButton setImage:chevLeft forState:UIControlStateNormal];
    } else {
        [self.prevButton setTitle:@"◀" forState:UIControlStateNormal];
    }
    [self.prevButton addTarget:self action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    self.prevButton.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:self.prevButton];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (chevRight) {
        [self.nextButton setImage:chevRight forState:UIControlStateNormal];
    } else {
        [self.nextButton setTitle:@"▶" forState:UIControlStateNormal];
    }
    [self.nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    self.nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:self.nextButton];

    // Date range label
    self.dateRangeLabel = [[UILabel alloc] init];
    self.dateRangeLabel.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightSemibold];
    self.dateRangeLabel.textColor = [HATheme primaryTextColor];
    self.dateRangeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:self.dateRangeLabel];

    // View mode icon buttons — SF Symbols (iOS 13+), fallback to text
    UIImage *calIcon = nil;
    UIImage *listIcon = nil;
    if (@available(iOS 13.0, *)) {
        calIcon = [UIImage systemImageNamed:@"calendar"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightRegular]];
        listIcon = [UIImage systemImageNamed:@"list.bullet"
                     withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightRegular]];
    }

    self.monthViewBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    if (calIcon) {
        [self.monthViewBtn setImage:calIcon forState:UIControlStateNormal];
    } else {
        [self.monthViewBtn setTitle:@"📅" forState:UIControlStateNormal];
    }
    [self.monthViewBtn addTarget:self action:@selector(switchToMonth) forControlEvents:UIControlEventTouchUpInside];
    self.monthViewBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:self.monthViewBtn];

    self.listViewBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    if (listIcon) {
        [self.listViewBtn setImage:listIcon forState:UIControlStateNormal];
    } else {
        [self.listViewBtn setTitle:@"☰" forState:UIControlStateNormal];
    }
    [self.listViewBtn addTarget:self action:@selector(switchToList) forControlEvents:UIControlEventTouchUpInside];
    self.listViewBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:self.listViewBtn];

    HAActivateConstraints(@[
        HACon([navBar.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8]),
        HACon([navBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding]),
        HACon([navBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding]),
        HACon([navBar.heightAnchor constraintEqualToConstant:kNavBarHeight]),

        HACon([self.todayButton.leadingAnchor constraintEqualToAnchor:navBar.leadingAnchor]),
        HACon([self.todayButton.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor]),

        HACon([self.prevButton.leadingAnchor constraintEqualToAnchor:self.todayButton.trailingAnchor constant:6]),
        HACon([self.prevButton.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor]),
        HACon([self.prevButton.widthAnchor constraintEqualToConstant:24]),

        HACon([self.nextButton.leadingAnchor constraintEqualToAnchor:self.prevButton.trailingAnchor constant:2]),
        HACon([self.nextButton.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor]),
        HACon([self.nextButton.widthAnchor constraintEqualToConstant:24]),

        HACon([self.dateRangeLabel.leadingAnchor constraintEqualToAnchor:self.nextButton.trailingAnchor constant:6]),
        HACon([self.dateRangeLabel.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor]),

        HACon([self.listViewBtn.trailingAnchor constraintEqualToAnchor:navBar.trailingAnchor]),
        HACon([self.listViewBtn.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor]),
        HACon([self.listViewBtn.widthAnchor constraintEqualToConstant:28]),

        HACon([self.monthViewBtn.trailingAnchor constraintEqualToAnchor:self.listViewBtn.leadingAnchor constant:-4]),
        HACon([self.monthViewBtn.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor]),
        HACon([self.monthViewBtn.widthAnchor constraintEqualToConstant:28]),
    ]);

    // --- Content container ---
    self.contentContainer = [[UIView alloc] init];
    self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.contentContainer];

    HAActivateConstraints(@[
        HACon([self.contentContainer.topAnchor constraintEqualToAnchor:navBar.bottomAnchor constant:4]),
        HACon([self.contentContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor]),
        HACon([self.contentContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]),
        HACon([self.contentContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]),
    ]);

    self.listScrollView = [[UIScrollView alloc] init];
    self.listScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.listScrollView.showsVerticalScrollIndicator = NO;
}

- (void)updateViewModeButtons {
    BOOL isList = (self.viewMode == HACalendarViewModeList);
    self.listViewBtn.tintColor = isList ? sDefaultEventColor : [HATheme secondaryTextColor];
    self.monthViewBtn.tintColor = !isList ? sDefaultEventColor : [HATheme secondaryTextColor];
}

#pragma mark - Configuration

- (void)configureWithEntityIds:(NSArray<NSString *> *)entityIds configItem:(HADashboardConfigItem *)configItem {
    self.entityIds = entityIds;
    self.displayStartDate = [self.calendar startOfDayForDate:[NSDate date]];

    NSString *initialView = configItem.customProperties[@"initial_view"];
    if ([initialView hasPrefix:@"list"]) {
        self.viewMode = HACalendarViewModeList;
    } else if ([initialView isEqualToString:@"dayGridMonth"]) {
        self.viewMode = HACalendarViewModeMonth;
    } else {
        self.viewMode = initialView ? HACalendarViewModeMonth : HACalendarViewModeList;
    }

    [self updateViewModeButtons];
    [self updateDateRangeLabel];
    [self showPlaceholder:@"Loading..."];
    self.needsEventsLoad = YES;
}

#pragma mark - Navigation

- (void)todayTapped {
    self.displayStartDate = [self.calendar startOfDayForDate:[NSDate date]];
    [self updateDateRangeLabel];
    [self refetch];
}

- (void)prevTapped {
    if (self.viewMode == HACalendarViewModeMonth) {
        self.displayStartDate = [self.calendar dateByAddingUnit:NSCalendarUnitMonth value:-1 toDate:self.displayStartDate options:0];
    } else {
        self.displayStartDate = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:-7 toDate:self.displayStartDate options:0];
    }
    [self updateDateRangeLabel];
    [self refetch];
}

- (void)nextTapped {
    if (self.viewMode == HACalendarViewModeMonth) {
        self.displayStartDate = [self.calendar dateByAddingUnit:NSCalendarUnitMonth value:1 toDate:self.displayStartDate options:0];
    } else {
        self.displayStartDate = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:7 toDate:self.displayStartDate options:0];
    }
    [self updateDateRangeLabel];
    [self refetch];
}

- (void)switchToList {
    if (self.viewMode == HACalendarViewModeList) return;
    self.viewMode = HACalendarViewModeList;
    [self updateViewModeButtons];
    [self updateDateRangeLabel];
    [self refetch];
}

- (void)switchToMonth {
    if (self.viewMode == HACalendarViewModeMonth) return;
    self.viewMode = HACalendarViewModeMonth;
    [self updateViewModeButtons];
    [self updateDateRangeLabel];
    [self refetch];
}

- (void)refetch {
    self.events = nil;
    [self cancelLoading];
    [self fetchEvents];
}

- (void)updateDateRangeLabel {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];

    if (self.viewMode == HACalendarViewModeMonth) {
        fmt.dateFormat = @"MMMM yyyy";
        NSDateComponents *comp = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:self.displayStartDate];
        NSDate *monthStart = [self.calendar dateFromComponents:comp];
        self.dateRangeLabel.text = [fmt stringFromDate:monthStart];
    } else {
        // "16 – 22 Feb 2026" style
        NSDate *start = self.displayStartDate;
        NSDate *end = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:6 toDate:start options:0];

        NSInteger startDay = [self.calendar component:NSCalendarUnitDay fromDate:start];
        NSInteger endDay = [self.calendar component:NSCalendarUnitDay fromDate:end];
        NSInteger startMonth = [self.calendar component:NSCalendarUnitMonth fromDate:start];
        NSInteger endMonth = [self.calendar component:NSCalendarUnitMonth fromDate:end];

        fmt.dateFormat = @"MMM";
        NSString *endMonthStr = [fmt stringFromDate:end];

        fmt.dateFormat = @"yyyy";
        NSString *year = [fmt stringFromDate:end];

        if (startMonth == endMonth) {
            self.dateRangeLabel.text = [NSString stringWithFormat:@"%ld – %ld %@ %@",
                                        (long)startDay, (long)endDay, endMonthStr, year];
        } else {
            fmt.dateFormat = @"MMM";
            NSString *startMonthStr = [fmt stringFromDate:start];
            self.dateRangeLabel.text = [NSString stringWithFormat:@"%ld %@ – %ld %@ %@",
                                        (long)startDay, startMonthStr, (long)endDay, endMonthStr, year];
        }
    }
}

#pragma mark - Deferred Loading

- (void)beginLoading {
    if (self.needsEventsLoad && self.entityIds.count > 0) {
        self.needsEventsLoad = NO;
        [self fetchEvents];
    }
}

- (void)cancelLoading {
    [[HAHTTPClient sharedClient] cancelTask:self.fetchTask];
    self.fetchTask = nil;
}

#pragma mark - Event Fetching

- (void)fetchEvents {
    NSString *serverURL = [[HAAuthManager sharedManager] serverURL];
    NSString *token = [[HAAuthManager sharedManager] accessToken];
    if (!serverURL || !token || self.entityIds.count == 0) {
        [self showPlaceholder:@"Not configured"];
        return;
    }

    NSDate *startDate;
    NSDate *endDate;

    if (self.viewMode == HACalendarViewModeMonth) {
        NSDateComponents *comp = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:self.displayStartDate];
        startDate = [self.calendar dateFromComponents:comp];
        comp.month += 1;
        endDate = [self.calendar dateFromComponents:comp];
    } else {
        startDate = self.displayStartDate;
        endDate = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:7 toDate:startDate options:0];
    }

    static NSDateFormatter *isoFmt;
    static dispatch_once_t fmtOnce;
    dispatch_once(&fmtOnce, ^{
        isoFmt = [[NSDateFormatter alloc] init];
        isoFmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.000'Z'";
        isoFmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        isoFmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });

    NSString *startStr = [isoFmt stringFromDate:startDate];
    NSString *endStr = [isoFmt stringFromDate:endDate];

    NSString *entityId = self.entityIds.firstObject;
    NSString *urlStr = [NSString stringWithFormat:@"%@/api/calendars/%@?start=%@&end=%@",
                        serverURL, entityId, startStr, endStr];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        [self showPlaceholder:@"Invalid URL"];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 15.0;

    __weak typeof(self) weakSelf = self;
    self.fetchTask = [[HAHTTPClient sharedClient] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf showPlaceholder:@"Failed to load"];
            });
            return;
        }

        NSArray *parsed = nil;
        if (data.length > 0) {
            parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }

        NSArray<HACalendarEvent *> *events = [HACalendarCardCell parseEvents:parsed];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.events = events;
            if (self.viewMode == HACalendarViewModeMonth) {
                [self renderMonthView];
            } else {
                [self renderListView];
            }
        });
    }];
}

#pragma mark - Event Parsing

+ (NSArray<HACalendarEvent *> *)parseEvents:(NSArray *)rawEvents {
    if (![rawEvents isKindOfClass:[NSArray class]]) return @[];

    static NSDateFormatter *dateFmt;
    static dispatch_once_t parseOnce;
    dispatch_once(&parseOnce, ^{
        dateFmt = [[NSDateFormatter alloc] init];
        dateFmt.dateFormat = @"yyyy-MM-dd";
        dateFmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });

    NSMutableArray<HACalendarEvent *> *events = [NSMutableArray arrayWithCapacity:rawEvents.count];
    for (NSDictionary *raw in rawEvents) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;

        HACalendarEvent *event = [[HACalendarEvent alloc] init];
        event.summary = raw[@"summary"] ?: @"(No title)";
        event.location = raw[@"location"];

        id startObj = raw[@"start"];
        if ([startObj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *startDict = startObj;
            if (startDict[@"dateTime"]) {
                event.startDate = [HADateUtils dateFromISO8601String:startDict[@"dateTime"]];
                event.allDay = NO;
            } else if (startDict[@"date"]) {
                event.startDate = [dateFmt dateFromString:startDict[@"date"]];
                event.allDay = YES;
            }
        } else if ([startObj isKindOfClass:[NSString class]]) {
            event.startDate = [HADateUtils dateFromISO8601String:startObj] ?: [dateFmt dateFromString:startObj];
            event.allDay = ([dateFmt dateFromString:startObj] != nil && [HADateUtils dateFromISO8601String:startObj] == nil);
        }

        id endObj = raw[@"end"];
        if ([endObj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *endDict = endObj;
            if (endDict[@"dateTime"]) {
                event.endDate = [HADateUtils dateFromISO8601String:endDict[@"dateTime"]];
            } else if (endDict[@"date"]) {
                event.endDate = [dateFmt dateFromString:endDict[@"date"]];
            }
        } else if ([endObj isKindOfClass:[NSString class]]) {
            event.endDate = [HADateUtils dateFromISO8601String:endObj] ?: [dateFmt dateFromString:endObj];
        }

        if (event.startDate) {
            [events addObject:event];
        }
    }

    [events sortUsingComparator:^NSComparisonResult(HACalendarEvent *a, HACalendarEvent *b) {
        return [a.startDate compare:b.startDate];
    }];

    return events;
}

#pragma mark - Multi-day Event Projection

/// Expand events across each day they span. Returns array of (date, event) pairs grouped by day.
- (NSArray<NSDictionary *> *)projectEventsIntoDays {
    NSMutableDictionary<NSNumber *, NSMutableArray<HACalendarEvent *> *> *dayMap = [NSMutableDictionary dictionary];
    NSMutableArray<NSDate *> *orderedDays = [NSMutableArray array];

    NSDate *rangeStart = self.displayStartDate;
    NSDate *rangeEnd;
    if (self.viewMode == HACalendarViewModeMonth) {
        NSDateComponents *comp = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:self.displayStartDate];
        comp.month += 1;
        rangeEnd = [self.calendar dateFromComponents:comp];
    } else {
        rangeEnd = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:7 toDate:rangeStart options:0];
    }

    for (HACalendarEvent *event in self.events) {
        NSDate *eventStart = [self.calendar startOfDayForDate:event.startDate];
        NSDate *eventEnd = event.endDate ? [self.calendar startOfDayForDate:event.endDate] : eventStart;

        // For all-day events, the end date is exclusive (e.g., Feb 17-18 means just Feb 17)
        // But for multi-day all-day events, we project across all days
        if (event.allDay && event.endDate) {
            // End date is exclusive in HA all-day events, so subtract 1 day
            eventEnd = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:eventEnd options:0];
        }

        // Project across each day the event touches within our display range
        NSDate *day = [eventStart compare:rangeStart] == NSOrderedAscending ? rangeStart : eventStart;
        while ([day compare:eventEnd] != NSOrderedDescending && [day compare:rangeEnd] == NSOrderedAscending) {
            NSNumber *dayKey = @((long)[[self.calendar startOfDayForDate:day] timeIntervalSince1970]);
            if (!dayMap[dayKey]) {
                dayMap[dayKey] = [NSMutableArray array];
                [orderedDays addObject:[self.calendar startOfDayForDate:day]];
            }
            [dayMap[dayKey] addObject:event];
            day = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
        }
    }

    // Sort days chronologically
    [orderedDays sortUsingComparator:^NSComparisonResult(NSDate *a, NSDate *b) {
        return [a compare:b];
    }];

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDate *d in orderedDays) {
        NSNumber *dayKey = @((long)[[self.calendar startOfDayForDate:d] timeIntervalSince1970]);
        [result addObject:@{@"date": d, @"events": dayMap[dayKey]}];
    }
    return result;
}

#pragma mark - List View Rendering

- (void)renderListView {
    for (UIView *v in self.contentContainer.subviews) [v removeFromSuperview];

    if (self.events.count == 0) {
        [self showPlaceholder:@"No upcoming events"];
        return;
    }

    [self.contentContainer addSubview:self.listScrollView];
    HAActivateConstraints(@[
        HACon([self.listScrollView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor]),
        HACon([self.listScrollView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor]),
        HACon([self.listScrollView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor]),
        HACon([self.listScrollView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor]),
    ]);
    // Remove old scroll content
    for (UIView *v in self.listScrollView.subviews) [v removeFromSuperview];

    NSArray<NSDictionary *> *dayGroups = [self projectEventsIntoDays];
    CGFloat yOffset = 0;
    CGFloat width = self.contentView.bounds.size.width;

    for (NSUInteger i = 0; i < dayGroups.count; i++) {
        NSDate *day = dayGroups[i][@"date"];
        NSArray<HACalendarEvent *> *group = dayGroups[i][@"events"];

        // Separator line above each day group (except first)
        if (i > 0) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(kPadding, yOffset, width - kPadding * 2, 0.5)];
            sep.backgroundColor = [[HATheme tertiaryTextColor] colorWithAlphaComponent:0.2];
            [self.listScrollView addSubview:sep];
            yOffset += 6;
        }

        // Day header: "Monday  16 February 2026" — HA style
        UIView *header = [self makeDayHeader:day y:yOffset width:width];
        [self.listScrollView addSubview:header];
        yOffset += kDayHeaderHeight;

        // Events
        for (HACalendarEvent *event in group) {
            UIView *row = [self makeEventRow:event y:yOffset width:width];
            [self.listScrollView addSubview:row];
            yOffset += kEventRowHeight;
        }

        yOffset += 4;
    }

    self.listScrollView.contentSize = CGSizeMake(width, yOffset + kPadding);
}

- (NSString *)dayNameForDate:(NSDate *)date {
    NSDate *today = [self.calendar startOfDayForDate:[NSDate date]];
    NSDate *tomorrow = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0];
    if ([self.calendar isDate:date inSameDayAsDate:today]) return @"Today";
    if ([self.calendar isDate:date inSameDayAsDate:tomorrow]) return @"Tomorrow";

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"EEEE";
    return [fmt stringFromDate:date];
}

- (UIView *)makeDayHeader:(NSDate *)date y:(CGFloat)y width:(CGFloat)width {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, kDayHeaderHeight)];

    // Day name on left (e.g. "Monday" or "Today")
    UILabel *dayName = [[UILabel alloc] init];
    dayName.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightSemibold];
    dayName.textColor = [HATheme primaryTextColor];
    dayName.text = [self dayNameForDate:date];
    dayName.frame = CGRectMake(kPadding, 4, 120, kDayHeaderHeight - 4);
    [header addSubview:dayName];

    // Full date on right (e.g. "16 February 2026")
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"d MMMM yyyy";
    UILabel *fullDate = [[UILabel alloc] init];
    fullDate.font = [UIFont systemFontOfSize:12];
    fullDate.textColor = [HATheme secondaryTextColor];
    fullDate.text = [fmt stringFromDate:date];
    fullDate.textAlignment = NSTextAlignmentRight;
    fullDate.frame = CGRectMake(width / 2, 4, width / 2 - kPadding, kDayHeaderHeight - 4);
    [header addSubview:fullDate];

    return header;
}

- (UIView *)makeEventRow:(HACalendarEvent *)event y:(CGFloat)y width:(CGFloat)width {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, kEventRowHeight)];

    // Colored dot
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(kPadding, (kEventRowHeight - 8) / 2, 8, 8)];
    dot.backgroundColor = sDefaultEventColor;
    dot.layer.cornerRadius = 4;
    [row addSubview:dot];

    // Time label — show range "17:30 - 18:00" or "All day"
    UILabel *timeLabel = [[UILabel alloc] init];
    timeLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:11 weight:HAFontWeightRegular];
    timeLabel.textColor = [HATheme secondaryTextColor];

    if (event.allDay) {
        timeLabel.text = @"All day";
    } else {
        NSString *start = [self.timeFormatter stringFromDate:event.startDate];
        if (event.endDate) {
            NSString *end = [self.timeFormatter stringFromDate:event.endDate];
            timeLabel.text = [NSString stringWithFormat:@"%@ - %@", start, end];
        } else {
            timeLabel.text = start;
        }
    }

    CGFloat timeX = kPadding + 14;
    CGFloat timeWidth = 100;
    timeLabel.frame = CGRectMake(timeX, 0, timeWidth, kEventRowHeight);
    [row addSubview:timeLabel];

    // Summary label
    UILabel *summaryLabel = [[UILabel alloc] init];
    summaryLabel.font = [UIFont systemFontOfSize:13];
    summaryLabel.textColor = [HATheme primaryTextColor];
    summaryLabel.text = event.summary;
    summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    CGFloat summaryX = timeX + timeWidth + 4;
    summaryLabel.frame = CGRectMake(summaryX, 0, width - summaryX - kPadding, kEventRowHeight);
    [row addSubview:summaryLabel];

    return row;
}

#pragma mark - Month View Rendering

- (void)renderMonthView {
    for (UIView *v in self.contentContainer.subviews) [v removeFromSuperview];

    CGFloat width = self.contentView.bounds.size.width;

    // Day-of-week header row
    CGFloat dayWidth = (width - kPadding * 2) / 7.0;
    NSArray *weekdaySymbols = self.calendar.veryShortWeekdaySymbols;
    NSInteger firstWeekday = self.calendar.firstWeekday;

    for (NSInteger i = 0; i < 7; i++) {
        NSInteger symbolIndex = ((firstWeekday - 1) + i) % 7;
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(kPadding + i * dayWidth, 0, dayWidth, 20)];
        label.font = [UIFont ha_systemFontOfSize:10 weight:HAFontWeightMedium];
        label.textColor = [HATheme secondaryTextColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.text = weekdaySymbols[symbolIndex];
        [self.contentContainer addSubview:label];
    }

    // Month grid calculations
    NSDateComponents *comp = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:self.displayStartDate];
    NSDate *firstOfMonth = [self.calendar dateFromComponents:comp];
    NSInteger weekdayOfFirst = [self.calendar component:NSCalendarUnitWeekday fromDate:firstOfMonth];
    NSInteger offset = ((weekdayOfFirst - firstWeekday) + 7) % 7;
    NSRange daysInMonth = [self.calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:firstOfMonth];

    NSDate *now = [NSDate date];
    NSInteger todayDay = [self.calendar component:NSCalendarUnitDay fromDate:now];
    BOOL isCurrentMonth = ([self.calendar component:NSCalendarUnitMonth fromDate:now] == comp.month &&
                           [self.calendar component:NSCalendarUnitYear fromDate:now] == comp.year);

    // Build set of days with events (project multi-day events)
    NSMutableSet<NSNumber *> *eventDays = [NSMutableSet set];
    for (HACalendarEvent *event in self.events) {
        NSDate *eventStart = [self.calendar startOfDayForDate:event.startDate];
        NSDate *eventEnd = event.endDate ? [self.calendar startOfDayForDate:event.endDate] : eventStart;
        if (event.allDay && event.endDate) {
            eventEnd = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:eventEnd options:0];
        }

        NSDate *day = eventStart;
        while ([day compare:eventEnd] != NSOrderedDescending) {
            NSInteger dayNum = [self.calendar component:NSCalendarUnitDay fromDate:day];
            NSInteger dayMonth = [self.calendar component:NSCalendarUnitMonth fromDate:day];
            if (dayMonth == comp.month) {
                [eventDays addObject:@(dayNum)];
            }
            day = [self.calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
        }
    }

    CGFloat gridY = 22;
    for (NSInteger row = 0; row < 6; row++) {
        for (NSInteger col = 0; col < 7; col++) {
            NSInteger cellIndex = row * 7 + col;
            NSInteger dayNum = cellIndex - offset + 1;

            CGFloat x = kPadding + col * dayWidth;
            CGFloat y = gridY + row * kMonthGridRowHeight;

            if (dayNum < 1 || dayNum > (NSInteger)daysInMonth.length) continue;

            UILabel *dayLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, y, dayWidth, kMonthGridRowHeight - 4)];
            dayLabel.font = [UIFont systemFontOfSize:13];
            dayLabel.textAlignment = NSTextAlignmentCenter;
            dayLabel.text = [NSString stringWithFormat:@"%ld", (long)dayNum];

            BOOL isToday = (isCurrentMonth && dayNum == todayDay);
            if (isToday) {
                dayLabel.textColor = [UIColor whiteColor];
                dayLabel.backgroundColor = sDefaultEventColor;
                dayLabel.layer.cornerRadius = (kMonthGridRowHeight - 4) / 2;
                dayLabel.layer.masksToBounds = YES;
            } else {
                dayLabel.textColor = [HATheme primaryTextColor];
            }

            [self.contentContainer addSubview:dayLabel];

            if ([eventDays containsObject:@(dayNum)] && !isToday) {
                UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(x + dayWidth / 2 - 2,
                                                                       y + kMonthGridRowHeight - 6, 4, 4)];
                dot.backgroundColor = sDefaultEventColor;
                dot.layer.cornerRadius = 2;
                [self.contentContainer addSubview:dot];
            }
        }
    }

    // Upcoming events below grid
    CGFloat listTop = gridY + 6 * kMonthGridRowHeight + 4;

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(kPadding, listTop, width - kPadding * 2, 0.5)];
    sep.backgroundColor = [[HATheme tertiaryTextColor] colorWithAlphaComponent:0.3];
    [self.contentContainer addSubview:sep];
    listTop += 6;

    NSDate *today = [self.calendar startOfDayForDate:now];
    NSMutableArray<HACalendarEvent *> *upcoming = [NSMutableArray array];
    for (HACalendarEvent *event in self.events) {
        if ([event.startDate compare:today] != NSOrderedAscending) {
            [upcoming addObject:event];
            if (upcoming.count >= 4) break;
        }
    }

    if (upcoming.count == 0) {
        UILabel *noEvents = [[UILabel alloc] initWithFrame:CGRectMake(kPadding, listTop, width - kPadding * 2, 24)];
        noEvents.font = [UIFont systemFontOfSize:12];
        noEvents.textColor = [HATheme secondaryTextColor];
        noEvents.text = @"No upcoming events";
        [self.contentContainer addSubview:noEvents];
    } else {
        for (NSUInteger i = 0; i < upcoming.count; i++) {
            UIView *row = [self makeEventRow:upcoming[i] y:listTop + i * kEventRowHeight width:width];
            [self.contentContainer addSubview:row];
        }
    }
}

#pragma mark - Placeholder

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;

        // NavBar: top area
        CGFloat navX = kPadding;
        CGFloat navY = 8;
        CGFloat navW = w - kPadding * 2;

        // Today button
        CGSize todaySize = [self.todayButton sizeThatFits:CGSizeMake(100, kNavBarHeight)];
        self.todayButton.frame = CGRectMake(navX, navY + (kNavBarHeight - todaySize.height) / 2.0, todaySize.width, todaySize.height);

        // Prev button
        self.prevButton.frame = CGRectMake(CGRectGetMaxX(self.todayButton.frame) + 6, navY + (kNavBarHeight - 24) / 2.0, 24, 24);
        // Next button
        self.nextButton.frame = CGRectMake(CGRectGetMaxX(self.prevButton.frame) + 2, navY + (kNavBarHeight - 24) / 2.0, 24, 24);

        // Date range label
        CGSize dateSize = [self.dateRangeLabel sizeThatFits:CGSizeMake(200, kNavBarHeight)];
        self.dateRangeLabel.frame = CGRectMake(CGRectGetMaxX(self.nextButton.frame) + 6, navY + (kNavBarHeight - dateSize.height) / 2.0, dateSize.width, dateSize.height);

        // List view button: right edge
        self.listViewBtn.frame = CGRectMake(navX + navW - 28, navY + (kNavBarHeight - 28) / 2.0, 28, 28);
        // Month view button
        self.monthViewBtn.frame = CGRectMake(CGRectGetMinX(self.listViewBtn.frame) - 32, navY + (kNavBarHeight - 28) / 2.0, 28, 28);

        // Content container: below nav bar, fill remaining space
        CGFloat contentTop = navY + kNavBarHeight + 4;
        self.contentContainer.frame = CGRectMake(0, contentTop, w, h - contentTop);

        // List scroll view
        self.listScrollView.frame = self.contentContainer.bounds;
    }
}

- (void)showPlaceholder:(NSString *)text {
    for (UIView *v in self.contentContainer.subviews) [v removeFromSuperview];

    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = [HATheme secondaryTextColor];
    label.text = text;
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:label];

    HAActivateConstraints(@[
        HACon([label.centerXAnchor constraintEqualToAnchor:self.contentContainer.centerXAnchor]),
        HACon([label.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor]),
    ]);
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    [self cancelLoading];
    self.events = nil;
    self.entityIds = nil;
    self.needsEventsLoad = NO;
    for (UIView *v in self.contentContainer.subviews) [v removeFromSuperview];
    for (UIView *v in self.listScrollView.subviews) [v removeFromSuperview];
    self.dateRangeLabel.text = nil;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.dateRangeLabel.textColor = [HATheme primaryTextColor];
    self.todayButton.layer.borderColor = [HATheme tertiaryTextColor].CGColor;
}

@end
