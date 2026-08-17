#import "HAMarkdownCardCell.h"
#import "HADashboardConfig.h"
#import "HATheme.h"

static const CGFloat kPadding = 12.0;
static const CGFloat kTitleHeight = 24.0;

@interface HAMarkdownCardCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *contentLabel;
@property (nonatomic, copy) NSString *markdownContent;
@end

@implementation HAMarkdownCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
        self.contentView.layer.cornerRadius = 12.0;
        self.contentView.clipsToBounds = YES;

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        self.titleLabel.textColor = [HATheme primaryTextColor];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.hidden = YES;
        [self.contentView addSubview:self.titleLabel];

        self.contentLabel = [[UILabel alloc] init];
        self.contentLabel.font = [UIFont systemFontOfSize:13];
        self.contentLabel.textColor = [HATheme primaryTextColor];
        self.contentLabel.numberOfLines = 0;
        self.contentLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.contentLabel];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(themeDidChange:)
                                                     name:HAThemeDidChangeNotification
                                                   object:nil];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kPadding],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],

            [self.contentLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding],
            [self.contentLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding],
            [self.contentLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-kPadding],
        ]];
    }
    return self;
}

- (void)configureWithConfigItem:(HADashboardConfigItem *)configItem {
    NSDictionary *props = configItem.customProperties;

    // Title
    NSString *title = props[@"markdown_title"];
    if ([title isKindOfClass:[NSString class]] && title.length > 0) {
        self.titleLabel.text = title;
        self.titleLabel.hidden = NO;
    } else {
        self.titleLabel.hidden = YES;
    }

    // Content: render markdown as attributed string
    self.markdownContent = props[@"markdown_content"] ?: @"";
    [self refreshMarkdownContent];

    // Top constraint for content depends on title visibility
    // Remove existing top constraint and re-add
    for (NSLayoutConstraint *c in self.contentView.constraints) {
        if (c.firstItem == self.contentLabel && c.firstAttribute == NSLayoutAttributeTop) {
            c.active = NO;
        }
    }
    if (!self.titleLabel.hidden) {
        [self.contentLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6].active = YES;
    } else {
        [self.contentLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kPadding].active = YES;
    }

    // text_only mode: no background/border
    BOOL textOnly = [props[@"text_only"] boolValue];
    if (textOnly) {
        self.contentView.backgroundColor = [UIColor clearColor];
        self.contentView.layer.cornerRadius = 0;
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
        self.contentView.layer.cornerRadius = 12.0;
    }
}

- (void)themeDidChange:(NSNotification *)notification {
    [self refreshMarkdownContent];
    self.titleLabel.textColor = [HATheme primaryTextColor];
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self refreshMarkdownContent];
        }
    }
}

- (void)refreshMarkdownContent {
    self.contentLabel.attributedText = [self attributedStringFromMarkdown:self.markdownContent ?: @""];
}

- (UIColor *)resolvedColorForCurrentTraitCollection:(UIColor *)color {
    if (@available(iOS 13.0, *)) {
        return [color resolvedColorWithTraitCollection:self.traitCollection];
    }
    return color;
}

