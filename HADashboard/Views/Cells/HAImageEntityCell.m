#import "HAImageEntityCell.h"
#import "HAEntity.h"
#import "HAAuthManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"

@interface HAImageEntityCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) NSURLSessionDataTask *imageTask;
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
    [NSLayoutConstraint activateConstraints:@[
        [self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.imageView.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
        [self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
    ]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];
    self.stateLabel.hidden = YES;

    [self.imageTask cancel];
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
    self.imageTask = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data) return;
        UIImage *img = [UIImage imageWithData:data];
        if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (s) s.imageView.image = img;
        });
    }];
    [self.imageTask resume];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.imageTask cancel];
    self.imageTask = nil;
    self.imageView.image = nil;
}

@end
