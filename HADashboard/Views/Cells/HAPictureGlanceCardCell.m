#import "HAPictureGlanceCardCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"

@interface HAPictureGlanceCardCell ()
@property (nonatomic, strong) UIImageView *bgImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIStackView *entityIconStack;
@property (nonatomic, strong) NSURLSessionDataTask *imageTask;
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
    self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.titleLabel];

    self.entityIconStack = [[UIStackView alloc] init];
    self.entityIconStack.axis = UILayoutConstraintAxisHorizontal;
    self.entityIconStack.spacing = 12;
    self.entityIconStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.entityIconStack];

    CGFloat pad = 10;
    [NSLayoutConstraint activateConstraints:@[
        [self.bgImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.bgImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.bgImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.bgImageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.entityIconStack.topAnchor constant:-4],
        [self.entityIconStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [self.entityIconStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-pad],
        [self.entityIconStack.heightAnchor constraintEqualToConstant:24],
    ]];
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
    [self.imageTask cancel];
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
                self.imageTask = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
                    if (!data) return;
                    UIImage *img = [UIImage imageWithData:data];
                    if (!img) return;
                    dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.bgImageView.image = img; });
                }];
                [self.imageTask resume];
            }
        }
    }

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.imageTask cancel];
    self.imageTask = nil;
    self.bgImageView.image = nil;
    self.titleLabel.text = nil;
    for (UIView *v in self.entityIconStack.arrangedSubviews) {
        [self.entityIconStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

@end
