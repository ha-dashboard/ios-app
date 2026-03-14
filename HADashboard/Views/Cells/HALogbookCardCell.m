#import "HALogbookCardCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HALogbookManager.h"
#import "HATheme.h"

static const CGFloat kRowHeight = 32.0;
static const CGFloat kPadding = 10.0;
static const NSInteger kMaxEntries = 10;

@interface HALogbookCardCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIStackView *entryStack;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) NSInteger hoursToShow;
@property (nonatomic, copy) NSArray<NSString *> *entityFilter;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation HALogbookCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.layer.cornerRadius = 14.0;
        self.contentView.layer.masksToBounds = YES;
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        self.titleLabel.textColor = [HATheme primaryTextColor];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.titleLabel];

        self.entryStack = [[UIStackView alloc] init];
        self.entryStack.axis = UILayoutConstraintAxisVertical;
        self.entryStack.spacing = 2;
        self.entryStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.entryStack];

        self.emptyLabel = [[UILabel alloc] init];
        self.emptyLabel.text = @"No recent activity";
        self.emptyLabel.font = [UIFont systemFontOfSize:13];
        self.emptyLabel.textColor = [HATheme secondaryTextColor];
        self.emptyLabel.textAlignment = NSTextAlignmentCenter;
        self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.emptyLabel.hidden = YES;
        [self.contentView addSubview:self.emptyLabel];

        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
        self.spinner.hidesWhenStopped = YES;
        [self.contentView addSubview:self.spinner];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kPadding],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],

            [self.entryStack.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
            [self.entryStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
            [self.entryStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],

            [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [self.spinner.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.spinner.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary<NSString *, HAEntity *> *)entityDict
                  configItem:(HADashboardConfigItem *)configItem {
    NSDictionary *props = configItem.customProperties;

    // Title: config title > section title > "Logbook"
    NSString *title = props[@"title"];
    if (![title isKindOfClass:[NSString class]] || title.length == 0) {
        title = section.title;
    }
    self.titleLabel.text = title ?: @"Logbook";

    self.hoursToShow = 24;
    if ([props[@"hours_to_show"] isKindOfClass:[NSNumber class]]) {
        self.hoursToShow = [props[@"hours_to_show"] integerValue];
    }

    // Entity filter: config entities array > section entityIds
    NSArray *configEntities = props[@"entities"];
    if ([configEntities isKindOfClass:[NSArray class]] && configEntities.count > 0) {
        // Logbook card entities can be strings or dicts with "entity" key
        NSMutableArray *ids = [NSMutableArray array];
        for (id item in configEntities) {
            if ([item isKindOfClass:[NSString class]]) {
                [ids addObject:item];
            } else if ([item isKindOfClass:[NSDictionary class]] && [item[@"entity"] isKindOfClass:[NSString class]]) {
                [ids addObject:item[@"entity"]];
            }
        }
        self.entityFilter = ids;
    } else {
        self.entityFilter = section.entityIds;
    }

    self.loaded = NO;

    // Clear previous entries
    for (UIView *v in [self.entryStack.arrangedSubviews copy]) {
        [self.entryStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    self.emptyLabel.hidden = YES;
}

- (void)beginLoading {
    if (self.loaded) return;
    self.loaded = YES;

    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;

    if (self.entityFilter.count > 0) {
        [[HALogbookManager sharedManager] fetchEntriesForEntityIds:self.entityFilter
                                                         hoursBack:self.hoursToShow
                                                        completion:^(NSArray *entries, NSError *error) {
            [weakSelf displayEntries:entries];
        }];
    } else {
        [[HALogbookManager sharedManager] fetchRecentEntries:self.hoursToShow
                                                  completion:^(NSArray *entries, NSError *error) {
            [weakSelf displayEntries:entries];
        }];
    }
}

- (void)displayEntries:(NSArray *)entries {
    [self.spinner stopAnimating];

    // Clear previous
    for (UIView *v in [self.entryStack.arrangedSubviews copy]) {
        [self.entryStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    if (entries.count == 0) {
        self.emptyLabel.hidden = NO;
        return;
    }
    self.emptyLabel.hidden = YES;

    // Show up to kMaxEntries
    NSInteger count = MIN((NSInteger)entries.count, kMaxEntries);
    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *entry = entries[i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        UIView *row = [self createEntryRow:entry];
        [self.entryStack addArrangedSubview:row];
    }
}

- (UIView *)createEntryRow:(NSDictionary *)entry {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:kRowHeight].active = YES;

    // Time label
    UILabel *timeLabel = [[UILabel alloc] init];
    timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightRegular];
    timeLabel.textColor = [HATheme secondaryTextColor];
    timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:timeLabel];

    // Name + message label
    UILabel *msgLabel = [[UILabel alloc] init];
    msgLabel.font = [UIFont systemFontOfSize:12];
    msgLabel.textColor = [HATheme primaryTextColor];
    msgLabel.numberOfLines = 1;
    msgLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    msgLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:msgLabel];

    // Parse time — show HH:mm format
    NSString *when = entry[@"when"];
    if ([when isKindOfClass:[NSString class]] && when.length >= 16) {
        // Extract HH:mm from ISO 8601 string (e.g. "2026-03-01T14:30:00Z")
        NSRange timeRange = NSMakeRange(11, 5);
        if (when.length >= NSMaxRange(timeRange)) {
            timeLabel.text = [when substringWithRange:timeRange];
        }
    }

    // Build message
    NSString *name = entry[@"name"];
    NSString *message = entry[@"message"];
    if ([name isKindOfClass:[NSString class]] && [message isKindOfClass:[NSString class]]) {
        msgLabel.text = [NSString stringWithFormat:@"%@ %@", name, message];
    } else if ([name isKindOfClass:[NSString class]]) {
        NSString *state = entry[@"state"];
        if ([state isKindOfClass:[NSString class]]) {
            msgLabel.text = [NSString stringWithFormat:@"%@ → %@", name, state];
        } else {
            msgLabel.text = name;
        }
    }

    [NSLayoutConstraint activateConstraints:@[
        [timeLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [timeLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [timeLabel.widthAnchor constraintEqualToConstant:50],

        [msgLabel.leadingAnchor constraintEqualToAnchor:timeLabel.trailingAnchor constant:4],
        [msgLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [msgLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    return row;
}

+ (CGFloat)preferredHeightForHours:(NSInteger)hours {
    // Title + up to 10 rows + padding
    return kPadding + 20 + 8 + (kMaxEntries * (kRowHeight + 2)) + kPadding;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.loaded = NO;
    self.emptyLabel.hidden = YES;
    [self.spinner stopAnimating];
    for (UIView *v in [self.entryStack.arrangedSubviews copy]) {
        [self.entryStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.titleLabel.textColor = [HATheme primaryTextColor];
}

@end
