#import "HAAutoLayout.h"
#import "HAImageEntityCell.h"
#import "HAEntity.h"
#import "HAAuthManager.h"
#import "HAHTTPClient.h"
#import "HADashboardConfig.h"
#import "HATheme.h"

@interface HAImageEntityCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) id imageTask;
@end

@implementation HAImageEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    self.imageView = [[UIImageView alloc] init];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.clipsToBounds = YES;
    self.imageView.layer.cornerRadius = 8;
    self.imageView.backgroundColor = [HATheme cellBackgroundColor];
    [self.contentView addSubview:self.imageView];

    CGFloat padding = 10.0;
    HAActivateConstraints(@[
        HACon([self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.imageView.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4]),
        HACon([self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding]),
    ]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat padding = 10.0;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat top = CGRectGetMaxY(self.nameLabel.frame) + 4;
        self.imageView.frame = CGRectMake(padding, top, w - padding * 2, h - padding - top);
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];
    self.stateLabel.hidden = YES;

    [[HAHTTPClient sharedClient] cancelTask:self.imageTask];
    self.imageView.image = nil;

    NSString *picturePath = entity.attributes[@"entity_picture"];
    if (![picturePath isKindOfClass:[NSString class]] || picturePath.length == 0) return;

    NSString *serverURL = [[HAAuthManager sharedManager] serverURL];
    if (!serverURL) return;

    NSString *fullURL = [picturePath hasPrefix:@"/"]
        ? [serverURL stringByAppendingString:picturePath]
        : picturePath;

    NSURL *url = [NSURL URLWithString:fullURL];
    if (!url) return;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    NSString *token = [[HAAuthManager sharedManager] accessToken];
    if (token) [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];

    __weak typeof(self) weakSelf = self;
    self.imageTask = [[HAHTTPClient sharedClient] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data) return;
        UIImage *img = [UIImage imageWithData:data];
        if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (s) s.imageView.image = img;
        });
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [[HAHTTPClient sharedClient] cancelTask:self.imageTask];
    self.imageTask = nil;
    self.imageView.image = nil;
}

@end
