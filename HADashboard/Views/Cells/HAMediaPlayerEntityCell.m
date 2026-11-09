#import "HAMediaPlayerEntityCell.h"
#import "HAStrings.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "HAStateLocalizer.h"
#import "HAAction.h"
#import "HAActionDispatcher.h"
#import "UIView+HAUtilities.h"

static const CGFloat kIconCircleSize = 36.0;
static const CGFloat kIconFontSize   = 20.0;
static const CGFloat kBtnSize        = 36.0;
static const CGFloat kBtnIconSize    = 18.0;
static const CGFloat kBtnSpacing     = 8.0;
static const CGFloat kPadding        = 12.0;
static const CGFloat kMoreInfoSize   = 28.0;

// Rows below the header, top to bottom. Each row's top is chained to the
// bottom of the previous *visible* row (or the media info label), so rows
// that have nothing to show collapse instead of leaving blank space.
static const CGFloat kHeaderHeight       = 48.0; // kPadding + kIconCircleSize
static const CGFloat kMediaInfoGap       = 8.0;
static const CGFloat kControlRowGap      = 8.0;
static const CGFloat kControlRowHeight   = 36.0; // kBtnSize
static const CGFloat kVolumeRowGap       = 8.0;
static const CGFloat kVolumeRowHeight    = 28.0;
static const CGFloat kProgressRowGap     = 6.0;
static const CGFloat kProgressRowHeight  = 20.0;
static const CGFloat kBottomRowGap       = 6.0;
static const CGFloat kBottomRowHeight    = 24.0;
static const CGFloat kMediaInfoFontSize  = 12.0;

/// Which parts of the card are shown for an entity. Shared by
/// -configureWithEntity:configItem: and +preferredHeightForEntity: so the
/// cell's layout and the collection view's item height can't disagree.
typedef struct {
    BOOL mediaInfo;
    BOOL controlRow;
    BOOL volumeRow;
    BOOL progressRow;
    BOOL bottomRow;
} HAMediaCardRows;

static NSString *HAMediaInfoText(HAEntity *entity) {
    NSString *title  = [entity mediaTitle];
    NSString *artist = [entity mediaArtist];
    if (title.length > 0 && artist.length > 0) {
        return [NSString stringWithFormat:@"%@ — %@", artist, title];
    }
    return title.length > 0 ? title : nil;
}

static BOOL HAMediaHasProgress(HAEntity *entity) {
    NSNumber *duration = [entity mediaDuration];
    return duration && [duration doubleValue] > 0 && [entity mediaPosition] != nil;
}

static HAMediaCardRows HAMediaCardRowsForEntity(HAEntity *entity, NSArray<NSString *> *controls) {
    HAMediaCardRows rows = {NO, NO, NO, NO, NO};
    if (!entity) return rows;
    BOOL active = [HAEntity mediaPlayerStateIsActive:entity.state];
    rows.mediaInfo = active && HAMediaInfoText(entity).length > 0;
    rows.progressRow = active && HAMediaHasProgress(entity);
    for (NSString *c in controls) {
        if ([c isEqualToString:HAMediaControlTurnOn] || [c isEqualToString:HAMediaControlTurnOff] ||
            [c isEqualToString:HAMediaControlPreviousTrack] || [c isEqualToString:HAMediaControlNextTrack] ||
            [c isEqualToString:HAMediaControlPlay] || [c isEqualToString:HAMediaControlPause] ||
            [c isEqualToString:HAMediaControlStop] || [c isEqualToString:HAMediaControlPlayPause]) {
            rows.controlRow = YES;
        } else if ([c isEqualToString:HAMediaControlVolumeMute] || [c isEqualToString:HAMediaControlVolumeDown] ||
                   [c isEqualToString:HAMediaControlVolumeUp] || [c isEqualToString:HAMediaControlVolumeSet]) {
            rows.volumeRow = YES;
        } else if ([c isEqualToString:HAMediaControlSelectSource] || [c isEqualToString:HAMediaControlShuffle] ||
                   [c isEqualToString:HAMediaControlRepeat]) {
            rows.bottomRow = YES;
        }
    }
    return rows;
}

