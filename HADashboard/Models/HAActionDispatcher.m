#import "HAActionDispatcher.h"
#import "HAStrings.h"
#import "HAAction.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HAHaptics.h"

NSString *const HAActionNavigateNotification = @"HAActionNavigateNotification";

@interface HAActionDispatcher ()
- (void)showConfirmationForAction:(HAAction *)action forEntity:(HAEntity *)entity fromViewController:(UIViewController *)vc;
- (void)doExecuteAction:(HAAction *)action forEntity:(HAEntity *)entity fromViewController:(UIViewController *)vc;
@end

@implementation HAActionDispatcher

+ (instancetype)sharedDispatcher {
    static HAActionDispatcher *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HAActionDispatcher alloc] init];
    });
    return instance;
}

- (void)executeAction:(HAAction *)action
            forEntity:(HAEntity *)entity
  fromViewController:(UIViewController *)vc {
    if (!action || [action isNone]) return;

    // Confirmation dialog: show before executing
    if (action.confirmation) {
        [self showConfirmationForAction:action forEntity:entity fromViewController:vc];
        return;
    }

    [self doExecuteAction:action forEntity:entity fromViewController:vc];
}

#pragma mark - Confirmation

- (void)showConfirmationForAction:(HAAction *)action
                        forEntity:(HAEntity *)entity
               fromViewController:(UIViewController *)vc {
    NSString *message = nil;
    if ([action.confirmation isKindOfClass:[NSDictionary class]]) {
        message = ((NSDictionary *)action.confirmation)[@"text"];
    }
    if (!message) {
        message = HALocalizedString(@"alert.confirm_action.default_message", @"Fallback confirmation alert message for a Lovelace tap-action confirmation dialog that specifies no custom text.");
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:HALocalizedString(@"action.cancel", @"Cancel button in alerts and action sheets throughout Settings.")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak typeof(self) weakSelf = self;
    HAAction *confirmedAction = [[HAAction alloc] init];
    confirmedAction.action = action.action;
    confirmedAction.navigationPath = action.navigationPath;
    confirmedAction.urlPath = action.urlPath;
    confirmedAction.performAction = action.performAction;
    confirmedAction.data = action.data;
    confirmedAction.target = action.target;
    confirmedAction.entityOverride = action.entityOverride;
    // Don't set confirmation again — prevent infinite loop
    [alert addAction:[UIAlertAction actionWithTitle:HALocalizedString(@"action.confirm", @"Confirm button in a Lovelace tap-action confirmation dialog.")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_) {
        [weakSelf doExecuteAction:confirmedAction forEntity:entity fromViewController:vc];
    }]];

    [vc presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Action Execution

- (void)doExecuteAction:(HAAction *)action
              forEntity:(HAEntity *)entity
     fromViewController:(UIViewController *)vc {
    NSString *type = action.action;

    if ([type isEqualToString:HAActionTypeToggle]) {
        [self executeToggle:entity];
    } else if ([type isEqualToString:HAActionTypeMoreInfo]) {
        [self executeMoreInfo:action entity:entity fromViewController:vc];
    } else if ([type isEqualToString:HAActionTypeNavigate]) {
        [self executeNavigate:action];
    } else if ([type isEqualToString:HAActionTypeURL]) {
        [self executeURL:action];
    } else if ([type isEqualToString:HAActionTypeCallService] ||
               [type isEqualToString:HAActionTypePerformAction]) {
        [self executeServiceCall:action entity:entity];
    }
    // HAActionTypeNone: already handled above
}

- (void)executeToggle:(HAEntity *)entity {
    if (!entity) return;
    NSString *svc = [entity toggleService];
    if (!svc) return;
    [HAHaptics lightImpact];
    [[HAConnectionManager sharedManager] callService:svc
                                            inDomain:[entity domain]
                                            withData:nil
                                            entityId:entity.entityId];
}

- (void)executeMoreInfo:(HAAction *)action
                 entity:(HAEntity *)entity
     fromViewController:(UIViewController *)vc {
    // Use entity override if specified
    HAEntity *targetEntity = entity;
    if (action.entityOverride) {
        HAEntity *override = [[HAConnectionManager sharedManager] entityForId:action.entityOverride];
        if (override) targetEntity = override;
    }
    if (!targetEntity) return;

    // Post notification — the dashboard VC listens and presents the detail sheet.
    // This avoids the dispatcher needing to know about HAEntityDetailViewController.
    [HAHaptics lightImpact];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HAActionMoreInfoNotification"
                                                        object:nil
                                                      userInfo:@{@"entity": targetEntity}];
}

- (void)executeNavigate:(HAAction *)action {
    NSString *path = action.navigationPath;
    if (!path) return;
    [HAHaptics lightImpact];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAActionNavigateNotification
                                                        object:nil
                                                      userInfo:@{@"path": path}];
}

- (void)executeURL:(HAAction *)action {
    NSString *urlString = action.urlPath;
    if (!urlString) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    [HAHaptics lightImpact];
    // iOS 9 compatible — openURL:options:completionHandler: is iOS 10+
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[UIApplication sharedApplication] openURL:url];
#pragma clang diagnostic pop
}

- (void)executeServiceCall:(HAAction *)action entity:(HAEntity *)entity {
    NSString *serviceStr = action.performAction;
    if (!serviceStr) return;

    // Split "domain.service" into domain and service
    NSArray *parts = [serviceStr componentsSeparatedByString:@"."];
    if (parts.count < 2) return;
    NSString *domain = parts[0];
    NSString *service = parts[1];

    // Build service data: merge action.data + action.target
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (action.data) [data addEntriesFromDictionary:action.data];

    // Target can specify entity_id, device_id, area_id
    if (action.target) {
        [data addEntriesFromDictionary:action.target];
    }

    // If no entity specified in target/data and we have a context entity, use it
    if (!data[@"entity_id"] && entity) {
        data[@"entity_id"] = entity.entityId;
    }

    [HAHaptics lightImpact];
    // Use the entity_id from data for the API call, or fall back to context entity
    NSString *entityId = data[@"entity_id"];
    // Remove entity_id from data dict since callService takes it separately
    NSMutableDictionary *serviceData = [data mutableCopy];
    [serviceData removeObjectForKey:@"entity_id"];

    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:domain
                                            withData:serviceData.count > 0 ? serviceData : nil
                                            entityId:entityId];
}

@end
