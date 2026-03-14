#import "HAAutoLayout.h"
#import "NSString+HACompat.h"
#import "HAMarkdownCardCell.h"
#import "NSString+HACompat.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "UIFont+HACompat.h"

static const CGFloat kPadding = 12.0;
static const CGFloat kTitleHeight = 24.0;

@interface HAMarkdownCardCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *contentLabel;
@end

@implementation HAMarkdownCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
        self.contentView.layer.cornerRadius = 12.0;
        self.contentView.clipsToBounds = YES;

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont ha_systemFontOfSize:14 weight:HAFontWeightSemibold];
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

        HAActivateConstraints(@[
            HACon([self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kPadding]),
            HACon([self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding]),
            HACon([self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding]),

            HACon([self.contentLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kPadding]),
            HACon([self.contentLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kPadding]),
            HACon([self.contentLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-kPadding]),
        ]);
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
    NSString *content = props[@"markdown_content"] ?: @"";
    self.contentLabel.attributedText = [self attributedStringFromMarkdown:content];

    // Top constraint for content depends on title visibility
    // Remove existing top constraint and re-add
    for (NSLayoutConstraint *c in self.contentView.constraints) {
        if (c.firstItem == self.contentLabel && c.firstAttribute == NSLayoutAttributeTop) {
            HASetConstraintActive(c, NO);
        }
    }
    if (!self.titleLabel.hidden) {
        HASetConstraintActive([self.contentLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6], YES);
    } else {
        HASetConstraintActive([self.contentLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kPadding], YES);
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

/// Simple markdown-to-attributed-string conversion.
/// Supports: **bold**, *italic*, `code`, # headings, - lists.
/// Does NOT support Jinja2 templates.
- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown {
    if (!markdown || markdown.length == 0) return [[NSAttributedString alloc] init];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    UIFont *normalFont = [UIFont systemFontOfSize:13];
    UIFont *boldFont = [UIFont boldSystemFontOfSize:13];
    UIFont *codeFont = [UIFont monospacedSystemFontOfSize:12 weight:HAFontWeightRegular];
    UIFont *headingFont = [UIFont boldSystemFontOfSize:16];
    UIColor *textColor = [HATheme primaryTextColor];
    UIColor *codeColor = [HATheme secondaryTextColor];

    NSDictionary *normalAttrs = @{HAFontAttributeName: normalFont, HAForegroundColorAttributeName: textColor};
    NSDictionary *boldAttrs = @{HAFontAttributeName: boldFont, HAForegroundColorAttributeName: textColor};
    NSDictionary *codeAttrs = @{HAFontAttributeName: codeFont, HAForegroundColorAttributeName: codeColor};
    NSDictionary *headingAttrs = @{HAFontAttributeName: headingFont, HAForegroundColorAttributeName: textColor};

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
                                                                           attributes:@{HAFontAttributeName: h2, HAForegroundColorAttributeName: textColor}]];
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

    // Estimate height from content line count
    NSUInteger lineCount = [[content componentsSeparatedByString:@"\n"] count];
    CGFloat contentHeight = MAX(20, lineCount * 18); // ~18pt per line
    CGFloat titleExtra = hasTitle ? kTitleHeight + 6 : 0;
    return kPadding + titleExtra + contentHeight + kPadding;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat labelW = w - kPadding * 2;
        CGFloat y = kPadding;
        if (!self.titleLabel.hidden) {
            self.titleLabel.frame = CGRectMake(kPadding, y, labelW, kTitleHeight);
            y = CGRectGetMaxY(self.titleLabel.frame) + 6;
        }
        CGSize contentSize = [self.contentLabel sizeThatFits:CGSizeMake(labelW, CGFLOAT_MAX)];
        self.contentLabel.frame = CGRectMake(kPadding, y, labelW, contentSize.height);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.titleLabel.hidden = YES;
    self.contentLabel.attributedText = nil;
    self.contentView.layer.cornerRadius = 12.0;
}

@end