@interface HAMediaPlayerEntityCell ()
@property (nonatomic, strong) UIView  *iconCircle;
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *mpNameLabel;
@property (nonatomic, strong) UILabel *mpStateLabel;
@property (nonatomic, strong) UIButton *moreInfoButton;
@property (nonatomic, strong) UILabel *mediaInfoLabel;
@property (nonatomic, strong) UIView *controlRow;
@property (nonatomic, strong) UIStackView *transportStack;
@property (nonatomic, strong) UIButton *powerButton;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIView *volumeRow;
@property (nonatomic, strong) UIStackView *volumeButtonStack;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UIButton *volumeDownButton;
@property (nonatomic, strong) UIButton *volumeUpButton;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (nonatomic, strong) UILabel *volumeLabel;
@property (nonatomic, strong) UIImageView *albumArtView;
@property (nonatomic, strong) NSURLSessionDataTask *artLoadTask;
@property (nonatomic, strong) UIView *bottomRow;
@property (nonatomic, strong) UIButton *sourceButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, assign) double lastKnownDuration;
@property (nonatomic, copy) NSString *powerService;
@property (nonatomic, copy) NSString *playPauseService;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *rowChainConstraints;
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

    // ── More-info button (top-right), like HA's media-control card ⋮ ──
    self.moreInfoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.moreInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.moreInfoButton.accessibilityLabel = HALocalizedString(@"accessibility.more_info", @"VoiceOver label for the more-info (three dots) button on a card, which opens the entity's detail sheet.");
    [self.moreInfoButton addTarget:self action:@selector(moreInfoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.moreInfoButton];

    // ── Name label (right of icon) ──
    self.mpNameLabel = [self labelWithFont:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium] color:[HATheme primaryTextColor] lines:1];
    self.mpNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    // ── State label (below name, right of icon) ──
    self.mpStateLabel = [self labelWithFont:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];

    // ── Media info (artist - title) ──
    self.mediaInfoLabel = [self labelWithFont:[UIFont systemFontOfSize:kMediaInfoFontSize weight:UIFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.mediaInfoLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    // ── Header constraints ──
    [NSLayoutConstraint activateConstraints:@[
        [self.iconCircle.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
        [self.iconCircle.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kPadding],
        [self.iconCircle.widthAnchor constraintEqualToConstant:kIconCircleSize],
        [self.iconCircle.heightAnchor constraintEqualToConstant:kIconCircleSize],
        [self.iconLabel.centerXAnchor constraintEqualToAnchor:self.iconCircle.centerXAnchor],
        [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.iconCircle.centerYAnchor],

        [self.moreInfoButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
        [self.moreInfoButton.centerYAnchor constraintEqualToAnchor:self.iconCircle.centerYAnchor],
        [self.moreInfoButton.widthAnchor constraintEqualToConstant:kMoreInfoSize],
        [self.moreInfoButton.heightAnchor constraintEqualToConstant:kMoreInfoSize],

        // Name: right of icon, vertically centered in top section
        [self.mpNameLabel.leadingAnchor constraintEqualToAnchor:self.iconCircle.trailingAnchor constant:10],
        [self.mpNameLabel.trailingAnchor constraintEqualToAnchor:self.moreInfoButton.leadingAnchor constant:-2],
        [self.mpNameLabel.topAnchor constraintEqualToAnchor:self.iconCircle.topAnchor constant:1],

        // State: below name
        [self.mpStateLabel.leadingAnchor constraintEqualToAnchor:self.mpNameLabel.leadingAnchor],
        [self.mpStateLabel.trailingAnchor constraintEqualToAnchor:self.mpNameLabel.trailingAnchor],
        [self.mpStateLabel.topAnchor constraintEqualToAnchor:self.mpNameLabel.bottomAnchor constant:1],

        // Media info: below the icon/name row
        [self.mediaInfoLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
        [self.mediaInfoLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],
        [self.mediaInfoLabel.topAnchor constraintEqualToAnchor:self.iconCircle.bottomAnchor constant:kMediaInfoGap],
    ]];

    // ── Control row: power | prev | play/pause | next, centered ──
    self.controlRow = [self rowViewWithHeight:kControlRowHeight];

    self.powerButton     = [self makeTransportButtonWithIconName:@"power-standby" action:@selector(powerTapped)];
    self.prevButton      = [self makeTransportButtonWithIconName:@"skip-previous" action:@selector(prevTapped)];
    self.playPauseButton = [self makeTransportButtonWithIconName:@"play"          action:@selector(playPauseTapped)];
    self.nextButton      = [self makeTransportButtonWithIconName:@"skip-next"     action:@selector(nextTapped)];
    self.prevButton.accessibilityLabel = HALocalizedString(@"accessibility.media_player.previous_track", @"VoiceOver label for a media player's previous-track button.");
    self.nextButton.accessibilityLabel = HALocalizedString(@"accessibility.media_player.next_track", @"VoiceOver label for a media player's next-track button.");

    self.transportStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.powerButton, self.prevButton, self.playPauseButton, self.nextButton]];
    self.transportStack.axis = UILayoutConstraintAxisHorizontal;
    self.transportStack.spacing = kBtnSpacing;
    // Equal widths so a narrow card shrinks every button alike instead of overflowing.
    self.transportStack.distribution = UIStackViewDistributionFillEqually;
    self.transportStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.controlRow addSubview:self.transportStack];

    NSMutableArray<NSLayoutConstraint *> *transportConstraints = [NSMutableArray arrayWithArray:@[
        [self.transportStack.centerXAnchor constraintEqualToAnchor:self.controlRow.centerXAnchor],
        [self.transportStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.controlRow.leadingAnchor constant:kPadding],
        [self.transportStack.topAnchor constraintEqualToAnchor:self.controlRow.topAnchor],
        [self.transportStack.bottomAnchor constraintEqualToAnchor:self.controlRow.bottomAnchor],
    ]];
    for (UIButton *btn in self.transportStack.arrangedSubviews) {
        NSLayoutConstraint *width = [btn.widthAnchor constraintEqualToConstant:kBtnSize];
        width.priority = 999; // yields only when the card is too narrow
        [transportConstraints addObject:width];
    }
    [NSLayoutConstraint activateConstraints:transportConstraints];

    // ── Volume row: mute / step buttons + slider + percentage label ──
    self.volumeRow = [self rowViewWithHeight:kVolumeRowHeight];

    self.muteButton = [self makeSmallIconButtonWithAction:@selector(muteTapped)];
    self.volumeDownButton = [self makeSmallIconButtonWithAction:@selector(volumeDownTapped)];
    self.volumeUpButton = [self makeSmallIconButtonWithAction:@selector(volumeUpTapped)];
    self.volumeDownButton.accessibilityLabel = HALocalizedString(@"accessibility.media_player.volume_down", @"VoiceOver label for a media player's volume-down button.");
    self.volumeUpButton.accessibilityLabel = HALocalizedString(@"accessibility.media_player.volume_up", @"VoiceOver label for a media player's volume-up button.");

    self.volumeButtonStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.muteButton, self.volumeDownButton, self.volumeUpButton]];
    self.volumeButtonStack.axis = UILayoutConstraintAxisHorizontal;
    self.volumeButtonStack.spacing = 6;
    self.volumeButtonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.volumeRow addSubview:self.volumeButtonStack];

    self.volumeSlider = [[UISlider alloc] init];
    self.volumeSlider.minimumValue = 0.0;
    self.volumeSlider.maximumValue = 1.0;
    self.volumeSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.volumeSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.volumeSlider addTarget:self action:@selector(volumeSliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.volumeRow addSubview:self.volumeSlider];

    self.volumeLabel = [[UILabel alloc] init];
    self.volumeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.volumeLabel.textColor = [HATheme secondaryTextColor];
    self.volumeLabel.textAlignment = NSTextAlignmentRight;
    self.volumeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.volumeRow addSubview:self.volumeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.volumeButtonStack.leadingAnchor constraintEqualToAnchor:self.volumeRow.leadingAnchor constant:kPadding],
        [self.volumeButtonStack.centerYAnchor constraintEqualToAnchor:self.volumeRow.centerYAnchor],

        [self.volumeLabel.trailingAnchor constraintEqualToAnchor:self.volumeRow.trailingAnchor constant:-kPadding],
        [self.volumeLabel.centerYAnchor constraintEqualToAnchor:self.volumeRow.centerYAnchor],
        [self.volumeLabel.widthAnchor constraintEqualToConstant:36],

        [self.volumeSlider.leadingAnchor constraintEqualToAnchor:self.volumeButtonStack.trailingAnchor constant:6],
        [self.volumeSlider.trailingAnchor constraintEqualToAnchor:self.volumeLabel.leadingAnchor constant:-6],
        [self.volumeSlider.centerYAnchor constraintEqualToAnchor:self.volumeRow.centerYAnchor],
    ]];

    // ── Progress bar ──
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
        [self.progressSlider.heightAnchor constraintEqualToConstant:kProgressRowHeight],
    ]];

    // ── Source + shuffle + repeat row ──
    self.bottomRow = [self rowViewWithHeight:kBottomRowHeight];

    self.sourceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sourceButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.sourceButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.sourceButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sourceButton.hidden = YES;
    [self.sourceButton addTarget:self action:@selector(sourceTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomRow addSubview:self.sourceButton];

    self.shuffleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    self.repeatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.repeatButton addTarget:self action:@selector(repeatTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *modeStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.shuffleButton, self.repeatButton]];
    modeStack.axis = UILayoutConstraintAxisHorizontal;
    modeStack.spacing = 8;
    modeStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomRow addSubview:modeStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.sourceButton.leadingAnchor constraintEqualToAnchor:self.bottomRow.leadingAnchor constant:kPadding],
        [self.sourceButton.centerYAnchor constraintEqualToAnchor:self.bottomRow.centerYAnchor],
        [self.sourceButton.trailingAnchor constraintLessThanOrEqualToAnchor:modeStack.leadingAnchor constant:-8],

        [modeStack.trailingAnchor constraintEqualToAnchor:self.bottomRow.trailingAnchor constant:-kPadding],
        [modeStack.centerYAnchor constraintEqualToAnchor:self.bottomRow.centerYAnchor],
        [self.shuffleButton.widthAnchor constraintEqualToConstant:24],
        [self.shuffleButton.heightAnchor constraintEqualToConstant:24],
        [self.repeatButton.widthAnchor constraintEqualToConstant:24],
        [self.repeatButton.heightAnchor constraintEqualToConstant:24],
    ]];

    [self updateRowChain:(HAMediaCardRows){NO, NO, NO, NO, NO}];
}

