#import "HAAutoLayout.h"
#import "HAMediaPlayerEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HAHTTPClient.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIView+HAUtilities.h"
#import "UIViewController+HAAlert.h"
#import "UIFont+HACompat.h"
#import "NSString+HACompat.h"

static const CGFloat kIconCircleSize = 36.0;
static const CGFloat kIconFontSize   = 20.0;
static const CGFloat kBtnSize        = 36.0;
static const CGFloat kBtnIconSize    = 18.0;
static const CGFloat kBtnSpacing     = 8.0;
static const CGFloat kPadding        = 12.0;

@interface HAMediaPlayerEntityCell ()
@property (nonatomic, strong) UIView  *iconCircle;
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *mpNameLabel;
@property (nonatomic, strong) UILabel *mpStateLabel;
@property (nonatomic, strong) UILabel *mediaInfoLabel;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (nonatomic, strong) UILabel *volumeLabel;
@property (nonatomic, strong) UIImageView *albumArtView;
@property (nonatomic, strong) id artLoadTask;
@property (nonatomic, strong) UIButton *sourceButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, assign) double lastKnownDuration;
@end

@implementation HAMediaPlayerEntityCell

#pragma mark - Layout

- (void)setupSubviews {
    [super setupSubviews];
    // Hide base cell name/state — this cell has its own layout
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    // ── Icon circle (top-left) ──
    self.iconCircle = [[UIView alloc] init];
    self.iconCircle.layer.cornerRadius = kIconCircleSize / 2.0;
    self.iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.iconCircle];

    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.font = [HAIconMapper mdiFontOfSize:kIconFontSize];
    self.iconLabel.textAlignment = NSTextAlignmentCenter;
    self.iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.iconCircle addSubview:self.iconLabel];

    // Album art (overlays icon circle when available)
    self.albumArtView = [[UIImageView alloc] init];
    self.albumArtView.contentMode = UIViewContentModeScaleAspectFill;
    self.albumArtView.clipsToBounds = YES;
    self.albumArtView.layer.cornerRadius = kIconCircleSize / 2.0;
    self.albumArtView.translatesAutoresizingMaskIntoConstraints = NO;
    self.albumArtView.hidden = YES;
    [self.contentView addSubview:self.albumArtView];

    HAActivateConstraints(@[
        HACon([self.albumArtView.centerXAnchor constraintEqualToAnchor:self.iconCircle.centerXAnchor]),
        HACon([self.albumArtView.centerYAnchor constraintEqualToAnchor:self.iconCircle.centerYAnchor]),
        HACon([self.albumArtView.widthAnchor constraintEqualToConstant:kIconCircleSize]),
        HACon([self.albumArtView.heightAnchor constraintEqualToConstant:kIconCircleSize]),
    ]);

    // ── Name label (right of icon) ──
    self.mpNameLabel = [self labelWithFont:[UIFont ha_systemFontOfSize:13 weight:HAFontWeightMedium] color:[HATheme primaryTextColor] lines:1];
    self.mpNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    // ── State label (below name, right of icon) ──
    self.mpStateLabel = [self labelWithFont:[UIFont ha_systemFontOfSize:11 weight:HAFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];

    // ── Media info (artist - title) ──
    self.mediaInfoLabel = [self labelWithFont:[UIFont ha_systemFontOfSize:12 weight:HAFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.mediaInfoLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    // ── Transport buttons (prev | play/pause | next) ──
    self.prevButton      = [self makeTransportButtonWithIconName:@"skip-previous" action:@selector(prevTapped)];
    self.playPauseButton = [self makeTransportButtonWithIconName:@"play"          action:@selector(playPauseTapped)];
    self.nextButton      = [self makeTransportButtonWithIconName:@"skip-next"     action:@selector(nextTapped)];

    // ── Constraints ──

    HAActivateConstraints(@[
        // Icon circle: top-left
        HACon([self.iconCircle.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding]),
        HACon([self.iconCircle.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kPadding]),
        HACon([self.iconCircle.widthAnchor constraintEqualToConstant:kIconCircleSize]),
        HACon([self.iconCircle.heightAnchor constraintEqualToConstant:kIconCircleSize]),
        HACon([self.iconLabel.centerXAnchor constraintEqualToAnchor:self.iconCircle.centerXAnchor]),
        HACon([self.iconLabel.centerYAnchor constraintEqualToAnchor:self.iconCircle.centerYAnchor]),
        // Name: right of icon, vertically centered in top section
        HACon([self.mpNameLabel.leadingAnchor constraintEqualToAnchor:self.iconCircle.trailingAnchor constant:10]),
        HACon([self.mpNameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding]),
        HACon([self.mpNameLabel.topAnchor constraintEqualToAnchor:self.iconCircle.topAnchor constant:1]),
        // State: below name
        HACon([self.mpStateLabel.leadingAnchor constraintEqualToAnchor:self.mpNameLabel.leadingAnchor]),
        HACon([self.mpStateLabel.trailingAnchor constraintEqualToAnchor:self.mpNameLabel.trailingAnchor]),
        HACon([self.mpStateLabel.topAnchor constraintEqualToAnchor:self.mpNameLabel.bottomAnchor constant:1]),
        // Media info: below the icon/name row
        HACon([self.mediaInfoLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding]),
        HACon([self.mediaInfoLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding]),
        HACon([self.mediaInfoLabel.topAnchor constraintEqualToAnchor:self.iconCircle.bottomAnchor constant:8]),
        // Transport buttons: centered horizontal row below media info
        // Play/pause centered
        HACon([self.playPauseButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.playPauseButton.topAnchor constraintEqualToAnchor:self.mediaInfoLabel.bottomAnchor constant:8]),
        HACon([self.playPauseButton.widthAnchor constraintEqualToConstant:kBtnSize]),
        HACon([self.playPauseButton.heightAnchor constraintEqualToConstant:kBtnSize]),
        // Prev: left of play/pause
        HACon([self.prevButton.trailingAnchor constraintEqualToAnchor:self.playPauseButton.leadingAnchor constant:-kBtnSpacing]),
        HACon([self.prevButton.centerYAnchor constraintEqualToAnchor:self.playPauseButton.centerYAnchor]),
        HACon([self.prevButton.widthAnchor constraintEqualToConstant:kBtnSize]),
        HACon([self.prevButton.heightAnchor constraintEqualToConstant:kBtnSize]),
        // Next: right of play/pause
        HACon([self.nextButton.leadingAnchor constraintEqualToAnchor:self.playPauseButton.trailingAnchor constant:kBtnSpacing]),
        HACon([self.nextButton.centerYAnchor constraintEqualToAnchor:self.playPauseButton.centerYAnchor]),
        HACon([self.nextButton.widthAnchor constraintEqualToConstant:kBtnSize]),
        HACon([self.nextButton.heightAnchor constraintEqualToConstant:kBtnSize]),
    ]);

    // ── Volume row: mute button + slider + percentage label ──
    self.muteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.muteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.muteButton addTarget:self action:@selector(muteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.muteButton];

    self.volumeSlider = [[UISlider alloc] init];
    self.volumeSlider.minimumValue = 0.0;
    self.volumeSlider.maximumValue = 1.0;
    self.volumeSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.volumeSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.volumeSlider addTarget:self action:@selector(volumeSliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.contentView addSubview:self.volumeSlider];

    self.volumeLabel = [[UILabel alloc] init];
    self.volumeLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:11 weight:HAFontWeightMedium];
    self.volumeLabel.textColor = [HATheme secondaryTextColor];
    self.volumeLabel.textAlignment = NSTextAlignmentRight;
    self.volumeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.volumeLabel];

    HAActivateConstraints(@[
        HACon([self.muteButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding]),
        HACon([self.muteButton.topAnchor constraintEqualToAnchor:self.playPauseButton.bottomAnchor constant:8]),
        HACon([self.muteButton.widthAnchor constraintEqualToConstant:28]),
        HACon([self.muteButton.heightAnchor constraintEqualToConstant:28]),

        HACon([self.volumeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding]),
        HACon([self.volumeLabel.centerYAnchor constraintEqualToAnchor:self.muteButton.centerYAnchor]),
        HACon([self.volumeLabel.widthAnchor constraintEqualToConstant:36]),

        HACon([self.volumeSlider.leadingAnchor constraintEqualToAnchor:self.muteButton.trailingAnchor constant:6]),
        HACon([self.volumeSlider.trailingAnchor constraintEqualToAnchor:self.volumeLabel.leadingAnchor constant:-6]),
        HACon([self.volumeSlider.centerYAnchor constraintEqualToAnchor:self.muteButton.centerYAnchor]),
    ]);

    // ── Progress bar (below volume) ──
    self.progressSlider = [[UISlider alloc] init];
    self.progressSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressSlider.minimumTrackTintColor = [HATheme secondaryTextColor];
    self.progressSlider.maximumTrackTintColor = [[HATheme secondaryTextColor] colorWithAlphaComponent:0.2];
    self.progressSlider.minimumValue = 0.0;
    self.progressSlider.maximumValue = 1.0;
    self.progressSlider.continuous = NO;
    self.progressSlider.hidden = YES;
    // Smaller thumb for a compact look
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(10, 10), NO, 0);
    [[HATheme secondaryTextColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 10, 10)] fill];
    UIImage *thumbImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [self.progressSlider setThumbImage:thumbImage forState:UIControlStateNormal];
    [self.progressSlider addTarget:self action:@selector(progressSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.progressSlider];

    HAActivateConstraints(@[
        HACon([self.progressSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding]),
        HACon([self.progressSlider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding]),
        HACon([self.progressSlider.topAnchor constraintEqualToAnchor:self.muteButton.bottomAnchor constant:6]),
    ]);

    // ── Source + shuffle + repeat row (below progress) ──
    self.sourceButton = HASystemButton();
    self.sourceButton.titleLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    self.sourceButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.sourceButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sourceButton.hidden = YES;
    [self.sourceButton addTarget:self action:@selector(sourceTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.sourceButton];

    self.shuffleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.shuffleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.shuffleButton];

    self.repeatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.repeatButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.repeatButton addTarget:self action:@selector(repeatTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.repeatButton];

    HAActivateConstraints(@[
        HACon([self.sourceButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding]),
        HACon([self.sourceButton.topAnchor constraintEqualToAnchor:self.progressSlider.bottomAnchor constant:6]),
        HACon([self.sourceButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.shuffleButton.leadingAnchor constant:-8]),

        HACon([self.repeatButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding]),
        HACon([self.repeatButton.centerYAnchor constraintEqualToAnchor:self.sourceButton.centerYAnchor]),
        HACon([self.repeatButton.widthAnchor constraintEqualToConstant:24]),
        HACon([self.repeatButton.heightAnchor constraintEqualToConstant:24]),

        HACon([self.shuffleButton.trailingAnchor constraintEqualToAnchor:self.repeatButton.leadingAnchor constant:-8]),
        HACon([self.shuffleButton.centerYAnchor constraintEqualToAnchor:self.sourceButton.centerYAnchor]),
        HACon([self.shuffleButton.widthAnchor constraintEqualToConstant:24]),
        HACon([self.shuffleButton.heightAnchor constraintEqualToConstant:24]),
    ]);
}

