#import "HABottomSheetPresentationController.h"

static const CGFloat kDimAlpha = 0.4;
static const CGFloat kCornerRadius = 14.0;
static const CGFloat kHeightRatio = 0.65; // 65% of container height
static const CGFloat kDismissThreshold = 150.0;
static const CGFloat kDismissVelocity = 800.0;

@interface HABottomSheetPresentationController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, assign) BOOL dismissing;
@end

@implementation HABottomSheetPresentationController

#pragma mark - Presentation

- (BOOL)shouldRemovePresentersView {
    return NO;
}

- (CGRect)frameOfPresentedViewInContainerView {
    CGRect bounds = self.containerView.bounds;
    CGFloat height = floor(bounds.size.height * kHeightRatio);
    return CGRectMake(0, bounds.size.height - height, bounds.size.width, height);
}

- (void)presentationTransitionWillBegin {
    // Dimming view
    self.dimmingView = [[UIView alloc] initWithFrame:self.containerView.bounds];
    self.dimmingView.backgroundColor = [UIColor blackColor];
    self.dimmingView.alpha = 0;
    self.dimmingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerView insertSubview:self.dimmingView atIndex:0];

    // Tap to dismiss
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dimmingViewTapped:)];
    [self.dimmingView addGestureRecognizer:tap];

    // Animate dimming alongside transition
    id<UIViewControllerTransitionCoordinator> coordinator = self.presentedViewController.transitionCoordinator;
    if (coordinator) {
        [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            self.dimmingView.alpha = kDimAlpha;
        } completion:nil];
    } else {
        self.dimmingView.alpha = kDimAlpha;
    }
}

- (void)presentationTransitionDidEnd:(BOOL)completed {
    if (!completed) {
        [self.dimmingView removeFromSuperview];
        self.dimmingView = nil;
        return;
    }

    // Apply corner radius — skip layer.mask on iOS 9-10 as it blocks
    // touch delivery.  Use simple cornerRadius (rounds all 4 corners)
    // as a visual compromise.
    UIView *presented = self.presentedView;
    presented.clipsToBounds = YES;
    if (@available(iOS 11.0, *)) {
        presented.layer.cornerRadius = kCornerRadius;
        presented.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else {
        presented.layer.cornerRadius = kCornerRadius;
        // No layer.mask — it breaks hit testing on iOS 9.
    }

    // Pan-to-dismiss gesture
    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.panGesture.delegate = self;
    [presented addGestureRecognizer:self.panGesture];
}

- (void)dismissalTransitionWillBegin {
    id<UIViewControllerTransitionCoordinator> coordinator = self.presentedViewController.transitionCoordinator;
    if (coordinator) {
        [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            self.dimmingView.alpha = 0;
        } completion:nil];
    } else {
        self.dimmingView.alpha = 0;
    }
}

- (void)dismissalTransitionDidEnd:(BOOL)completed {
    if (completed) {
        [self.dimmingView removeFromSuperview];
        self.dimmingView = nil;

        // iOS 9-10: UIKit may leave the container view (UITransitionView)
        // in the hierarchy after custom-presentation dismissal, blocking
        // all touches to the presenting view controller underneath.
        // Force-remove it so the app is interactive again.
        UIView *container = self.containerView;
        if (container && container.subviews.count == 0) {
            [container removeFromSuperview];
        }
    }
}

- (void)containerViewWillLayoutSubviews {
    [super containerViewWillLayoutSubviews];
    self.presentedView.frame = [self frameOfPresentedViewInContainerView];
    self.dimmingView.frame = self.containerView.bounds;
}

#pragma mark - Tap to Dismiss

- (void)dimmingViewTapped:(UITapGestureRecognizer *)gesture {
    [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Pan to Dismiss

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *presented = self.presentedView;
    CGFloat translation = [gesture translationInView:presented].y;
    CGFloat velocity = [gesture velocityInView:presented].y;

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.dismissing = NO;
            break;

        case UIGestureRecognizerStateChanged: {
            if (translation < 0) translation = 0; // Don't allow dragging upward
            CGRect frame = [self frameOfPresentedViewInContainerView];
            frame.origin.y += translation;
            presented.frame = frame;

            // Fade dimming proportionally
            CGFloat progress = translation / presented.bounds.size.height;
            self.dimmingView.alpha = kDimAlpha * (1.0 - progress);
            break;
        }

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if (translation > kDismissThreshold || velocity > kDismissVelocity) {
                // Dismiss
                self.dismissing = YES;
                [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
            } else {
                // Spring back
                [UIView animateWithDuration:0.3
                                      delay:0
                     usingSpringWithDamping:0.8
                      initialSpringVelocity:0
                                    options:UIViewAnimationOptionCurveEaseOut
                                 animations:^{
                    presented.frame = [self frameOfPresentedViewInContainerView];
                    self.dimmingView.alpha = kDimAlpha;
                } completion:nil];
            }
            break;
        }

        default:
            break;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.panGesture) return YES;

    // Only begin pan-to-dismiss when scroll view is at the top
    UIScrollView *scrollView = self.trackedScrollView;
    if (scrollView) {
        if (scrollView.contentOffset.y > 0) {
            return NO;
        }
    }

    // Only for downward drags
    CGPoint velocity = [gestureRecognizer velocityInView:self.presentedView];
    return velocity.y > 0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // Allow simultaneous recognition with scroll view so we can coordinate
    if (gestureRecognizer == self.panGesture &&
        [otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]) {
        return YES;
    }
    return NO;
}

@end
