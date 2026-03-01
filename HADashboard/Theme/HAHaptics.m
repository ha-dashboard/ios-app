#import "HAHaptics.h"

@implementation HAHaptics

+ (void)lightImpact {
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
    }
#endif
}

+ (void)mediumImpact {
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    }
#endif
}

+ (void)heavyImpact {
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [gen impactOccurred];
    }
#endif
}

+ (void)notifySuccess {
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 10.0, *)) {
        UINotificationFeedbackGenerator *gen = [[UINotificationFeedbackGenerator alloc] init];
        [gen notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
#endif
}

+ (void)selectionChanged {
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 10.0, *)) {
        UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
        [gen selectionChanged];
    }
#endif
}

@end
