#import "HAPersonEntityCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAAuthManager.h"
#import "NSMutableURLRequest+HAHelpers.h"
#import "HAStateLocalizer.h"

static const CGFloat kAvatarSize = 40.0;

@interface HAPersonEntityCell ()
@property (nonatomic, strong) UILabel *locationLabel;
@property (nonatomic, strong) UILabel *gpsLabel;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) NSURLSessionDataTask *imageTask;
@property (nonatomic, copy) NSString *currentPictureURL;
@end

@implementation HAPersonEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Avatar image view (circular)
    self.avatarView = [[UIImageView alloc] init];
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.layer.cornerRadius = kAvatarSize / 2.0;
    self.avatarView.backgroundColor = [HATheme controlBackgroundColor];
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.hidden = YES;
    [self.contentView addSubview:self.avatarView];

    // Location label (display-only)
    self.locationLabel = [self labelWithFont:[UIFont boldSystemFontOfSize:18] color:[HATheme primaryTextColor] lines:1];

    // Avatar: top-right
    [NSLayoutConstraint activateConstraints:@[
        [self.avatarView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.avatarView.widthAnchor constraintEqualToConstant:kAvatarSize],
        [self.avatarView.heightAnchor constraintEqualToConstant:kAvatarSize],
    ]];

    // GPS coordinates label (secondary, below location)
    self.gpsLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightRegular]
                                  color:[HATheme secondaryTextColor] lines:1];
    self.gpsLabel.hidden = YES;

    // Location label: below name, constrained before avatar
    [NSLayoutConstraint activateConstraints:@[
        [self.locationLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.locationLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.avatarView.leadingAnchor constant:-8],
        [self.locationLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
        [self.gpsLabel.leadingAnchor constraintEqualToAnchor:self.locationLabel.leadingAnchor],
        [self.gpsLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.avatarView.leadingAnchor constant:-8],
        [self.gpsLabel.topAnchor constraintEqualToAnchor:self.locationLabel.bottomAnchor constant:1],
    ]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSString *state = entity.state;
    // This cell renders BOTH `person` and `device_tracker` domains
    // (HAEntityCellFactory routes device_tracker to kPersonCellId) — HA
    // translates them under separate dotted-key buckets
    // (`component.person.…` vs `component.device_tracker.…`, plan §2.1's
    // coverage table), so the entity's OWN domain must be passed through,
    // not a hardcoded "person". Passing the wrong domain here previously
    // meant a device_tracker entity's legacy offline fallback
    // (state.fallback.device_tracker.*) could never actually be reached by
    // this cell, since every lookup was mislabeled as "person".
    NSString *domain = [entity domain] ?: @"person";
    if ([state isEqualToString:@"home"]) {
        // "Home"/"Away" come from Home Assistant's own translations now
        // (docs/plans/i18n-plan.md §2.5), not an app-hardcoded literal —
        // this is the fix for GitHub issue #19's raw `not_home`.
        self.locationLabel.text = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:domain
                                                                                    deviceClass:nil
                                                                                       platform:entity.platform
                                                                                 translationKey:nil
                                                                                          state:state];
        self.locationLabel.textColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.2 alpha:1.0];
    } else if ([state isEqualToString:@"not_home"]) {
        self.locationLabel.text = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:domain
                                                                                    deviceClass:nil
                                                                                       platform:entity.platform
                                                                                 translationKey:nil
                                                                                          state:state];
        self.locationLabel.textColor = [HATheme secondaryTextColor];
    } else {
        // Zone name
        self.locationLabel.text = [state stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        self.locationLabel.textColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    }

    // GPS coordinates
    NSNumber *lat = entity.attributes[@"latitude"];
    NSNumber *lon = entity.attributes[@"longitude"];
    if ([lat isKindOfClass:[NSNumber class]] && [lon isKindOfClass:[NSNumber class]]) {
        NSNumber *accuracy = entity.attributes[@"gps_accuracy"];
        if ([accuracy isKindOfClass:[NSNumber class]]) {
            self.gpsLabel.text = [NSString stringWithFormat:@"%.4f, %.4f (\u00B1%ldm)",
                [lat doubleValue], [lon doubleValue], (long)[accuracy integerValue]];
        } else {
            self.gpsLabel.text = [NSString stringWithFormat:@"%.4f, %.4f",
                [lat doubleValue], [lon doubleValue]];
        }
        self.gpsLabel.hidden = NO;
    } else {
        self.gpsLabel.hidden = YES;
    }

    // Load entity_picture as avatar
    NSString *picturePath = entity.attributes[@"entity_picture"];
    if ([picturePath isKindOfClass:[NSString class]] && picturePath.length > 0) {
        self.avatarView.hidden = NO;
        [self loadAvatarFromPath:picturePath];
    } else {
        self.avatarView.hidden = YES;
        self.avatarView.image = nil;
    }
}

- (void)loadAvatarFromPath:(NSString *)path {
    // Skip if already loading the same URL
    if ([path isEqualToString:self.currentPictureURL] && self.avatarView.image) return;
    self.currentPictureURL = path;

    // Cancel previous request
    [self.imageTask cancel];

    HAAuthManager *auth = [HAAuthManager sharedManager];
    NSString *serverURL = auth.serverURL;
    NSString *token = auth.accessToken;
    if (!serverURL || !token) return;

    NSURL *url = [NSURL URLWithString:[serverURL stringByAppendingString:path]];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request ha_setAuthHeaders:token];

    __weak typeof(self) weakSelf = self;
    NSString *capturedPath = [path copy];
    self.imageTask = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) return;
            UIImage *image = [UIImage imageWithData:data];
            if (!image) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                // Only apply if still showing the same entity
                if ([capturedPath isEqualToString:strongSelf.currentPictureURL]) {
                    strongSelf.avatarView.image = image;
                }
            });
        }];
    [self.imageTask resume];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.imageTask cancel];
    self.imageTask = nil;
    self.currentPictureURL = nil;
    self.avatarView.image = nil;
    self.avatarView.hidden = YES;
    self.avatarView.backgroundColor = [HATheme controlBackgroundColor];
    self.locationLabel.text = nil;
    self.locationLabel.textColor = [HATheme primaryTextColor];
    self.gpsLabel.text = nil;
    self.gpsLabel.hidden = YES;
}

@end
