#import "HAAction.h"
#import "HAEntity.h"

NSString *const HAActionTypeToggle       = @"toggle";
NSString *const HAActionTypeMoreInfo     = @"more-info";
NSString *const HAActionTypeCallService  = @"call-service";
NSString *const HAActionTypePerformAction = @"perform-action";
NSString *const HAActionTypeNavigate     = @"navigate";
NSString *const HAActionTypeURL          = @"url";
NSString *const HAActionTypeNone         = @"none";

@implementation HAAction

+ (instancetype)actionFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;

    HAAction *action = [[HAAction alloc] init];
    action.action = dict[@"action"];
    if (!action.action) return nil;

    action.navigationPath = dict[@"navigation_path"];
    action.urlPath = dict[@"url_path"];

    // HA supports both "perform_action" (new) and "service" (legacy) keys
    action.performAction = dict[@"perform_action"] ?: dict[@"service"];
    action.data = dict[@"data"] ?: dict[@"service_data"];
    action.target = dict[@"target"];
    action.entityOverride = dict[@"entity"];
    action.confirmation = dict[@"confirmation"];

    return action;
}

/// Domains that support toggle as default tap action, matching HA frontend's DOMAINS_TOGGLE.
+ (BOOL)isToggleDomain:(NSString *)domain {
    static NSSet *toggleDomains;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        toggleDomains = [NSSet setWithArray:@[
            @"automation", @"fan", @"group", @"humidifier",
            @"input_boolean", @"light", @"switch", @"valve"
        ]];
    });
    return [toggleDomains containsObject:domain];
}

+ (instancetype)defaultTapActionForEntity:(HAEntity *)entity {
    HAAction *action = [[HAAction alloc] init];
    NSString *domain = [entity domain];
    if (entity && [self isToggleDomain:domain]) {
        action.action = HAActionTypeToggle;
    } else if ([domain isEqualToString:@"scene"] || [domain isEqualToString:@"script"]
               || [domain isEqualToString:@"button"]) {
        // Actionable entities: activate on tap
        action.action = HAActionTypeToggle;
    } else {
        // Non-toggle entities: tap does nothing. Use long-press for more_info.
        action.action = HAActionTypeNone;
    }
    return action;
}

+ (instancetype)defaultHoldAction {
    HAAction *action = [[HAAction alloc] init];
    action.action = HAActionTypeMoreInfo;
    return action;
}

+ (BOOL)configHasAction:(id)config {
    if (![config isKindOfClass:[NSDictionary class]]) return NO;
    id action = config[@"action"];
    return [action isKindOfClass:[NSString class]] && [action length] > 0 && ![action isEqualToString:HAActionTypeNone];
}

- (BOOL)isNone {
    return [self.action isEqualToString:HAActionTypeNone];
}

@end
