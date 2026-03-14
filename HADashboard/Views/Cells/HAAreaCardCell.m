#import "HAAutoLayout.h"
#import "HAStackView.h"
#import "HAAreaCardCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HAHTTPClient.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIFont+HACompat.h"

@interface HAAreaCardCell ()
@property (nonatomic, strong) UIImageView *bgImageView;
@property (nonatomic, strong) UILabel *areaNameLabel;
@property (nonatomic, strong) UILabel *sensorSummaryLabel;
@property (nonatomic, strong) HAStackView *toggleStack;
@property (nonatomic, strong) id imageTask;
@property (nonatomic, strong) NSArray<NSString *> *toggleEntityIds;
@end

@implementation HAAreaCardCell

- (void)setupSubviews {
    [super setupSubviews];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    // Background image (camera/picture)
    self.bgImageView = [[UIImageView alloc] init];
    self.bgImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.bgImageView.clipsToBounds = YES;
    self.bgImageView.layer.cornerRadius = 12;
    self.bgImageView.backgroundColor = [HATheme cellBackgroundColor];
    [self.contentView insertSubview:self.bgImageView atIndex:0];

    // Semi-transparent overlay for text readability
    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
    overlay.layer.cornerRadius = 12;
    overlay.clipsToBounds = YES;
    [self.contentView insertSubview:overlay aboveSubview:self.bgImageView];

    // Area name (large, white over image)
    self.areaNameLabel = [[UILabel alloc] init];
    self.areaNameLabel.font = [UIFont ha_systemFontOfSize:18 weight:HAFontWeightBold];
    self.areaNameLabel.textColor = [UIColor whiteColor];
    self.areaNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.areaNameLabel];

    // Sensor summary (temp, humidity — below area name)
    self.sensorSummaryLabel = [[UILabel alloc] init];
    self.sensorSummaryLabel.font = [UIFont ha_systemFontOfSize:12 weight:HAFontWeightMedium];
    self.sensorSummaryLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.85];
    self.sensorSummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.sensorSummaryLabel];

    // Toggle buttons (lights, switches, fans)
    self.toggleStack = [[HAStackView alloc] init];
    self.toggleStack.axis = 0;
    self.toggleStack.spacing = 8;
    self.toggleStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.toggleStack];

    CGFloat pad = 12;
    HAActivateConstraints(@[
        HACon([self.bgImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor]),
        HACon([self.bgImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]),
        HACon([self.bgImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor]),
        HACon([self.bgImageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]),
        HACon([overlay.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor]),
        HACon([overlay.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]),
        HACon([overlay.topAnchor constraintEqualToAnchor:self.contentView.topAnchor]),
        HACon([overlay.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]),
        HACon([self.areaNameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad]),
        HACon([self.areaNameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad]),
        HACon([self.areaNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-pad]),
        HACon([self.sensorSummaryLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad]),
        HACon([self.sensorSummaryLabel.topAnchor constraintEqualToAnchor:self.areaNameLabel.bottomAnchor constant:2]),
        HACon([self.toggleStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad]),
        HACon([self.toggleStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-pad]),
    ]);
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary<NSString *, HAEntity *> *)entities
                  configItem:(HADashboardConfigItem *)configItem {
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    // Area name from section title or config
    NSString *areaName = section.title ?: configItem.customProperties[@"area_name"] ?: @"Area";
    self.areaNameLabel.text = areaName;

    // Clear toggles
    for (UIView *v in self.toggleStack.arrangedSubviews) {
        [self.toggleStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    // Gather entities by type
    NSMutableArray *sensorParts = [NSMutableArray array];
    NSMutableArray *toggleIds = [NSMutableArray array];

    for (NSString *eid in section.entityIds) {
        HAEntity *entity = entities[eid];
        if (!entity) continue;
        NSString *domain = [entity domain];

        // Sensors: aggregate temperature and humidity
        if ([domain isEqualToString:@"sensor"]) {
            NSString *dc = entity.attributes[@"device_class"];
            if ([dc isEqualToString:@"temperature"]) {
                [sensorParts addObject:[NSString stringWithFormat:@"%@%@",
                    entity.state, entity.unitOfMeasurement ?: @"\u00B0"]];
            } else if ([dc isEqualToString:@"humidity"]) {
                [sensorParts addObject:[NSString stringWithFormat:@"%@%%", entity.state]];
            }
        }
        // Toggleable: light, switch, fan
        if ([domain isEqualToString:@"light"] || [domain isEqualToString:@"switch"] ||
            [domain isEqualToString:@"fan"]) {
            [toggleIds addObject:eid];
        }
    }

    self.sensorSummaryLabel.text = sensorParts.count > 0 ? [sensorParts componentsJoinedByString:@" · "] : nil;
    self.sensorSummaryLabel.hidden = sensorParts.count == 0;

    // Build toggle buttons (max 4 to fit)
    self.toggleEntityIds = [toggleIds copy];
    NSInteger maxToggles = MIN((NSInteger)toggleIds.count, 4);
    for (NSInteger i = 0; i < maxToggles; i++) {
        HAEntity *entity = entities[toggleIds[i]];
        UIButton *btn = HASystemButton();
        NSString *iconName = [entity icon];
        if (!iconName) {
            NSString *domain = [entity domain];
            if ([domain isEqualToString:@"light"])       iconName = @"lightbulb";
            else if ([domain isEqualToString:@"switch"]) iconName = @"flash";
            else if ([domain isEqualToString:@"fan"])    iconName = @"fan";
            else                                         iconName = @"toggle-switch-variant";
        }
        UIColor *iconColor = [entity isOn] ? [UIColor yellowColor] : [[UIColor whiteColor] colorWithAlphaComponent:0.7];
        [HAIconMapper setIconName:iconName onButton:btn size:18 color:iconColor];
        btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
        btn.layer.cornerRadius = 16;
        btn.tag = i;
        [btn addTarget:self action:@selector(toggleTapped:) forControlEvents:UIControlEventTouchUpInside];
        HAActivateConstraints(@[
            HACon([btn.widthAnchor constraintEqualToConstant:32]),
            HACon([btn.heightAnchor constraintEqualToConstant:32]),
        ]);
        [self.toggleStack addArrangedSubview:btn];
    }

    // Load background image
    [[HAHTTPClient sharedClient] cancelTask:self.imageTask];
    self.bgImageView.image = nil;
    NSString *picturePath = configItem.customProperties[@"camera_image"]
                         ?: configItem.customProperties[@"image"];
    if ([picturePath isKindOfClass:[NSString class]] && picturePath.length > 0) {
        NSString *serverURL = [[HAAuthManager sharedManager] serverURL];
        if (serverURL) {
            NSString *fullURL = [picturePath hasPrefix:@"/"]
                ? [serverURL stringByAppendingString:picturePath] : picturePath;
            NSURL *url = [NSURL URLWithString:fullURL];
            if (url) {
                NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
                NSString *token = [[HAAuthManager sharedManager] accessToken];
                if (token) [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
                __weak typeof(self) weakSelf = self;
                self.imageTask = [[HAHTTPClient sharedClient] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
                    if (!data) return;
                    UIImage *img = [UIImage imageWithData:data];
                    if (!img) return;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        weakSelf.bgImageView.image = img;
                    });
                }];
            }
        }
    }

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

- (void)toggleTapped:(UIButton *)sender {
    [HAHaptics lightImpact];
    NSUInteger idx = (NSUInteger)sender.tag;
    if (idx >= self.toggleEntityIds.count) return;
    NSString *eid = self.toggleEntityIds[idx];
    HAEntity *entity = [[HAConnectionManager sharedManager] entityForId:eid];
    if (!entity) return;
    [[HAConnectionManager sharedManager] callService:@"toggle"
                                            inDomain:[entity domain]
                                            withData:nil
                                            entityId:eid];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat pad = 12;

        // bgImageView + overlay: fill contentView
        for (UIView *sub in self.contentView.subviews) {
            if ([sub isKindOfClass:[UIImageView class]] && sub == self.bgImageView) {
                sub.frame = self.contentView.bounds;
            }
        }
        self.bgImageView.frame = self.contentView.bounds;
        // Overlay is the subview inserted above bgImageView
        for (UIView *sub in self.contentView.subviews) {
            if (sub != self.bgImageView && sub != self.areaNameLabel && sub != self.sensorSummaryLabel && sub != self.toggleStack && sub.tag == 0 && [sub.backgroundColor isEqual:[[UIColor blackColor] colorWithAlphaComponent:0.3]]) {
                sub.frame = self.contentView.bounds;
                break;
            }
        }

        // areaNameLabel: top-left
        CGSize nameSize = [self.areaNameLabel sizeThatFits:CGSizeMake(w - pad * 2, CGFLOAT_MAX)];
        self.areaNameLabel.frame = CGRectMake(pad, pad, MIN(nameSize.width, w - pad * 2), nameSize.height);

        // sensorSummaryLabel: below area name
        CGSize sensorSize = [self.sensorSummaryLabel sizeThatFits:CGSizeMake(w - pad * 2, CGFLOAT_MAX)];
        self.sensorSummaryLabel.frame = CGRectMake(pad, CGRectGetMaxY(self.areaNameLabel.frame) + 2, sensorSize.width, sensorSize.height);

        // toggleStack: bottom-right
        CGSize stackSize = [self.toggleStack sizeThatFits:CGSizeMake(w, 32)];
        self.toggleStack.frame = CGRectMake(w - pad - stackSize.width, h - pad - 32, stackSize.width, 32);

        // Toggle buttons inside stack need sizing
        for (UIView *btn in self.toggleStack.arrangedSubviews) {
            btn.frame = CGRectMake(0, 0, 32, 32);
        }
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [[HAHTTPClient sharedClient] cancelTask:self.imageTask];
    self.imageTask = nil;
    self.bgImageView.image = nil;
    self.areaNameLabel.text = nil;
    self.sensorSummaryLabel.text = nil;
    self.toggleEntityIds = nil;
    for (UIView *v in self.toggleStack.arrangedSubviews) {
        [self.toggleStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

@end
