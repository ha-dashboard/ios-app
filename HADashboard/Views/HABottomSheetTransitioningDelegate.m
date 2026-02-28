#import "HABottomSheetTransitioningDelegate.h"
#import "HABottomSheetPresentationController.h"

// ── Animation Controllers ────────────────────────────────────────────
// Required on iOS 9-10: without these, UIModalPresentationCustom
// transitions silently fail (dismiss does nothing, present may glitch).
// iOS 11+ works without them but they're harmless to provide.

@interface HABottomSheetPresentAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@end

@implementation HABottomSheetPresentAnimator

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)ctx {
    return 0.35;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)ctx {
    UIView *toView = [ctx viewForKey:UITransitionContextToViewKey];
    UIView *container = [ctx containerView];

    // Final frame comes from the presentation controller
    CGRect finalFrame = [ctx finalFrameForViewController:[ctx viewControllerForKey:UITransitionContextToViewControllerKey]];
    toView.frame = CGRectMake(finalFrame.origin.x,
                              container.bounds.size.height,
                              finalFrame.size.width,
                              finalFrame.size.height);
    [container addSubview:toView];

    [UIView animateWithDuration:[self transitionDuration:ctx]
                          delay:0
         usingSpringWithDamping:0.9
          initialSpringVelocity:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        toView.frame = finalFrame;
    } completion:^(BOOL finished) {
        [ctx completeTransition:![ctx transitionWasCancelled]];
    }];
}

@end

@interface HABottomSheetDismissAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@end

@implementation HABottomSheetDismissAnimator

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)ctx {
    return 0.25;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)ctx {
    UIView *fromView = [ctx viewForKey:UITransitionContextFromViewKey];
    UIView *containerView = [ctx containerView];

    // Find the dimming view (inserted at index 0 by the presentation controller)
    UIView *dimmingView = containerView.subviews.firstObject;
    if (dimmingView == fromView) dimmingView = nil; // safety

    [UIView animateWithDuration:[self transitionDuration:ctx]
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        fromView.frame = CGRectMake(0, containerView.bounds.size.height,
                                    fromView.frame.size.width,
                                    fromView.frame.size.height);
        dimmingView.alpha = 0;
    } completion:^(BOOL finished) {
        [fromView removeFromSuperview];
        [dimmingView removeFromSuperview];
        BOOL cancelled = [ctx transitionWasCancelled];
        [ctx completeTransition:!cancelled];

        // iOS 9-10: UIKit leaves the container view (UITransitionView) in
        // the hierarchy after custom-presentation dismissal, blocking all
        // touches to the presenting VC.  Force-remove it.
        if (!cancelled) {
            [containerView removeFromSuperview];
        }
    }];
}

@end

// ── Transitioning Delegate ───────────────────────────────────────────

@implementation HABottomSheetTransitioningDelegate

- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented
                                                      presentingViewController:(UIViewController *)presenting
                                                          sourceViewController:(UIViewController *)source {
    return [[HABottomSheetPresentationController alloc] initWithPresentedViewController:presented
                                                              presentingViewController:presenting];
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source {
    return [[HABottomSheetPresentAnimator alloc] init];
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return [[HABottomSheetDismissAnimator alloc] init];
}

@end
