#import "HABLEProxyRegistration.h"
#import "HAAPIClient.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "HALog.h"
#import <arpa/inet.h>

static BOOL HABLESetupURLIsProtected(NSURL *URL) {
    if (!URL.host.length) return NO;
    if ([URL.scheme.lowercaseString isEqual:@"https"]) return YES;
    if (![URL.scheme.lowercaseString isEqual:@"http"]) return NO;
    NSString *host = [URL.host.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"[]"]];
    if ([host isEqual:@"localhost"] || [host hasSuffix:@".local"]) return YES;
    struct in_addr ipv4;
    if (inet_pton(AF_INET, host.UTF8String, &ipv4) == 1) {
        uint32_t value = ntohl(ipv4.s_addr);
        return (value & 0xff000000) == 0x0a000000 || (value & 0xfff00000) == 0xac100000 || (value & 0xffff0000) == 0xc0a80000 || (value & 0xff000000) == 0x7f000000 || (value & 0xffff0000) == 0xa9fe0000;
    }
    struct in6_addr ipv6;
    if (inet_pton(AF_INET6, host.UTF8String, &ipv6) == 1) return IN6_IS_ADDR_LOOPBACK(&ipv6) || (ipv6.s6_addr[0] & 0xfe) == 0xfc || (ipv6.s6_addr[0] == 0xfe && (ipv6.s6_addr[1] & 0xc0) == 0x80);
    return NO;
}

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
+ (BOOL)isAdministratorInfo:(id)value { return [value isKindOfClass:[NSDictionary class]] && [value[@"is_admin"] isKindOfClass:[NSNumber class]] && [value[@"is_admin"] boolValue]; }
+ (BOOL)isSetupURLAllowed:(NSURL *)URL { return HABLESetupURLIsProtected(URL); }
+ (BOOL)isSuccessfulExistingEntryReason:(NSString *)reason { return [reason isEqual:@"already_configured"] || [reason isEqual:@"already_configured_updates"]; }
- (instancetype)init { if ((self = [super init])) _status = @"Not registered by this app"; return self; }
- (void)cancel { self.generation++; [self.api cancelAllRequests]; self.api = nil; self.key = nil; self.completion = nil; if (self.registering) self.status = @"Setup paused"; self.registering = NO; }
- (void)registerHost:(NSString *)host key:(NSString *)key completion:(void (^)(BOOL))completion {
    [self cancel]; HAAuthManager *auth = [HAAuthManager sharedManager];
    if (!host.length || !key.length || !auth.isConfigured) { self.status = @"Enable the proxy and connect to Home Assistant first"; completion(NO); return; }
    if (!HABLESetupURLIsProtected([NSURL URLWithString:auth.serverURL])) { self.status = @"Use HTTPS or a private local HA address for encrypted proxy setup"; completion(NO); return; }
    HAConnectionManager *connection = [HAConnectionManager sharedManager];
    if (!connection.connected) { self.status = @"Connect to Home Assistant as an administrator first"; completion(NO); return; }
    self.host = host; self.key = key; self.server = auth.serverURL; self.revision = auth.authenticationRevision; self.steps = 0;
    self.completion = completion; self.registering = YES; self.status = @"Checking Home Assistant administrator access";
    NSUInteger generation = self.generation; __weak typeof(self) weakSelf = self;
    [connection sendCommand:@{@"type":@"auth/current_user"} completion:^(id user, NSError *error) {
        HABLEProxyRegistration *self = weakSelf; if (!self || generation != self.generation) return;
        if (error || ![[self class] isAdministratorInfo:user]) { [self finish:NO status:@"An HA administrator account is required for automatic setup"]; return; }
        HAAuthManager *current = [HAAuthManager sharedManager];
        if (current.authenticationRevision != self.revision || ![current.serverURL isEqual:self.server]) { [self finish:NO status:@"Home Assistant connection changed; try again"]; return; }
        self.status = @"Adding the encrypted proxy to Home Assistant";
        self.api = [[HAAPIClient alloc] initWithBaseURL:[NSURL URLWithString:self.server] token:current.accessToken requestTimeoutInterval:20 resourceTimeoutInterval:30];
        [self post:@"/api/config/config_entries/flow" body:@{@"handler":@"esphome", @"context":@{@"source":@"user"}, @"show_advanced_options":@NO}];
    }];
}
- (void)finish:(BOOL)success status:(NSString *)status {
    self.status = status; self.registering = NO; self.key = nil;
    HALogI(@"bleproxy", @"HA proxy setup %@: %@", success ? @"completed" : @"stopped", status);
    void (^completion)(BOOL) = self.completion; self.completion = nil; if (completion) completion(success);
}
- (void)post:(NSString *)path body:(NSDictionary *)body {
    NSUInteger generation = self.generation;
    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (++self.steps > 5 || auth.authenticationRevision != self.revision || ![auth.serverURL isEqual:self.server]) { [self finish:NO status:@"Home Assistant connection changed; try again"]; return; }
    HALogI(@"bleproxy", @"HA proxy setup request %lu", (unsigned long)self.steps);
    __weak typeof(self) weakSelf = self;
    [self.api postJSONAtPath:path body:body completion:^(id result, NSError *error) {
        HABLEProxyRegistration *self = weakSelf; if (!self || generation != self.generation) return;
        if (error || ![result isKindOfClass:[NSDictionary class]]) { [self finish:NO status:error.localizedDescription ?: @"Home Assistant setup failed"]; return; }
        HAAuthManager *auth = [HAAuthManager sharedManager];
        if (auth.authenticationRevision != self.revision || ![auth.serverURL isEqual:self.server]) { [self finish:NO status:@"Home Assistant connection changed; try again"]; return; }
        NSString *type = result[@"type"], *step = result[@"step_id"];
        if ([type isEqual:@"create_entry"]) { self.entryID = result[@"result"][@"entry_id"]; [self finish:YES status:@"Added to Home Assistant"]; return; }
        if ([type isEqual:@"abort"]) { BOOL exists = [[self class] isSuccessfulExistingEntryReason:result[@"reason"]]; [self finish:exists status:exists ? @"Configured in Home Assistant" : [NSString stringWithFormat:@"Setup stopped: %@", result[@"reason"] ?: @"unknown reason"]]; return; }
        if ([result[@"errors"] isKindOfClass:[NSDictionary class]] && [result[@"errors"] count]) { [self finish:NO status:[NSString stringWithFormat:@"Home Assistant setup: %@", [result[@"errors"] allValues].firstObject]]; return; }
        NSString *flow = result[@"flow_id"];
        if (![flow isKindOfClass:[NSString class]] || ![type isEqual:@"form"]) { [self finish:NO status:@"Complete ESPHome setup in Home Assistant"]; return; }
        NSString *next = [@"/api/config/config_entries/flow/" stringByAppendingString:flow];
        if ([step isEqual:@"user"]) { self.status = @"Verifying the proxy address with Home Assistant"; [self post:next body:@{@"host":self.host, @"port":@6053}]; }
        else if ([step isEqual:@"encryption_key"]) { self.status = @"Completing encrypted proxy setup"; [self post:next body:@{@"noise_psk":self.key}]; }
        else [self finish:NO status:@"Complete the remaining ESPHome setup step in Home Assistant"];
    }];
}
@end
