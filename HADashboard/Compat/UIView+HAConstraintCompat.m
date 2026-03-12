#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreText/CoreText.h>
#import "HAIconMapper.h"

/// On iOS 5.x, the entire Auto Layout system is missing: UIView has no
/// addConstraint:, no translatesAutoresizingMaskIntoConstraints, no layout
/// anchors (topAnchor, etc.), and NSLayoutConstraint doesn't exist.
///
/// Rather than guarding 400+ call sites, we dynamically install no-op stubs
/// for ALL missing Auto Layout methods at load time. On iOS 6+ these methods
/// exist natively and we don't touch them.

__attribute__((constructor))
static void HAInstallConstraintStubs(void) {
    Class uiview = [UIView class];

    // UIView constraint methods (iOS 6+)
    if (!class_getInstanceMethod(uiview, @selector(addConstraint:))) {
        class_addMethod(uiview, @selector(addConstraint:),
                        imp_implementationWithBlock(^(id s, id c) {}), "v@:@");
    }
    if (!class_getInstanceMethod(uiview, @selector(addConstraints:))) {
        class_addMethod(uiview, @selector(addConstraints:),
                        imp_implementationWithBlock(^(id s, id c) {}), "v@:@");
    }
    if (!class_getInstanceMethod(uiview, @selector(removeConstraint:))) {
        class_addMethod(uiview, @selector(removeConstraint:),
                        imp_implementationWithBlock(^(id s, id c) {}), "v@:@");
    }
    if (!class_getInstanceMethod(uiview, @selector(removeConstraints:))) {
        class_addMethod(uiview, @selector(removeConstraints:),
                        imp_implementationWithBlock(^(id s, id c) {}), "v@:@");
    }
    if (!class_getInstanceMethod(uiview, @selector(setTranslatesAutoresizingMaskIntoConstraints:))) {
        class_addMethod(uiview, @selector(setTranslatesAutoresizingMaskIntoConstraints:),
                        imp_implementationWithBlock(^(id s, BOOL v) {}), "v@:B");
    }
    if (!class_getInstanceMethod(uiview, @selector(constraints))) {
        class_addMethod(uiview, @selector(constraints),
                        imp_implementationWithBlock(^id(id s) { return @[]; }), "@@:");
    }
    if (!class_getInstanceMethod(uiview, @selector(translatesAutoresizingMaskIntoConstraints))) {
        class_addMethod(uiview, @selector(translatesAutoresizingMaskIntoConstraints),
                        imp_implementationWithBlock(^BOOL(id s) { return YES; }), "B@:");
    }

    // NSLayoutAnchor stubs (iOS 9+) — return a dummy object whose
    // constraintEqualToAnchor: etc. methods return nil
    if (!class_getInstanceMethod(uiview, @selector(topAnchor))) {
        Class dummy = objc_allocateClassPair([NSObject class], "HADummyAnchor", 0);
        if (dummy) {
            IMP nilRet = imp_implementationWithBlock(^id(id s, ...) { return nil; });
            class_addMethod(dummy, @selector(constraintEqualToAnchor:), nilRet, "@@:@");
            class_addMethod(dummy, @selector(constraintEqualToAnchor:constant:), nilRet, "@@:@d");
            class_addMethod(dummy, @selector(constraintGreaterThanOrEqualToAnchor:), nilRet, "@@:@");
            class_addMethod(dummy, @selector(constraintGreaterThanOrEqualToAnchor:constant:), nilRet, "@@:@d");
            class_addMethod(dummy, @selector(constraintLessThanOrEqualToAnchor:), nilRet, "@@:@");
            class_addMethod(dummy, @selector(constraintLessThanOrEqualToAnchor:constant:), nilRet, "@@:@d");
            class_addMethod(dummy, @selector(constraintEqualToConstant:), nilRet, "@@:d");
            objc_registerClassPair(dummy);

            __block id shared = [[dummy alloc] init];
            IMP anchorGetter = imp_implementationWithBlock(^id(id s) { return shared; });
            SEL anchors[] = {
                @selector(topAnchor), @selector(bottomAnchor),
                @selector(leadingAnchor), @selector(trailingAnchor),
                @selector(leftAnchor), @selector(rightAnchor),
                @selector(widthAnchor), @selector(heightAnchor),
                @selector(centerXAnchor), @selector(centerYAnchor),
                @selector(firstBaselineAnchor), @selector(lastBaselineAnchor),
            };
            for (int i = 0; i < 12; i++) {
                class_addMethod(uiview, anchors[i], anchorGetter, "@@:");
            }
        }
    }

    // NSLayoutConstraint: do NOT create a dummy class. On iOS 5,
    // NSClassFromString(@"NSLayoutConstraint") returns nil, which makes
    // HAAutoLayoutAvailable() return NO, skipping all guarded constraint code.
    // Messages sent to the nil class (e.g. [NSLayoutConstraint activateConstraints:])
    // are safe no-ops in ObjC. Creating a dummy class would make
    // HAAutoLayoutAvailable() return YES, causing the guarded code to execute
    // with nil constraints from our dummy anchors — crashing in @[nil, ...] arrays.

    // UIViewController layout guide stubs (iOS 7+)
    Class uivc = [UIViewController class];
    if (!class_getInstanceMethod(uivc, @selector(topLayoutGuide))) {
        // Return nil — anchor calls on nil return nil (safe)
        IMP nilGuide = imp_implementationWithBlock(^id(id s) { return nil; });
        class_addMethod(uivc, @selector(topLayoutGuide), nilGuide, "@@:");
        class_addMethod(uivc, @selector(bottomLayoutGuide), nilGuide, "@@:");
    }

    // UIView safeAreaLayoutGuide stub (iOS 11+)
    if (!class_getInstanceMethod(uiview, @selector(safeAreaLayoutGuide))) {
        IMP selfReturn = imp_implementationWithBlock(^id(id s) { return s; });
        class_addMethod(uiview, @selector(safeAreaLayoutGuide), selfReturn, "@@:");
    }

    // UIView tintColor (iOS 7+) — cosmetic property, no-op on iOS 5-6
    if (!class_getInstanceMethod(uiview, @selector(setTintColor:))) {
        class_addMethod(uiview, @selector(setTintColor:),
                        imp_implementationWithBlock(^(id s, id c) {}), "v@:@");
    }
    if (!class_getInstanceMethod(uiview, @selector(tintColor))) {
        class_addMethod(uiview, @selector(tintColor),
                        imp_implementationWithBlock(^id(id s) { return nil; }), "@@:");
    }

    // UIImage imageWithRenderingMode: (iOS 7+) — return self on iOS 5-6
    Class uiimage = [UIImage class];
    if (!class_getInstanceMethod(uiimage, @selector(imageWithRenderingMode:))) {
        class_addMethod(uiimage, @selector(imageWithRenderingMode:),
                        imp_implementationWithBlock(^id(id s, NSInteger mode) { return s; }), "@@:l");
    }

    // UIStatusBarStyleLightContent is enum value 1 — no runtime stub needed (compiled as integer)

    // UINavigationBar barTintColor (iOS 7+) — already guarded with respondsToSelector:
    // UIBarButtonItem tintColor follows UIView tintColor stub above

    // UILabel attributedText (iOS 6+) — fall back to plain text on iOS 5
    Class uilabel = [UILabel class];
    if (!class_getInstanceMethod(uilabel, @selector(setAttributedText:))) {
        class_addMethod(uilabel, @selector(setAttributedText:),
                        imp_implementationWithBlock(^(UILabel *s, NSAttributedString *attr) {
                            s.text = [attr string];
                        }), "v@:@");
    }
    if (!class_getInstanceMethod(uilabel, @selector(attributedText))) {
        class_addMethod(uilabel, @selector(attributedText),
                        imp_implementationWithBlock(^id(id s) { return nil; }), "@@:");
    }

    // UIView content priority methods (iOS 6+) — no-op on iOS 5
    if (!class_getInstanceMethod(uiview, @selector(setContentHuggingPriority:forAxis:))) {
        class_addMethod(uiview, @selector(setContentHuggingPriority:forAxis:),
                        imp_implementationWithBlock(^(id s, float p, NSInteger a) {}), "v@:fi");
    }
    if (!class_getInstanceMethod(uiview, @selector(setContentCompressionResistancePriority:forAxis:))) {
        class_addMethod(uiview, @selector(setContentCompressionResistancePriority:forAxis:),
                        imp_implementationWithBlock(^(id s, float p, NSInteger a) {}), "v@:fi");
    }

    // UITextView attributedText (iOS 6+)
    Class uitextview = [UITextView class];
    if (!class_getInstanceMethod(uitextview, @selector(setAttributedText:))) {
        class_addMethod(uitextview, @selector(setAttributedText:),
                        imp_implementationWithBlock(^(UITextView *s, NSAttributedString *attr) {
                            s.text = [attr string];
                        }), "v@:@");
    }

    // UIButton setAttributedTitle:forState: (iOS 6+) — fall back to plain title on iOS 5
    Class uibutton = [UIButton class];
    if (!class_getInstanceMethod(uibutton, @selector(setAttributedTitle:forState:))) {
        class_addMethod(uibutton, @selector(setAttributedTitle:forState:),
                        imp_implementationWithBlock(^(UIButton *s, NSAttributedString *title, NSUInteger state) {
                            [s setTitle:[title string] forState:state];
                        }), "v@:@I");
    }

    // UIViewController shouldAutorotateToInterfaceOrientation: (iOS 5 rotation API)
    // On iOS 5, the default returns YES only for portrait. Override on both
    // UIViewController AND UINavigationController (which has its own override
    // that queries topViewController — but if called before topVC exists, it
    // falls back to its own default which is portrait-only).
    if (!class_getInstanceMethod([UIViewController class], @selector(supportedInterfaceOrientations))) {
        IMP allOrientations = imp_implementationWithBlock(^BOOL(id self, NSInteger orientation) {
            return YES;
        });
        SEL rotSel = @selector(shouldAutorotateToInterfaceOrientation:);

        // Replace on UIViewController base class
        Method vcMethod = class_getInstanceMethod([UIViewController class], rotSel);
        if (vcMethod) method_setImplementation(vcMethod, allOrientations);

        // Replace on UINavigationController (has its own override)
        Method navMethod = class_getInstanceMethod([UINavigationController class], rotSel);
        if (navMethod) method_setImplementation(navMethod, allOrientations);

        // Replace on UITabBarController if used
        Method tabMethod = class_getInstanceMethod([UITabBarController class], rotSel);
        if (tabMethod) method_setImplementation(tabMethod, allOrientations);
    }

    // UIColor system colors (iOS 7+) — provide sensible defaults on iOS 5-6
    Class uicolor = objc_getMetaClass("UIColor");
    struct { SEL sel; CGFloat r, g, b, a; } colorStubs[] = {
        { @selector(systemBlueColor),   0.0, 0.478, 1.0, 1.0 },
        { @selector(systemRedColor),    1.0, 0.231, 0.188, 1.0 },
        { @selector(systemGreenColor),  0.298, 0.851, 0.392, 1.0 },
        { @selector(systemOrangeColor), 1.0, 0.584, 0.0, 1.0 },
        { @selector(systemYellowColor), 1.0, 0.8, 0.0, 1.0 },
        { @selector(systemGray2Color),  0.682, 0.682, 0.698, 1.0 },
        { @selector(systemGray3Color),  0.78, 0.78, 0.8, 1.0 },
        { @selector(systemGray4Color),  0.82, 0.82, 0.84, 1.0 },
    };
    for (int i = 0; i < (int)(sizeof(colorStubs)/sizeof(colorStubs[0])); i++) {
        if (!class_getClassMethod([UIColor class], colorStubs[i].sel)) {
            CGFloat r = colorStubs[i].r, g = colorStubs[i].g;
            CGFloat b = colorStubs[i].b, a = colorStubs[i].a;
            class_addMethod(uicolor, colorStubs[i].sel,
                            imp_implementationWithBlock(^id(id cls) {
                                return [UIColor colorWithRed:r green:g blue:b alpha:a];
                            }), "@@:");
        }
    }

    // ── UILabel drawTextInRect: swizzle for MDI icon rendering on iOS 5 ──
    // iOS 5's text engine can't render Supplementary Private Use Area codepoints
    // (U+F0000+) used by Material Design Icons. Instead of checking at every call
    // site, swizzle drawTextInRect: to detect MDI font + SMP text and render via
    // CoreText automatically. On iOS 6+ this swizzle is not installed.
    if ([[UIDevice currentDevice].systemVersion integerValue] < 6) {
        Class labelClass = [UILabel class];
        SEL drawSel = @selector(drawTextInRect:);
        Method origMethod = class_getInstanceMethod(labelClass, drawSel);
        if (origMethod) {
            typedef void (*DrawIMP)(id, SEL, CGRect);
            __block DrawIMP origDraw = (DrawIMP)method_getImplementation(origMethod);

            IMP newIMP = imp_implementationWithBlock(^(UILabel *self, CGRect rect) {
                // Check if this label uses the MDI font and has SMP text (surrogate pairs)
                NSString *mdiFontName = [HAIconMapper mdiFontName];
                NSString *text = self.text;
                BOOL isMDI = (mdiFontName && text.length > 0 &&
                              [self.font.fontName isEqualToString:mdiFontName]);

                if (!isMDI || text.length == 0) {
                    origDraw(self, drawSel, rect);
                    return;
                }

                // Check for surrogate pairs (SMP codepoints)
                BOOL hasSurrogates = NO;
                for (NSUInteger i = 0; i < text.length; i++) {
                    unichar c = [text characterAtIndex:i];
                    if (CFStringIsSurrogateHighCharacter(c)) { hasSurrogates = YES; break; }
                }

                if (!hasSurrogates) {
                    origDraw(self, drawSel, rect);
                    return;
                }

                // Render via CoreText
                CGContextRef ctx = UIGraphicsGetCurrentContext();
                if (!ctx) return;

                CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)mdiFontName,
                                                         self.font.pointSize, NULL);
                if (!ctFont) { origDraw(self, drawSel, rect); return; }

                // Get glyphs from the text
                UniChar chars[4];
                NSInteger charCount = MIN(text.length, 4);
                [text getCharacters:chars range:NSMakeRange(0, charCount)];

                CGGlyph glyphs[4] = {0};
                if (!CTFontGetGlyphsForCharacters(ctFont, chars, glyphs, charCount)) {
                    CFRelease(ctFont);
                    origDraw(self, drawSel, rect);
                    return;
                }

                // Get glyph metrics for centering
                CGRect bbox = CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationDefault,
                                                               glyphs, NULL, 1);

                // Flip context for CoreText
                CGContextSaveGState(ctx);
                CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
                CGContextTranslateCTM(ctx, 0, rect.size.height);
                CGContextScaleCTM(ctx, 1.0, -1.0);

                // Center glyph in rect, respecting text alignment
                CGFloat dx, dy;
                if (self.textAlignment == NSTextAlignmentCenter) {
                    dx = (rect.size.width - bbox.size.width) / 2.0 - bbox.origin.x;
                } else if (self.textAlignment == NSTextAlignmentRight) {
                    dx = rect.size.width - bbox.size.width - bbox.origin.x;
                } else {
                    dx = -bbox.origin.x;
                }
                dy = (rect.size.height - bbox.size.height) / 2.0 - bbox.origin.y;

                CGContextSetFillColorWithColor(ctx, self.textColor.CGColor);
                CGPoint position = CGPointMake(dx, dy);
                CTFontDrawGlyphs(ctFont, glyphs, &position, 1, ctx);

                CGContextRestoreGState(ctx);
                CFRelease(ctFont);
            });

            method_setImplementation(origMethod, newIMP);
        }
    }
}