- (UIButton *)makeTransportButtonWithIconName:(NSString *)iconName action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.layer.cornerRadius = kBtnSize / 2.0;
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    [HAIconMapper setIconName:iconName onButton:btn size:kBtnIconSize color:[HATheme primaryTextColor]];

    [self.contentView addSubview:btn];
    return btn;
}

/// Update a transport button's icon glyph (e.g. switching play <-> pause).
- (void)setButton:(UIButton *)btn iconName:(NSString *)iconName color:(UIColor *)color {
    [HAIconMapper setIconName:iconName onButton:btn size:kBtnIconSize color:color ?: [HATheme primaryTextColor]];
}

#pragma mark - Preferred Height

+ (CGFloat)preferredHeight {
    // icon row + media info + transport + volume + progress + source/shuffle row + bottom
    // 12 + 36 + 8 + 16 + 8 + 36 + 8 + 28 + 6 + 4 + 6 + 20 + 8 = 196
    return 196.0;
}

#pragma mark - Configuration

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];
    self.volumeSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    if (!entity) return;

    BOOL available = entity.isAvailable;
    BOOL playing   = entity.isPlaying;
    BOOL paused    = entity.isPaused;
    BOOL active    = playing || paused;

    // ── Icon ──
    NSString *iconName = configItem.customProperties[@"icon"];
    NSString *glyph = nil;
    if (iconName) {
        if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
        glyph = [HAIconMapper glyphForIconName:iconName];
    }
    if (!glyph) glyph = [HAEntityDisplayHelper iconGlyphForEntity:entity];
    self.iconLabel.text = glyph ?: @"?";

    UIColor *iconColor = [HAEntityDisplayHelper iconColorForEntity:entity];
    self.iconLabel.textColor = iconColor;
    self.iconCircle.backgroundColor = [iconColor colorWithAlphaComponent:0.12];

    // ── Album art (entity_picture) ──
    [[HAHTTPClient sharedClient] cancelTask:self.artLoadTask];
    NSString *picturePath = HAAttrString(entity.attributes, @"entity_picture");
    if ([picturePath hasPrefix:@"demo://"]) {
        // Demo mode placeholder: generate a colored gradient image
        self.albumArtView.image = [self demoPla:entity.state];
        self.albumArtView.hidden = NO;
    } else if (picturePath.length > 0) {
        [self loadAlbumArt:picturePath];
    } else {
        self.albumArtView.hidden = YES;
        self.albumArtView.image = nil;
    }

    // ── Name ──
    self.mpNameLabel.text = [HAEntityDisplayHelper displayNameForEntity:entity configItem:configItem nameOverride:nil];

    // ── State ──
    NSString *stateText = [HAEntityDisplayHelper humanReadableState:entity.state];
    self.mpStateLabel.text = stateText;
    self.mpStateLabel.textColor = active ? iconColor : [HATheme secondaryTextColor];

    // ── Media info ──
    NSString *title  = [entity mediaTitle];
    NSString *artist = [entity mediaArtist];
    if (title.length > 0 && artist.length > 0) {
        self.mediaInfoLabel.text = [NSString stringWithFormat:@"%@ \u2014 %@", artist, title];
    } else if (title.length > 0) {
        self.mediaInfoLabel.text = title;
    } else {
        self.mediaInfoLabel.text = nil;
    }

    // ── Play/pause button icon ──
    if (playing) {
        [self setButton:self.playPauseButton iconName:@"pause" color:[HATheme primaryTextColor]];
    } else {
        [self setButton:self.playPauseButton iconName:@"play" color:[HATheme primaryTextColor]];
    }

    // ── Button enable states ──
    self.prevButton.enabled      = available && active;
    self.playPauseButton.enabled = available;
    self.nextButton.enabled      = available && active;
    self.prevButton.alpha      = (available && active) ? 1.0 : 0.4;
    self.playPauseButton.alpha = available ? 1.0 : 0.4;
    self.nextButton.alpha      = (available && active) ? 1.0 : 0.4;

    // ── Volume ──
    NSNumber *volLevel = [entity volumeLevel];
    BOOL muted = [entity isVolumeMuted];
    if (volLevel) {
        self.volumeSlider.value = [volLevel floatValue];
        NSInteger pct = (NSInteger)([volLevel floatValue] * 100);
        self.volumeLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];
    } else {
        self.volumeSlider.value = 0;
        self.volumeLabel.text = @"—";
    }
    self.volumeSlider.enabled = available;

    // Mute button icon
    NSString *muteIcon = muted ? @"volume-off" : @"volume-high";
    UIColor *muteColor = muted ? [UIColor systemRedColor] : [HATheme secondaryTextColor];
    [HAIconMapper setIconName:muteIcon onButton:self.muteButton size:16 color:muteColor];
    self.muteButton.enabled = available;

    // ── Progress slider (seek-capable) ──
    NSNumber *duration = [entity mediaDuration];
    NSNumber *position = [entity mediaPosition];
    if (duration && [duration doubleValue] > 0 && position) {
        self.lastKnownDuration = [duration doubleValue];
        float progress = (float)([position doubleValue] / self.lastKnownDuration);
        // Don't update while user is dragging
        if (!self.progressSlider.isTracking) {
            self.progressSlider.value = MIN(1.0, MAX(0.0, progress));
        }
        self.progressSlider.hidden = NO;
        self.progressSlider.enabled = available;
    } else {
        self.lastKnownDuration = 0;
        self.progressSlider.hidden = YES;
    }

    // ── Source selector ──
    NSArray *sourceList = [entity mediaSourceList];
    NSString *currentSource = [entity mediaSource];
    if (sourceList.count > 0) {
        NSString *sourceTitle = currentSource.length > 0 ? currentSource : @"Source";
        [self.sourceButton setTitle:[NSString stringWithFormat:@"%@  \u25BE", sourceTitle] forState:UIControlStateNormal];
        self.sourceButton.hidden = NO;
        self.sourceButton.enabled = available;
    } else {
        self.sourceButton.hidden = YES;
    }

    // ── Shuffle button ──
    BOOL shuffle = [entity mediaShuffle];
    UIColor *shuffleColor = shuffle ? [UIColor systemBlueColor] : [HATheme secondaryTextColor];
    [HAIconMapper setIconName:@"shuffle-variant" onButton:self.shuffleButton size:14 color:shuffleColor];

    // ── Repeat button ──
    NSString *repeatMode = [entity mediaRepeat];
    NSString *repeatIconName = [repeatMode isEqualToString:@"one"] ? @"repeat-once" : @"repeat";
    UIColor *repeatColor = [repeatMode isEqualToString:@"off"] ? [HATheme secondaryTextColor] : [UIColor systemBlueColor];
    [HAIconMapper setIconName:repeatIconName onButton:self.repeatButton size:14 color:repeatColor];

    // ── Card background ──
    if (playing) {
        self.contentView.backgroundColor = [HATheme activeTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

#pragma mark - Actions

- (UIImage *)demoPla:(NSString *)state {
    CGFloat size = 60;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), YES, 0);
    BOOL playing = [state isEqualToString:@"playing"];
    UIColor *c1 = playing ? [UIColor colorWithRed:0.3 green:0.2 blue:0.6 alpha:1] : [UIColor darkGrayColor];
    UIColor *c2 = playing ? [UIColor colorWithRed:0.6 green:0.3 blue:0.8 alpha:1] : [UIColor grayColor];
    [c1 setFill]; UIRectFill(CGRectMake(0, 0, size, size / 2));
    [c2 setFill]; UIRectFill(CGRectMake(0, size / 2, size, size / 2));
    // Draw a music note symbol
    NSDictionary *attrs = @{HAFontAttributeName: [UIFont systemFontOfSize:28], HAForegroundColorAttributeName: [UIColor whiteColor]};
    [@"\u266B" ha_drawAtPoint:CGPointMake(size / 2 - 10, size / 2 - 16) withAttributes:attrs];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)loadAlbumArt:(NSString *)picturePath {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (!auth.isConfigured) return;

    // entity_picture is a relative path like /api/media_player_proxy/media_player.living_room
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", auth.serverURL, picturePath]];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", auth.accessToken] forHTTPHeaderField:@"Authorization"];

    __weak typeof(self) weakSelf = self;
    self.artLoadTask = [[HAHTTPClient sharedClient] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) return;
            UIImage *image = [UIImage imageWithData:data];
            if (!image) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf.albumArtView.image = image;
                strongSelf.albumArtView.hidden = NO;
            });
        }];
}

