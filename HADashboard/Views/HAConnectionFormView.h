#import <UIKit/UIKit.h>

@class HAConnectionFormView;

@protocol HAConnectionFormDelegate <NSObject>
/// Called when connection succeeds (token validated or OAuth complete).
- (void)connectionFormDidConnect:(HAConnectionFormView *)form;
@end

/// Reusable connection form containing server discovery, URL field,
/// auth mode switching, credential fields, connect button, and status.
/// Used by both HALoginViewController and HASettingsViewController.
@interface HAConnectionFormView : UIView

@property (nonatomic, weak) id<HAConnectionFormDelegate> delegate;

/// Pre-populate fields from stored credentials (if any).
- (void)loadExistingCredentials;

/// Start mDNS server discovery.
- (void)startDiscovery;

/// Stop mDNS server discovery.
- (void)stopDiscovery;

/// Clear all input fields and status.
- (void)clearFields;

@end
