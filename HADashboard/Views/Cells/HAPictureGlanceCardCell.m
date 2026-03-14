#import "HAAutoLayout.h"
#import "HAStackView.h"
#import "HAPictureGlanceCardCell.h"
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

@interface HAPictureGlanceCardCell ()
@property (nonatomic, strong) UIImageView *bgImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) HAStackView *entityIconStack;
@property (nonatomic, strong) id imageTask;
@property (nonatomic, strong) NSArray<NSString *> *entityIds;
@end

@implementation HAPictureGlanceCardCell

- (void)setupSubviews {
    [super setupSubviews];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    self.bgImageView = [[UIImageView alloc] init];
    self.bgImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bgImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.bgImageView.clipsToBounds = YES;
    self.bgImageView.layer.cornerRadius = 12;
    self.bgImageView.backgroundColor = [HATheme cellBackgroundColor];
    [self.contentView insertSubview:self.bgImageView atIndex:0];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont ha_systemFontOfSize:16 weight:HAFontWeightBold];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.titleLabel];

    self.entityIconStack = [[HAStackView alloc] init];
    self.entityIconStack.axis = 0;
    self.entityIconStack.spacing = 12;
    self.entityIconStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.entityIconStack];

    CGFloat pad = 10;
    HAPinEdgesFlush(self.bgImageView, self.contentView);
    HAActivateConstraints(@[
        HACon([self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad]),
        HACon([self.titleLabel.bottomAnchor constraintEqualToAnchor:self.entityIconStack.topAnchor constant:-4]),
        HACon([self.entityIconStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad]),
        HACon([self.entityIconStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-pad]),
        HACon([self.entityIconStack.heightAnchor constraintEqualToConstant:24]),
    ]);
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary<NSString *, HAEntity *> *)entities
                  configItem:(HADashboardConfigItem *)configItem {
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    self.titleLabel.text = section.title;
    self.entityIds = section.entityIds;

    // Clear icon stack
    for (UIView *v in self.entityIconStack.arrangedSubviews) {
        [self.entityIconStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    // Entity state icons along bottom
    for (NSString *eid in section.entityIds) {
        HAEntity *entity = entities[eid];
        if (!entity) continue;

        UILabel *iconLabel = [[UILabel alloc] init];
        iconLabel.font = [HAIconMapper mdiFontOfSize:18];
        iconLabel.text = [HAEntityDisplayHelper iconGlyphForEntity:entity];
        BOOL isActive = [entity isOn] || [entity.state isEqualToString:@"open"] ||
                        [entity.state isEqualToString:@"locked"];
        iconLabel.textColor = isActive
            ? [UIColor yellowColor]
            : [[UIColor whiteColor] colorWithAlphaComponent:0.7];
        [self.entityIconStack addArrangedSubview:iconLabel];
    }

    // Load background image
    [[HAHTTPClient sharedClient] cancelTask:self.imageTask];
    self.bgImageView.image = nil;
    NSDictionary *props = section.customProperties;
    NSString *picturePath = props[@"camera_image"] ?: props[@"image"];
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
                    dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.bgImageView.image = img; });
                }];
            }
        }
    }

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat pad = 10;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        self.bgImageView.frame = self.contentView.bounds;
        CGFloat stackH = 24;
        CGSize stackSize = [self.entityIconStack sizeThatFits:CGSizeMake(w - pad * 2, stackH)];
        self.entityIconStack.frame = CGRectMake(pad, h - pad - stackH, stackSize.width, stackH);
        CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(w - pad * 2, CGFLOAT_MAX)];
        self.titleLabel.frame = CGRectMake(pad, CGRectGetMinY(self.entityIconStack.frame) - 4 - titleSize.height,
                                           w - pad * 2, titleSize.height);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [[HAHTTPClient sharedClient] cancelTask:self.imageTask];
    self.imageTask = nil;
    self.bgImageView.image = nil;
    self.titleLabel.text = nil;
    for (UIView *v in self.entityIconStack.arrangedSubviews) {
        [self.entityIconStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

@end