- (void)prevTapped {
    [HAHaptics lightImpact];
    [self callService:@"media_previous_track" inDomain:@"media_player"];
}

- (void)playPauseTapped {
    [HAHaptics mediumImpact];
    [self callService:@"media_play_pause" inDomain:@"media_player"];
}

- (void)nextTapped {
    [HAHaptics lightImpact];
    [self callService:@"media_next_track" inDomain:@"media_player"];
}

- (void)volumeSliderTouchUp:(UISlider *)sender {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    NSInteger pct = (NSInteger)(sender.value * 100);
    self.volumeLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];
    [[HAConnectionManager sharedManager] callService:@"volume_set"
                                            inDomain:@"media_player"
                                            withData:@{@"volume_level": @(sender.value)}
                                            entityId:self.entity.entityId];
}

- (void)muteTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    BOOL currentlyMuted = [self.entity isVolumeMuted];
    [[HAConnectionManager sharedManager] callService:@"volume_mute"
                                            inDomain:@"media_player"
                                            withData:@{@"is_volume_muted": @(!currentlyMuted)}
                                            entityId:self.entity.entityId];
}

- (void)sourceTapped {
    if (!self.entity) return;
    NSArray *sources = [self.entity mediaSourceList];
    if (sources.count == 0) return;

    [HAHaptics selectionChanged];
    NSString *current = [self.entity mediaSource];

    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:sources.count];
    for (NSString *source in sources) {
        BOOL isSelected = [source isEqualToString:current];
        [titles addObject:isSelected ? [NSString stringWithFormat:@"\u2713 %@", source] : source];
    }

    UIViewController *vc = [self ha_parentViewController];
    if (vc) {
        [vc ha_showActionSheetWithTitle:@"Source"
                            cancelTitle:@"Cancel"
                           actionTitles:titles
                             sourceView:self.sourceButton
                                handler:^(NSInteger index) {
            [[HAConnectionManager sharedManager] callService:@"select_source"
                                                    inDomain:@"media_player"
                                                    withData:@{@"source": sources[(NSUInteger)index]}
                                                    entityId:self.entity.entityId];
        }];
    }
}