/// A full-width, fixed-height container for one row of controls. Its top is
/// set by -updateRowChain:.
- (UIView *)rowViewWithHeight:(CGFloat)height {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [row.heightAnchor constraintEqualToConstant:height],
    ]];
    return row;
}

/// Chain each row below the previous visible one. Hidden rows sit at the
/// current anchor with no gap, so they never push later rows down.
- (void)updateRowChain:(HAMediaCardRows)rows {
    if (self.rowChainConstraints) [NSLayoutConstraint deactivateConstraints:self.rowChainConstraints];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    UIView *anchor = self.mediaInfoLabel;
    NSArray *chain = @[
        @[self.controlRow,     @(rows.controlRow),  @(kControlRowGap)],
        @[self.volumeRow,      @(rows.volumeRow),   @(kVolumeRowGap)],
        @[self.progressSlider, @(rows.progressRow), @(kProgressRowGap)],
        @[self.bottomRow,      @(rows.bottomRow),   @(kBottomRowGap)],
    ];
    for (NSArray *entry in chain) {
        UIView *row = entry[0];
        BOOL visible = [entry[1] boolValue];
        row.hidden = !visible;
        [constraints addObject:[row.topAnchor constraintEqualToAnchor:anchor.bottomAnchor
                                                             constant:visible ? [entry[2] doubleValue] : 0]];
        if (visible) anchor = row;
    }
    [NSLayoutConstraint activateConstraints:constraints];
    self.rowChainConstraints = constraints;
}