/// Simple markdown-to-attributed-string conversion.
/// Supports: **bold**, *italic*, `code`, # headings, - lists.
/// Does NOT support Jinja2 templates.
- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown {
    if (!markdown || markdown.length == 0) return [[NSAttributedString alloc] init];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    UIFont *normalFont = [UIFont systemFontOfSize:13];
    UIFont *boldFont = [UIFont boldSystemFontOfSize:13];
    UIFont *codeFont = [UIFont fontWithName:@"Menlo-Regular" size:12] ?: [UIFont systemFontOfSize:12];
    UIFont *headingFont = [UIFont boldSystemFontOfSize:16];
    // NSAttributedString resolves dynamic UIColors when it is created rather
    // than when UILabel draws. Resolve against the cell's current traits and
    // rebuild on appearance changes so dark-mode markdown remains legible.
    UIColor *textColor = [self resolvedColorForCurrentTraitCollection:[HATheme primaryTextColor]];
    UIColor *codeColor = [self resolvedColorForCurrentTraitCollection:[HATheme secondaryTextColor]];

    NSDictionary *normalAttrs = @{NSFontAttributeName: normalFont, NSForegroundColorAttributeName: textColor};
    NSDictionary *boldAttrs = @{NSFontAttributeName: boldFont, NSForegroundColorAttributeName: textColor};
    NSDictionary *codeAttrs = @{NSFontAttributeName: codeFont, NSForegroundColorAttributeName: codeColor};
    NSDictionary *headingAttrs = @{NSFontAttributeName: headingFont, NSForegroundColorAttributeName: textColor};

    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        if (i > 0) [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:normalAttrs]];

        // Heading
        if ([line hasPrefix:@"# "]) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:[line substringFromIndex:2] attributes:headingAttrs]];
            continue;
        }
        if ([line hasPrefix:@"## "]) {
            UIFont *h2 = [UIFont boldSystemFontOfSize:15];
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:[line substringFromIndex:3]
                                                                           attributes:@{NSFontAttributeName: h2, NSForegroundColorAttributeName: textColor}]];
            continue;
        }

        // List items
        if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "]) {
            line = [NSString stringWithFormat:@"\u2022 %@", [line substringFromIndex:2]];
        }

        // Process inline formatting: **bold**, *italic*, `code`
        [self appendFormattedLine:line toResult:result
                      normalAttrs:normalAttrs boldAttrs:boldAttrs codeAttrs:codeAttrs];
    }
    return result;
}

- (void)appendFormattedLine:(NSString *)line
                   toResult:(NSMutableAttributedString *)result
                normalAttrs:(NSDictionary *)normalAttrs
                  boldAttrs:(NSDictionary *)boldAttrs
                  codeAttrs:(NSDictionary *)codeAttrs {
    NSUInteger i = 0;
    NSUInteger len = line.length;

    while (i < len) {
        unichar ch = [line characterAtIndex:i];

        // **bold**
        if (ch == '*' && i + 1 < len && [line characterAtIndex:i + 1] == '*') {
            NSRange end = [line rangeOfString:@"**" options:0 range:NSMakeRange(i + 2, len - i - 2)];
            if (end.location != NSNotFound) {
                NSString *boldText = [line substringWithRange:NSMakeRange(i + 2, end.location - i - 2)];
                [result appendAttributedString:[[NSAttributedString alloc] initWithString:boldText attributes:boldAttrs]];
                i = end.location + 2;
                continue;
            }
        }

        // `code`
        if (ch == '`') {
            NSRange end = [line rangeOfString:@"`" options:0 range:NSMakeRange(i + 1, len - i - 1)];
            if (end.location != NSNotFound) {
                NSString *codeText = [line substringWithRange:NSMakeRange(i + 1, end.location - i - 1)];
                [result appendAttributedString:[[NSAttributedString alloc] initWithString:codeText attributes:codeAttrs]];
                i = end.location + 1;
                continue;
            }
        }

        // Normal character
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&ch length:1] attributes:normalAttrs]];
        i++;
    }
}

+ (CGFloat)preferredHeightForConfigItem:(HADashboardConfigItem *)configItem width:(CGFloat)width {
    NSDictionary *props = configItem.customProperties;
    NSString *content = props[@"markdown_content"] ?: @"";
    BOOL hasTitle = [props[@"markdown_title"] isKindOfClass:[NSString class]] && [props[@"markdown_title"] length] > 0;

    // Measure against the actual card width. A line-count estimate clips
    // ordinary Markdown paragraphs as soon as they wrap on narrower phones.
    CGFloat textWidth = MAX(1, width - (2 * kPadding));
    CGRect textBounds = [content boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                               options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13]}
                                               context:nil];
    CGFloat contentHeight = MAX(20, ceil(textBounds.size.height));
    CGFloat titleExtra = hasTitle ? kTitleHeight + 6 : 0;
    return kPadding + titleExtra + contentHeight + kPadding;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.titleLabel.hidden = YES;
    self.markdownContent = nil;
    self.contentLabel.attributedText = nil;
    self.contentView.layer.cornerRadius = 12.0;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
