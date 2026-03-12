#import "HAAutoLayout.h"
#import "HAStackView.h"
#import "HAGlanceItemView.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIFont+HACompat.h"

static const CGFloat kIconSize = 24.0;
static const CGFloat kNameFontSize = 11.0;
static const CGFloat kStateFontSize = 11.0;
static const CGFloat kVerticalSpacing = 3.0;
static const CGFloat kVerticalPadding = 6.0;

@interface HAGlanceItemView ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) HAStackView *stack;
@property (nonatomic, weak, readwrite) HAEntity *entity;
@property (nonatomic, copy, readwrite) NSDictionary *actionConfig;
@end

@implementation HAGlanceItemView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.font = [HAIconMapper mdiFontOfSize:kIconSize];
    self.iconLabel.textAlignment = NSTextAlignmentCenter;
    self.iconLabel.textColor = [HATheme secondaryTextColor];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont ha_systemFontOfSize:kNameFontSize weight:HAFontWeightMedium];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.textColor = [HATheme primaryTextColor];
    self.nameLabel.numberOfLines = 1;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.font = [UIFont ha_systemFontOfSize:kStateFontSize weight:HAFontWeightRegular];
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.textColor = [HATheme secondaryTextColor];
    self.stateLabel.numberOfLines = 1;
    self.stateLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.stack = [[HAStackView alloc] initWithArrangedSubviews:@[self.iconLabel, self.nameLabel, self.stateLabel]];
    self.stack.axis = 1;
    self.stack.alignment = 3;
    self.stack.spacing = kVerticalSpacing;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.stack];

    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:2],
            [self.stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-2],
        ]];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGSize stackSize = [self.stack sizeThatFits:self.bounds.size];
        self.stack.frame = CGRectMake((self.bounds.size.width - stackSize.width) / 2.0,
                                      (self.bounds.size.height - stackSize.height) / 2.0,
                                      stackSize.width, stackSize.height);
    }
}

- (void)configureWithEntity:(HAEntity *)entity
               entityConfig:(NSDictionary *)config
                   showName:(BOOL)showName
                  showState:(BOOL)showState
                   showIcon:(BOOL)showIcon
                 stateColor:(BOOL)stateColor {
    self.entity = entity;

    // Store per-entity action config
    NSMutableDictionary *actions = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"tap_action", @"hold_action", @"double_tap_action"]) {
        if ([config[key] isKindOfClass:[NSDictionary class]]) {
            actions[key] = config[key];
        }
    }
    self.actionConfig = actions.count > 0 ? [actions copy] : nil;

    // Per-entity show_state override
    if (config[@"show_state"]) {
        showState = [config[@"show_state"] boolValue];
    }

    // Icon
    self.iconLabel.hidden = !showIcon;
    if (showIcon) {
        NSString *iconName = config[@"icon"];
        NSString *glyph = nil;
        if ([iconName isKindOfClass:[NSString class]]) {
            if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
            glyph = [HAIconMapper glyphForIconName:iconName];
        }
        if (!glyph && entity) {
            glyph = [HAEntityDisplayHelper iconGlyphForEntity:entity];
        }
        self.iconLabel.text = glyph ?: @"?";

        // State color: tint icon based on entity active state
        if (stateColor && entity) {
            self.iconLabel.textColor = [HAEntityDisplayHelper iconColorForEntity:entity];
        } else {
            self.iconLabel.textColor = [HATheme secondaryTextColor];
        }
    }

    // Name
    self.nameLabel.hidden = !showName;
    if (showName) {
        NSString *name = config[@"name"];
        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            name = entity.friendlyName ?: @"?";
        }
        self.nameLabel.text = name;
    }

    // State (with optional attribute override from per-entity config)
    self.stateLabel.hidden = !showState;
    if (showState) {
        if (entity) {
            NSString *displayState;
            NSString *attrOverride = [config[@"attribute"] isKindOfClass:[NSString class]] ? config[@"attribute"] : nil;
            if (attrOverride.length > 0) {
                id attrVal = entity.attributes[attrOverride];
                displayState = (attrVal && attrVal != [NSNull null]) ? [NSString stringWithFormat:@"%@", attrVal] : @"—";
            } else {
                NSString *formattedState = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:1];
                displayState = [HAEntityDisplayHelper humanReadableState:formattedState];
                NSString *unit = entity.unitOfMeasurement;
                if (unit.length > 0 && ![[entity domain] isEqualToString:@"binary_sensor"]) {
                    displayState = [NSString stringWithFormat:@"%@ %@", displayState, unit];
                }
            }
            self.stateLabel.text = displayState;
        } else {
            self.stateLabel.text = @"Unavailable";
        }
    }

    // Dim unavailable entities
    self.alpha = (entity && entity.isAvailable) ? 1.0 : 0.4;
}

+ (CGFloat)preferredHeightShowingName:(BOOL)showName showState:(BOOL)showState showIcon:(BOOL)showIcon {
    CGFloat height = kVerticalPadding * 2;
    NSInteger items = 0;
    if (showIcon)  { height += kIconSize;     items++; }
    if (showName)  { height += kNameFontSize + 2; items++; }  // font size + line height padding
    if (showState) { height += kStateFontSize + 2; items++; }
    if (items > 1) height += (items - 1) * kVerticalSpacing;
    return height;
}

@end