- (UIButton *)makeTransportButtonWithIconName:(NSString *)iconName action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.layer.cornerRadius = kBtnSize / 2.0;
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self setButton:btn iconName:iconName color:[HATheme primaryTextColor]];
    return btn;
}

- (UIButton *)makeSmallIconButtonWithAction:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [btn.widthAnchor constraintEqualToConstant:kVolumeRowHeight],
        [btn.heightAnchor constraintEqualToConstant:kVolumeRowHeight],
    ]];
    return btn;
}

/// Update a transport button's icon glyph (e.g. switching play <-> pause).
- (void)setButton:(UIButton *)btn iconName:(NSString *)iconName color:(UIColor *)color {
    [self setButton:btn iconName:iconName size:kBtnIconSize color:color];
}

- (void)setButton:(UIButton *)btn iconName:(NSString *)iconName size:(CGFloat)size color:(UIColor *)color {
    NSString *glyph = [HAIconMapper glyphForIconName:iconName];
    NSDictionary *attrs = @{
        NSFontAttributeName: [HAIconMapper mdiFontOfSize:size],
        NSForegroundColorAttributeName: color ?: [HATheme primaryTextColor],
    };
    NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:(glyph ?: @"?") attributes:attrs];
    [btn setAttributedTitle:attrTitle forState:UIControlStateNormal];
}

