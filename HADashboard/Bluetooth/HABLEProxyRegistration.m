#import "HABLEProxyRegistration.h"
#import "HAAPIClient.h"
#import "HAAuthManager.h"

@interface HABLEProxyRegistration ()
@property (nonatomic, assign, readwrite) BOOL registering;
@property (nonatomic, copy, readwrite) NSString *status;
@property (nonatomic, copy, readwrite) NSString *entryID;
@property (nonatomic, strong) HAAPIClient *api;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *server;
@property (nonatomic, assign) NSUInteger revision;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) NSUInteger steps;
@property (nonatomic, copy) void (^completion)(BOOL);
@end
@implementation HABLEProxyRegistration
- (instancetype)init { if ((self = [super init])) _status = @"Not registered by this app"; return self; }
- (void)cancel { self.generation++; [self.api cancelAllRequests]; self.api = nil; self.key = nil; self.completion = nil; self.registering = NO; }
- (void)registerHost:(NSString *)host key:(NSString *)key completion:(void (^)(BOOL))completion {
    [self cancel]; HAAuthManager *auth = [HAAuthManager sharedManager];
    if (!host.length || !key.length || !auth.isConfigured) { self.status = @"Enable the proxy and connect to Home Assistant first"; completion(NO); return; }
    self.host = host; self.key = key; self.server = auth.serverURL; self.revision = auth.authenticationRevision; self.steps = 0;
    self.completion = completion; self.registering = YES; self.status = @"Adding the encrypted proxy to Home Assistant";
    self.api = [[HAAPIClient alloc] initWithBaseURL:[NSURL URLWithString:self.server] token:auth.accessToken requestTimeoutInterval:20 resourceTimeoutInterval:30];
    [self post:@"/api/config/config_entries/flow" body:@{@"handler":@"esphome", @"context":@{@"source":@"user"}, @"show_advanced_options":@NO}];
}
- (void)finish:(BOOL)success status:(NSString *)status {
    self.status = status; self.registering = NO; self.key = nil;
    void (^completion)(BOOL) = self.completion; self.completion = nil; if (completion) completion(success);
}
- (void)post:(NSString *)path body:(NSDictionary *)body {
    NSUInteger generation = self.generation;
    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (++self.steps > 5 || auth.authenticationRevision != self.revision || ![auth.serverURL isEqual:self.server]) { [self finish:NO status:@"Home Assistant connection changed; try again"]; return; }
    __weak typeof(self) weakSelf = self;
    [self.api postJSONAtPath:path body:body completion:^(id result, NSError *error) {
        HABLEProxyRegistration *self = weakSelf; if (!self || generation != self.generation) return;
        if (error || ![result isKindOfClass:[NSDictionary class]]) { [self finish:NO status:error.localizedDescription ?: @"Home Assistant setup failed"]; return; }
        HAAuthManager *auth = [HAAuthManager sharedManager];
        if (auth.authenticationRevision != self.revision || ![auth.serverURL isEqual:self.server]) { [self finish:NO status:@"Home Assistant connection changed; try again"]; return; }
        NSString *type = result[@"type"], *step = result[@"step_id"];
        if ([type isEqual:@"create_entry"]) { self.entryID = result[@"result"][@"entry_id"]; [self finish:YES status:@"Added to Home Assistant"]; return; }
        if ([type isEqual:@"abort"]) { BOOL exists = [result[@"reason"] isEqual:@"already_configured"]; [self finish:exists status:exists ? @"Already configured in Home Assistant" : [NSString stringWithFormat:@"Setup stopped: %@", result[@"reason"] ?: @"unknown reason"]]; return; }
        if ([result[@"errors"] isKindOfClass:[NSDictionary class]] && [result[@"errors"] count]) { [self finish:NO status:[NSString stringWithFormat:@"Home Assistant setup: %@", [result[@"errors"] allValues].firstObject]]; return; }
        NSString *flow = result[@"flow_id"];
        if (![flow isKindOfClass:[NSString class]] || ![type isEqual:@"form"]) { [self finish:NO status:@"Complete ESPHome setup in Home Assistant"]; return; }
        NSString *next = [@"/api/config/config_entries/flow/" stringByAppendingString:flow];
        if ([step isEqual:@"user"]) [self post:next body:@{@"host":self.host, @"port":@6053}];
        else if ([step isEqual:@"encryption_key"]) [self post:next body:@{@"noise_psk":self.key}];
        else [self finish:NO status:@"Complete the remaining ESPHome setup step in Home Assistant"];
    }];
}
@end
