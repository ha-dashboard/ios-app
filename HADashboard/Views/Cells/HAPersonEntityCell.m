#import "HAAutoLayout.h"
#import "HAPersonEntityCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAAuthManager.h"
#import "HAHTTPClient.h"
#import "NSMutableURLRequest+HAHelpers.h"
#import "UIFont+HACompat.h"

static const CGFloat kAvatarSize = 40.0;

@interface HAPersonEntityCell ()
@property (nonatomic, strong) UILabel *locationLabel;
@property (nonatomic, strong) UILabel *gpsLabel;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) id imageTask;
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

    // GPS coordinates label (secondary, below location)
    self.gpsLabel = [self labelWithFont:[UIFont ha_monospacedDigitSystemFontOfSize:10 weight:HAFontWeightRegular]
                                  color:[HATheme secondaryTextColor] lines:1];
    self.gpsLabel.hidden = YES;

    HAActivateConstraints(@[
        // Avatar: top-right
        HACon([self.avatarView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]),
        HACon([self.avatarView.widthAnchor constraintEqualToConstant:kAvatarSize]),
        HACon([self.avatarView.heightAnchor constraintEqualToConstant:kAvatarSize]),
        // Location label: below name, constrained before avatar
        HACon([self.locationLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.locationLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.avatarView.leadingAnchor constant:-8]),
        HACon([self.locationLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4]),
        HACon([self.gpsLabel.leadingAnchor constraintEqualToAnchor:self.locationLabel.leadingAnchor]),
        HACon([self.gpsLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.avatarView.leadingAnchor constant:-8]),
        HACon([self.gpsLabel.topAnchor constraintEqualToAnchor:self.locationLabel.bottomAnchor constant:1]),
    ]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat padding = 10.0;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat midY = h / 2.0;

        self.avatarView.frame = CGRectMake(w - padding - kAvatarSize, midY - kAvatarSize / 2.0, kAvatarSize, kAvatarSize);

        CGFloat labelMaxW = CGRectGetMinX(self.avatarView.frame) - 8 - padding;
        CGSize locSize = [self.locationLabel sizeThatFits:CGSizeMake(labelMaxW, CGFLOAT_MAX)];
        self.locationLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 4,
                                               MIN(locSize.width, labelMaxW), locSize.height);

        CGSize gpsSize = [self.gpsLabel sizeThatFits:CGSizeMake(labelMaxW, CGFLOAT_MAX)];
        self.gpsLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.locationLabel.frame) + 1,
                                          MIN(gpsSize.width, labelMaxW), gpsSize.height);
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSString *state = entity.state;
    if ([state isEqualToString:@"home"]) {
        self.locationLabel.text = @"Home";
        self.locationLabel.textColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.2 alpha:1.0];
    } else if ([state isEqualToString:@"not_home"]) {
        self.locationLabel.text = @"Away";
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
    [[HAHTTPClient sharedClient] cancelTask:self.imageTask];

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
    self.imageTask = [[HAHTTPClient sharedClient] dataTaskWithRequest:request
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
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [[HAHTTPClient sharedClient] cancelTask:self.imageTask];
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