#pragma mark - Preferred Height

+ (CGFloat)preferredHeightForEntity:(HAEntity *)entity {
    HAMediaCardRows rows = HAMediaCardRowsForEntity(entity, [entity mediaControls]);
    BOOL anythingBelowHeader = rows.mediaInfo || rows.controlRow || rows.volumeRow || rows.progressRow || rows.bottomRow;
    if (!anythingBelowHeader) return kHeaderHeight + kPadding;

    CGFloat height = kHeaderHeight + kMediaInfoGap;
    if (rows.mediaInfo) height += ceil([UIFont systemFontOfSize:kMediaInfoFontSize weight:UIFontWeightRegular].lineHeight);
    if (rows.controlRow)  height += kControlRowGap + kControlRowHeight;
    if (rows.volumeRow)   height += kVolumeRowGap + kVolumeRowHeight;
    if (rows.progressRow) height += kProgressRowGap + kProgressRowHeight;
    if (rows.bottomRow)   height += kBottomRowGap + kBottomRowHeight;
    return height + kPadding;
}

#pragma mark - Configuration

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];
    self.volumeSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    NSArray<NSString *> *controls = [entity mediaControls];
    HAMediaCardRows rows = HAMediaCardRowsForEntity(entity, controls);
    [self updateRowChain:rows];

    [self setButton:self.moreInfoButton iconName:@"dots-vertical" color:[HATheme secondaryTextColor]];
    self.moreInfoButton.hidden = (entity == nil);

    if (!entity) return;

    BOOL playing   = entity.isPlaying;
    BOOL paused    = entity.isPaused;
    BOOL active    = playing || paused;
    NSInteger features = [entity supportedFeatures];

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
    self.mediaInfoLabel.text = rows.mediaInfo ? HAMediaInfoText(entity) : nil;

    // ── Power ──
    BOOL inactive = ![HAEntity mediaPlayerStateIsActive:entity.state];
    if ([controls containsObject:HAMediaControlTurnOn] && (inactive || ![controls containsObject:HAMediaControlTurnOff])) {
        self.powerService = HAMediaControlTurnOn;
    } else if ([controls containsObject:HAMediaControlTurnOff]) {
        self.powerService = HAMediaControlTurnOff;
    } else {
        self.powerService = nil;
    }
    self.powerButton.hidden = (self.powerService == nil);
    self.powerButton.accessibilityLabel = [self.powerService isEqualToString:HAMediaControlTurnOn]
        ? HALocalizedString(@"accessibility.media_player.turn_on", @"VoiceOver label for a media player's power button while the player is off.")
        : HALocalizedString(@"accessibility.media_player.turn_off", @"VoiceOver label for a media player's power button while the player is on.");

    // ── Transport ──
    [self setButton:self.powerButton iconName:@"power-standby" color:[HATheme primaryTextColor]];
    [self setButton:self.prevButton iconName:@"skip-previous" color:[HATheme primaryTextColor]];
    [self setButton:self.nextButton iconName:@"skip-next" color:[HATheme primaryTextColor]];
    self.prevButton.hidden = ![controls containsObject:HAMediaControlPreviousTrack];
    self.nextButton.hidden = ![controls containsObject:HAMediaControlNextTrack];

    NSMutableArray<NSString *> *playControls = [NSMutableArray array];
    for (NSString *c in @[HAMediaControlPlay, HAMediaControlPause, HAMediaControlStop, HAMediaControlPlayPause]) {
        if ([controls containsObject:c]) [playControls addObject:c];
    }
    // One button: assumed-state players can offer several of these at once,
    // so fold them into a single play/pause toggle.
    self.playPauseService = playControls.count == 1 ? playControls.firstObject
                          : (playControls.count > 1 ? HAMediaControlPlayPause : nil);
    self.playPauseButton.hidden = (self.playPauseService == nil);
    NSString *playIcon = @"play-pause";
    NSString *playLabel = HALocalizedString(@"accessibility.media_player.play_pause", @"VoiceOver label for a media player's combined play/pause button.");
    if ([self.playPauseService isEqualToString:HAMediaControlPlay]) {
        playIcon = @"play";
        playLabel = HALocalizedString(@"accessibility.media_player.play", @"VoiceOver label for a media player's play button.");
    } else if ([self.playPauseService isEqualToString:HAMediaControlPause]) {
        playIcon = @"pause";
        playLabel = HALocalizedString(@"accessibility.media_player.pause", @"VoiceOver label for a media player's pause button.");
    } else if ([self.playPauseService isEqualToString:HAMediaControlStop]) {
        playIcon = @"stop";
        playLabel = HALocalizedString(@"accessibility.media_player.stop", @"VoiceOver label for a media player's stop button.");
    }
    [self setButton:self.playPauseButton iconName:playIcon color:[HATheme primaryTextColor]];
    self.playPauseButton.accessibilityLabel = playLabel;

    // ── Volume ──
    BOOL showVolumeSlider = [controls containsObject:HAMediaControlVolumeSet];
    self.muteButton.hidden = ![controls containsObject:HAMediaControlVolumeMute];
    self.volumeDownButton.hidden = ![controls containsObject:HAMediaControlVolumeDown];
    self.volumeUpButton.hidden = ![controls containsObject:HAMediaControlVolumeUp];
    self.volumeSlider.hidden = !showVolumeSlider;
    self.volumeLabel.hidden = !showVolumeSlider;

    NSNumber *volLevel = [entity volumeLevel];
    BOOL muted = [entity isVolumeMuted];
    if (volLevel) {
        self.volumeSlider.value = [volLevel floatValue];
        NSInteger pct = (NSInteger)([volLevel floatValue] * 100);
        self.volumeLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];
    } else {
        self.volumeSlider.value = 0;
        self.volumeLabel.text = HALocalizedString(@"cell.media_player.no_value", @"Volume label in the media player cell, shown when no volume value is available.");
    }

    // Mute button icon
    UIColor *muteColor = muted ? [UIColor systemRedColor] : [HATheme secondaryTextColor];
    [self setButton:self.muteButton iconName:(muted ? @"volume-off" : @"volume-high") size:16 color:muteColor];
    self.muteButton.accessibilityLabel = muted
        ? HALocalizedString(@"accessibility.media_player.unmute", @"VoiceOver label for a media player's mute button while muted.")
        : HALocalizedString(@"accessibility.media_player.mute", @"VoiceOver label for a media player's mute button while not muted.");
    [self setButton:self.volumeDownButton iconName:@"volume-minus" size:16 color:[HATheme secondaryTextColor]];
    [self setButton:self.volumeUpButton iconName:@"volume-plus" size:16 color:[HATheme secondaryTextColor]];

    // ── Progress slider (seekable only with SEEK) ──
    if (rows.progressRow) {
        self.lastKnownDuration = [[entity mediaDuration] doubleValue];
        float progress = (float)([[entity mediaPosition] doubleValue] / self.lastKnownDuration);
        // Don't update while user is dragging
        if (!self.progressSlider.isTracking) {
            self.progressSlider.value = MIN(1.0, MAX(0.0, progress));
        }
        self.progressSlider.userInteractionEnabled = (features & HAMediaPlayerFeatureSeek) != 0;
    } else {
        self.lastKnownDuration = 0;
    }

    // ── Source selector ──
    if ([controls containsObject:HAMediaControlSelectSource]) {
        NSString *currentSource = [entity mediaSource];
        NSString *sourceTitle = currentSource.length > 0 ? currentSource
            : ([[HAStateLocalizer sharedLocalizer] localizedAttributeNameForDomain:@"media_player" attr:@"source"]
                ?: HALocalizedString(@"attr.source.name", @"Fallback label on the source-picker button in the media player cell, shown when no source is currently selected. Used only when Home Assistant's own translation for media_player's source attribute is unavailable."));
        [self.sourceButton setTitle:[NSString stringWithFormat:@"%@  ▾", sourceTitle] forState:UIControlStateNormal];
        self.sourceButton.hidden = NO;
    } else {
        self.sourceButton.hidden = YES;
    }

    // ── Shuffle button ──
    BOOL shuffle = [entity mediaShuffle];
    self.shuffleButton.hidden = ![controls containsObject:HAMediaControlShuffle];
    UIColor *shuffleColor = shuffle ? [UIColor systemBlueColor] : [HATheme secondaryTextColor];
    [self setButton:self.shuffleButton iconName:@"shuffle-variant" size:14 color:shuffleColor];

    // ── Repeat button ──
    NSString *repeatMode = [entity mediaRepeat];
    self.repeatButton.hidden = ![controls containsObject:HAMediaControlRepeat];
    NSString *repeatIconName = [repeatMode isEqualToString:@"one"] ? @"repeat-once" : @"repeat";
    UIColor *repeatColor = [repeatMode isEqualToString:@"off"] ? [HATheme secondaryTextColor] : [UIColor systemBlueColor];
    [self setButton:self.repeatButton iconName:repeatIconName size:14 color:repeatColor];

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
    [@"♫" drawAtPoint:CGPointMake(size / 2 - 10, size / 2 - 16) withAttributes:attrs];
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

