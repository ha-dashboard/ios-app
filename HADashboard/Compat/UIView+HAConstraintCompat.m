#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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
}
