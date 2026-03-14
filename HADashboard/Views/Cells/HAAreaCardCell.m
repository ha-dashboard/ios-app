#import "HAAreaCardCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"

@interface HAAreaCardCell ()
@property (nonatomic, strong) UIImageView *bgImageView;
@property (nonatomic, strong) UILabel *areaNameLabel;
@property (nonatomic, strong) UILabel *sensorSummaryLabel;
@property (nonatomic, strong) UIStackView *toggleStack;
@property (nonatomic, strong) NSURLSessionDataTask *imageTask;
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
    self.areaNameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.areaNameLabel.textColor = [UIColor whiteColor];
    self.areaNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.areaNameLabel];

    // Sensor summary (temp, humidity — below area name)
    self.sensorSummaryLabel = [[UILabel alloc] init];
    self.sensorSummaryLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.sensorSummaryLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.85];
    self.sensorSummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.sensorSummaryLabel];

    // Toggle buttons (lights, switches, fans)
    self.toggleStack = [[UIStackView alloc] init];
    self.toggleStack.axis = UILayoutConstraintAxisHorizontal;
    self.toggleStack.spacing = 8;
    self.toggleStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.toggleStack];

    CGFloat pad = 12;
    [NSLayoutConstraint activateConstraints:@[
        [self.bgImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.bgImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.bgImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.bgImageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [overlay.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.areaNameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.areaNameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad],
        [self.areaNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.sensorSummaryLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.sensorSummaryLabel.topAnchor constraintEqualToAnchor:self.areaNameLabel.bottomAnchor constant:2],
        [self.toggleStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
        [self.toggleStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-pad],
    ]];
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
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *glyph = [HAEntityDisplayHelper iconGlyphForEntity:entity];
        [btn setTitle:glyph forState:UIControlStateNormal];
        btn.titleLabel.font = [HAIconMapper mdiFontOfSize:18];
        [btn setTitleColor:[entity isOn] ? [UIColor yellowColor] : [[UIColor whiteColor] colorWithAlphaComponent:0.7]
                  forState:UIControlStateNormal];
        btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
        btn.layer.cornerRadius = 16;
        btn.tag = i;
        [btn addTarget:self action:@selector(toggleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [NSLayoutConstraint activateConstraints:@[
            [btn.widthAnchor constraintEqualToConstant:32],
            [btn.heightAnchor constraintEqualToConstant:32],
        ]];
        [self.toggleStack addArrangedSubview:btn];
    }

    // Load background image
    [self.imageTask cancel];
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
                self.imageTask = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
                    if (!data) return;
                    UIImage *img = [UIImage imageWithData:data];
                    if (!img) return;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        weakSelf.bgImageView.image = img;
                    });
                }];
                [self.imageTask resume];
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

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.imageTask cancel];
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