- (void)moreInfoTapped {
    if (!self.entity) return;
    HAAction *action = [[HAAction alloc] init];
    action.action = HAActionTypeMoreInfo;
    [[HAActionDispatcher sharedDispatcher] executeAction:action
                                              forEntity:self.entity
                                     fromViewController:[self ha_parentViewController]];
}

- (void)powerTapped {
    if (!self.powerService) return;
    [HAHaptics mediumImpact];
    [self callService:self.powerService inDomain:@"media_player"];
}

- (void)prevTapped {
    [HAHaptics lightImpact];
    [self callService:@"media_previous_track" inDomain:@"media_player"];
}

- (void)playPauseTapped {
    if (!self.playPauseService) return;
    [HAHaptics mediumImpact];
    [self callService:self.playPauseService inDomain:@"media_player"];
}

- (void)nextTapped {
    [HAHaptics lightImpact];
    [self callService:@"media_next_track" inDomain:@"media_player"];
}

- (void)volumeDownTapped {
    [HAHaptics lightImpact];
    [self callService:@"volume_down" inDomain:@"media_player"];
}

- (void)volumeUpTapped {
    [HAHaptics lightImpact];
    [self callService:@"volume_up" inDomain:@"media_player"];
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

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:HALocalizedString(@"cell.media_player.source", @"Action sheet title for picking a media source in the media player cell.")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *source in sources) {
        BOOL isSelected = [source isEqualToString:current];
        NSString *title = isSelected ? [NSString stringWithFormat:@"✓ %@", source] : source;
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[HAConnectionManager sharedManager] callService:@"select_source"
                                                    inDomain:@"media_player"
                                                    withData:@{@"source": source}
                                                    entityId:self.entity.entityId];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:HALocalizedString(@"action.cancel", @"Cancel button in alerts and action sheets throughout Settings.") style:UIAlertActionStyleCancel handler:nil]];
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
    self.iconCircle.backgroundColor = nil;
    self.volumeSlider.value = 0;
    self.volumeLabel.text = nil;
    [self.artLoadTask cancel];
    self.artLoadTask = nil;
    self.albumArtView.image = nil;
    self.albumArtView.hidden = YES;
    self.progressSlider.value = 0;
    self.lastKnownDuration = 0;
    self.sourceButton.hidden = YES;
    self.powerService = nil;
    self.playPauseService = nil;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.mpNameLabel.textColor = [HATheme primaryTextColor];
    self.mpStateLabel.textColor = [HATheme secondaryTextColor];
    self.mediaInfoLabel.textColor = [HATheme secondaryTextColor];
    self.powerButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.prevButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.playPauseButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.nextButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.volumeLabel.textColor = [HATheme secondaryTextColor];
}

@end
