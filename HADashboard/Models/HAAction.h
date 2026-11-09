#import <Foundation/Foundation.h>

@class HAEntity;

/// Action types matching HA Lovelace action configuration
extern NSString *const HAActionTypeToggle;
extern NSString *const HAActionTypeMoreInfo;
extern NSString *const HAActionTypeCallService;
extern NSString *const HAActionTypePerformAction;
extern NSString *const HAActionTypeNavigate;
extern NSString *const HAActionTypeURL;
extern NSString *const HAActionTypeNone;

/// Represents a configured tap/hold/double-tap action from Lovelace card config.
@interface HAAction : NSObject

@property (nonatomic, copy) NSString *action;         // toggle, more-info, navigate, etc.
@property (nonatomic, copy) NSString *navigationPath;  // for navigate
@property (nonatomic, copy) NSString *urlPath;         // for url
@property (nonatomic, copy) NSString *performAction;   // service name (e.g. light.turn_on)
@property (nonatomic, copy) NSDictionary *data;        // service data
@property (nonatomic, copy) NSDictionary *target;      // service target
@property (nonatomic, copy) NSString *entityOverride;  // override entity for more-info
@property (nonatomic, strong) id confirmation;          // BOOL @YES or NSDictionary with @"text"

/// Parse an action from a Lovelace config dictionary (e.g. card[@"tap_action"]).
/// Returns nil if dict is nil.
+ (instancetype)actionFromDictionary:(NSDictionary *)dict;

/// Default tap action: toggleable entities → toggle, non-toggleable → more-info.
+ (instancetype)defaultTapActionForEntity:(HAEntity *)entity;

/// Default hold action: more-info.
+ (instancetype)defaultHoldAction;

/// Convenience: is this a no-op action?
- (BOOL)isNone;

/// HA hasAction(): YES when `config` is an action dictionary with an "action"
/// string other than "none".
+ (BOOL)configHasAction:(id)config;

@end