- (void)shuffleTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    BOOL current = [self.entity mediaShuffle];
    [[HAConnectionManager sharedManager] callService:@"shuffle_set"
                                            inDomain:@"media_player"
                                            withData:@{@"shuffle": @(!current)}
                                            entityId:self.entity.entityId];
}

- (void)repeatTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    // Cycle: off → all → one → off
    NSString *current = [self.entity mediaRepeat];
    NSString *next;
    if ([current isEqualToString:@"off"]) next = @"all";
    else if ([current isEqualToString:@"all"]) next = @"one";
    else next = @"off";
    [[HAConnectionManager sharedManager] callService:@"repeat_set"
                                            inDomain:@"media_player"
                                            withData:@{@"repeat": next}
                                            entityId:self.entity.entityId];
}

- (void)progressSliderChanged:(UISlider *)slider {
    if (!self.entity || self.lastKnownDuration <= 0) return;
    [HAHaptics lightImpact];
    double seekPosition = slider.value * self.lastKnownDuration;
    [[HAConnectionManager sharedManager] callService:@"media_seek"
                                            inDomain:@"media_player"
                                            withData:@{@"seek_position": @(seekPosition)}
                                            entityId:self.entity.entityId];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat midX = w / 2.0;

        // Icon circle: top-left
        self.iconCircle.frame = CGRectMake(kPadding, kPadding, kIconCircleSize, kIconCircleSize);
        self.iconLabel.frame = CGRectMake(0, 0, kIconCircleSize, kIconCircleSize);
        self.albumArtView.frame = self.iconCircle.frame;

        // Name: right of icon
        CGFloat nameX = kPadding + kIconCircleSize + 10;
        CGFloat nameW = w - nameX - kPadding;
        CGSize nameSize = [self.mpNameLabel sizeThatFits:CGSizeMake(nameW, CGFLOAT_MAX)];
        self.mpNameLabel.frame = CGRectMake(nameX, kPadding + 1, nameW, nameSize.height);

        // State: below name
        CGSize stateSize = [self.mpStateLabel sizeThatFits:CGSizeMake(nameW, CGFLOAT_MAX)];
        self.mpStateLabel.frame = CGRectMake(nameX, CGRectGetMaxY(self.mpNameLabel.frame) + 1, nameW, stateSize.height);

        // Media info: below icon row
        CGFloat mediaY = kPadding + kIconCircleSize + 8;
        CGSize mediaSize = [self.mediaInfoLabel sizeThatFits:CGSizeMake(w - kPadding * 2, CGFLOAT_MAX)];
        self.mediaInfoLabel.frame = CGRectMake(kPadding, mediaY, w - kPadding * 2, mediaSize.height);

        // Transport buttons: centered row below media info
        CGFloat btnY = CGRectGetMaxY(self.mediaInfoLabel.frame) + 8;
        self.playPauseButton.frame = CGRectMake(midX - kBtnSize / 2.0, btnY, kBtnSize, kBtnSize);
        self.prevButton.frame = CGRectMake(midX - kBtnSize / 2.0 - kBtnSpacing - kBtnSize, btnY, kBtnSize, kBtnSize);
        self.nextButton.frame = CGRectMake(midX + kBtnSize / 2.0 + kBtnSpacing, btnY, kBtnSize, kBtnSize);

        // Volume row: below transport
        CGFloat volY = btnY + kBtnSize + 8;
        self.muteButton.frame = CGRectMake(kPadding, volY, 28, 28);
        self.volumeLabel.frame = CGRectMake(w - kPadding - 36, volY, 36, 28);
        self.volumeSlider.frame = CGRectMake(kPadding + 34, volY, w - kPadding * 2 - 34 - 42, 28);

        // Progress slider: below volume
        CGFloat progY = volY + 28 + 6;
        self.progressSlider.frame = CGRectMake(kPadding, progY, w - kPadding * 2, 20);

        // Source + shuffle + repeat row
        CGFloat srcY = progY + 20 + 6;
        CGSize srcSize = [self.sourceButton sizeThatFits:CGSizeMake(w / 2.0, CGFLOAT_MAX)];
        self.sourceButton.frame = CGRectMake(kPadding, srcY, srcSize.width, srcSize.height);
        self.repeatButton.frame = CGRectMake(w - kPadding - 24, srcY, 24, 24);
        self.shuffleButton.frame = CGRectMake(CGRectGetMinX(self.repeatButton.frame) - 32, srcY, 24, 24);
    }
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconLabel.text = nil;
    self.mpNameLabel.text = nil;
    self.mpStateLabel.text = nil;
    self.mediaInfoLabel.text = nil;
    self.prevButton.alpha = 1.0;
    self.playPauseButton.alpha = 1.0;
    self.nextButton.alpha = 1.0;
    self.iconCircle.backgroundColor = nil;
    self.volumeSlider.value = 0;
    self.volumeLabel.text = nil;
    [[HAHTTPClient sharedClient] cancelTask:self.artLoadTask];
    self.artLoadTask = nil;
    self.albumArtView.image = nil;
    self.albumArtView.hidden = YES;
    self.progressSlider.value = 0;
    self.progressSlider.hidden = YES;
    self.lastKnownDuration = 0;
    self.sourceButton.hidden = YES;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.mpNameLabel.textColor = [HATheme primaryTextColor];
    self.mpStateLabel.textColor = [HATheme secondaryTextColor];
    self.mediaInfoLabel.textColor = [HATheme secondaryTextColor];
    self.prevButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.playPauseButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.nextButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.volumeLabel.textColor = [HATheme secondaryTextColor];
}

@end
