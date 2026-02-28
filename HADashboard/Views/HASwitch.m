#import "HASwitch.h"
#import "HATheme.h"

@implementation HASwitch

- (instancetype)init {
    self = [super init];
    if (self) [self ha_commonInit];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self ha_commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self ha_commonInit];
    return self;
}

- (void)ha_commonInit {
    self.onTintColor = [HATheme switchTintColor];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(themeDidChange:)
        name:HAThemeDidChangeNotification object:nil];
}

- (void)themeDidChange:(NSNotification *)notification {
    self.onTintColor = [HATheme switchTintColor];
}

/// Re-apply tint when the switch is added to a window, ensuring it picks up
/// the current theme even if created before preferences were fully loaded.
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        self.onTintColor = [HATheme switchTintColor];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
