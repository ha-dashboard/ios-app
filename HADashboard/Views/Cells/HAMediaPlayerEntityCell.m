#import "HAMediaPlayerEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIView+HAUtilities.h"

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
@property (nonatomic, strong) NSURLSessionDataTask *artLoadTask;
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

    [NSLayoutConstraint activateConstraints:@[
        [self.albumArtView.centerXAnchor constraintEqualToAnchor:self.iconCircle.centerXAnchor],
        [self.albumArtView.centerYAnchor constraintEqualToAnchor:self.iconCircle.centerYAnchor],
        [self.albumArtView.widthAnchor constraintEqualToConstant:kIconCircleSize],
        [self.albumArtView.heightAnchor constraintEqualToConstant:kIconCircleSize],
    ]];

    // ── Name label (right of icon) ──
    self.mpNameLabel = [self labelWithFont:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium] color:[HATheme primaryTextColor] lines:1];
    self.mpNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    // ── State label (below name, right of icon) ──
    self.mpStateLabel = [self labelWithFont:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];

    // ── Media info (artist - title) ──
    self.mediaInfoLabel = [self labelWithFont:[UIFont systemFontOfSize:12 weight:UIFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.mediaInfoLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    // ── Transport buttons (prev | play/pause | next) ──
    self.prevButton      = [self makeTransportButtonWithIconName:@"skip-previous" action:@selector(prevTapped)];
    self.playPauseButton = [self makeTransportButtonWithIconName:@"play"          action:@selector(playPauseTapped)];
    self.nextButton      = [self makeTransportButtonWithIconName:@"skip-next"     action:@selector(nextTapped)];

    // ── Constraints ──

    // Icon circle: top-left
    [NSLayoutConstraint activateConstraints:@[
        [self.iconCircle.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
        [self.iconCircle.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kPadding],
        [self.iconCircle.widthAnchor constraintEqualToConstant:kIconCircleSize],
        [self.iconCircle.heightAnchor constraintEqualToConstant:kIconCircleSize],
        [self.iconLabel.centerXAnchor constraintEqualToAnchor:self.iconCircle.centerXAnchor],
        [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.iconCircle.centerYAnchor],
    ]];

    // Name: right of icon, vertically centered in top section
    [NSLayoutConstraint activateConstraints:@[
        [self.mpNameLabel.leadingAnchor constraintEqualToAnchor:self.iconCircle.trailingAnchor constant:10],
        [self.mpNameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],
        [self.mpNameLabel.topAnchor constraintEqualToAnchor:self.iconCircle.topAnchor constant:1],
    ]];

    // State: below name
    [NSLayoutConstraint activateConstraints:@[
        [self.mpStateLabel.leadingAnchor constraintEqualToAnchor:self.mpNameLabel.leadingAnchor],
        [self.mpStateLabel.trailingAnchor constraintEqualToAnchor:self.mpNameLabel.trailingAnchor],
        [self.mpStateLabel.topAnchor constraintEqualToAnchor:self.mpNameLabel.bottomAnchor constant:1],
    ]];

    // Media info: below the icon/name row
    [NSLayoutConstraint activateConstraints:@[
        [self.mediaInfoLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
        [self.mediaInfoLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],
        [self.mediaInfoLabel.topAnchor constraintEqualToAnchor:self.iconCircle.bottomAnchor constant:8],
    ]];

    // Transport buttons: centered horizontal row below media info
    [NSLayoutConstraint activateConstraints:@[
        // Play/pause centered
        [self.playPauseButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.playPauseButton.topAnchor constraintEqualToAnchor:self.mediaInfoLabel.bottomAnchor constant:8],
        [self.playPauseButton.widthAnchor constraintEqualToConstant:kBtnSize],
        [self.playPauseButton.heightAnchor constraintEqualToConstant:kBtnSize],

        // Prev: left of play/pause
        [self.prevButton.trailingAnchor constraintEqualToAnchor:self.playPauseButton.leadingAnchor constant:-kBtnSpacing],
        [self.prevButton.centerYAnchor constraintEqualToAnchor:self.playPauseButton.centerYAnchor],
        [self.prevButton.widthAnchor constraintEqualToConstant:kBtnSize],
        [self.prevButton.heightAnchor constraintEqualToConstant:kBtnSize],

        // Next: right of play/pause
        [self.nextButton.leadingAnchor constraintEqualToAnchor:self.playPauseButton.trailingAnchor constant:kBtnSpacing],
        [self.nextButton.centerYAnchor constraintEqualToAnchor:self.playPauseButton.centerYAnchor],
        [self.nextButton.widthAnchor constraintEqualToConstant:kBtnSize],
        [self.nextButton.heightAnchor constraintEqualToConstant:kBtnSize],
    ]];

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
    self.volumeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.volumeLabel.textColor = [HATheme secondaryTextColor];
    self.volumeLabel.textAlignment = NSTextAlignmentRight;
    self.volumeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.volumeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.muteButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
        [self.muteButton.topAnchor constraintEqualToAnchor:self.playPauseButton.bottomAnchor constant:8],
        [self.muteButton.widthAnchor constraintEqualToConstant:28],
        [self.muteButton.heightAnchor constraintEqualToConstant:28],

        [self.volumeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],
        [self.volumeLabel.centerYAnchor constraintEqualToAnchor:self.muteButton.centerYAnchor],
        [self.volumeLabel.widthAnchor constraintEqualToConstant:36],

        [self.volumeSlider.leadingAnchor constraintEqualToAnchor:self.muteButton.trailingAnchor constant:6],
        [self.volumeSlider.trailingAnchor constraintEqualToAnchor:self.volumeLabel.leadingAnchor constant:-6],
        [self.volumeSlider.centerYAnchor constraintEqualToAnchor:self.muteButton.centerYAnchor],
    ]];

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

    [NSLayoutConstraint activateConstraints:@[
        [self.progressSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
        [self.progressSlider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],
        [self.progressSlider.topAnchor constraintEqualToAnchor:self.muteButton.bottomAnchor constant:6],
    ]];

    // ── Source + shuffle + repeat row (below progress) ──
    self.sourceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sourceButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
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

    [NSLayoutConstraint activateConstraints:@[
        [self.sourceButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
        [self.sourceButton.topAnchor constraintEqualToAnchor:self.progressSlider.bottomAnchor constant:6],
        [self.sourceButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.shuffleButton.leadingAnchor constant:-8],

        [self.repeatButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],
        [self.repeatButton.centerYAnchor constraintEqualToAnchor:self.sourceButton.centerYAnchor],
        [self.repeatButton.widthAnchor constraintEqualToConstant:24],
        [self.repeatButton.heightAnchor constraintEqualToConstant:24],

        [self.shuffleButton.trailingAnchor constraintEqualToAnchor:self.repeatButton.leadingAnchor constant:-8],
        [self.shuffleButton.centerYAnchor constraintEqualToAnchor:self.sourceButton.centerYAnchor],
        [self.shuffleButton.widthAnchor constraintEqualToConstant:24],
        [self.shuffleButton.heightAnchor constraintEqualToConstant:24],
    ]];
}

- (UIButton *)makeTransportButtonWithIconName:(NSString *)iconName action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.layer.cornerRadius = kBtnSize / 2.0;
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    NSString *glyph = [HAIconMapper glyphForIconName:iconName];
    UIFont *iconFont = [HAIconMapper mdiFontOfSize:kBtnIconSize];
    NSDictionary *attrs = @{
        NSFontAttributeName: iconFont,
        NSForegroundColorAttributeName: [HATheme primaryTextColor],
    };
    NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:(glyph ?: @"?") attributes:attrs];
    [btn setAttributedTitle:attrTitle forState:UIControlStateNormal];

    [self.contentView addSubview:btn];
    return btn;
}

/// Update a transport button's icon glyph (e.g. switching play <-> pause).
- (void)setButton:(UIButton *)btn iconName:(NSString *)iconName color:(UIColor *)color {
    NSString *glyph = [HAIconMapper glyphForIconName:iconName];
    UIFont *iconFont = [HAIconMapper mdiFontOfSize:kBtnIconSize];
    NSDictionary *attrs = @{
        NSFontAttributeName: iconFont,
        NSForegroundColorAttributeName: color ?: [HATheme primaryTextColor],
    };
    NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:(glyph ?: @"?") attributes:attrs];
    [btn setAttributedTitle:attrTitle forState:UIControlStateNormal];
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
    [self.artLoadTask cancel];
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
    NSString *muteGlyph = [HAIconMapper glyphForIconName:muteIcon];
    UIFont *muteFont = [HAIconMapper mdiFontOfSize:16];
    UIColor *muteColor = muted ? [UIColor systemRedColor] : [HATheme secondaryTextColor];
    NSDictionary *muteAttrs = @{NSFontAttributeName: muteFont, NSForegroundColorAttributeName: muteColor};
    [self.muteButton setAttributedTitle:[[NSAttributedString alloc] initWithString:(muteGlyph ?: @"🔊") attributes:muteAttrs]
                               forState:UIControlStateNormal];
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
    NSString *shuffleGlyph = [HAIconMapper glyphForIconName:@"shuffle-variant"];
    UIFont *ctrlFont = [HAIconMapper mdiFontOfSize:14];
    UIColor *shuffleColor = shuffle ? [UIColor systemBlueColor] : [HATheme secondaryTextColor];
    [self.shuffleButton setAttributedTitle:[[NSAttributedString alloc] initWithString:(shuffleGlyph ?: @"🔀")
                                                                           attributes:@{NSFontAttributeName: ctrlFont, NSForegroundColorAttributeName: shuffleColor}]
                                  forState:UIControlStateNormal];

    // ── Repeat button ──
    NSString *repeatMode = [entity mediaRepeat];
    NSString *repeatIconName = [repeatMode isEqualToString:@"one"] ? @"repeat-once" : @"repeat";
    NSString *repeatGlyph = [HAIconMapper glyphForIconName:repeatIconName];
    UIColor *repeatColor = [repeatMode isEqualToString:@"off"] ? [HATheme secondaryTextColor] : [UIColor systemBlueColor];
    [self.repeatButton setAttributedTitle:[[NSAttributedString alloc] initWithString:(repeatGlyph ?: @"🔁")
                                                                          attributes:@{NSFontAttributeName: ctrlFont, NSForegroundColorAttributeName: repeatColor}]
                                 forState:UIControlStateNormal];

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
    NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:28], NSForegroundColorAttributeName: [UIColor whiteColor]};
    [@"\u266B" drawAtPoint:CGPointMake(size / 2 - 10, size / 2 - 16) withAttributes:attrs];
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
    self.artLoadTask = [[NSURLSession sharedSession] dataTaskWithRequest:request
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
    [self.artLoadTask resume];
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

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Source"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *source in sources) {
        BOOL isSelected = [source isEqualToString:current];
        NSString *title = isSelected ? [NSString stringWithFormat:@"\u2713 %@", source] : source;
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[HAConnectionManager sharedManager] callService:@"select_source"
                                                    inDomain:@"media_player"
                                                    withData:@{@"source": source}
                                                    entityId:self.entity.entityId];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.sourceButton;
    alert.popoverPresentationController.sourceRect = self.sourceButton.bounds;

    UIViewController *vc = [self ha_parentViewController];
    if (vc) [vc presentViewController:alert animated:YES completion:nil];
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
    [self.artLoadTask cancel];
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
