#import "HAUnsupportedCardCell.h"
#import "HAStrings.h"
#import "HADashboardConfig.h"
#import "HALovelaceParser.h"
#import "HATheme.h"

@implementation HAUnsupportedCardCell

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    // There is never an entity for an unsupported card. Routing through the
    // base implementation with entity:nil gives us heading-icon support
    // (CLAUDE.md: grids-with-headings) and theme-consistent colors for free;
    // we then replace its generic "missing entity" copy with our own.
    [super configureWithEntity:nil configItem:configItem];

    NSString *cardType = configItem.customProperties[HAUnsupportedCardTypeKey];
    if (cardType.length == 0) cardType = @"unknown";

    self.nameLabel.text = HALocalizedString(@"card.unsupported.title",
        @"Title shown on a placeholder for a Lovelace card type the app cannot render.");
    self.stateLabel.text = cardType;

    // Subtle, theme-consistent styling: tertiary text on the normal card
    // background, fully legible (not dimmed) so the type string is readable.
    self.nameLabel.textColor = [HATheme tertiaryTextColor];
    self.stateLabel.textColor = [HATheme tertiaryTextColor];
    self.stateLabel.font = [UIFont systemFontOfSize:12];
    self.contentView.alpha = 1.0;

    self.accessibilityLabel = [NSString stringWithFormat:
        HALocalizedString(@"card.unsupported.accessibilityFormat",
            @"VoiceOver label for an unsupported-card placeholder. %1$@ is the raw Lovelace card type, e.g. custom:bubble-card."),
        cardType];
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.nameLabel.textColor = [HATheme tertiaryTextColor];
    self.stateLabel.textColor = [HATheme tertiaryTextColor];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.accessibilityLabel = nil;
}

@end
