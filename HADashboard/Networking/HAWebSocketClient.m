#import "HAWebSocketClient.h"
#import "HALog.h"
#import "HAAuthManager.h"
#import "SRWebSocket.h"

@interface HAWebSocketClient () <SRWebSocketDelegate>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy)   NSString *token;
@property (nonatomic, strong) SRWebSocket *socket;
@property (nonatomic, assign) NSInteger nextMessageId;
@property (atomic, assign, readwrite, getter=isConnected) BOOL connected;
@property (atomic, assign, readwrite, getter=isAuthenticated) BOOL authenticated;
@end

@implementation HAWebSocketClient

- (instancetype)initWithURL:(NSURL *)url token:(NSString *)token {
    self = [super init];
    if (self) {
        _url   = url;
        _token = [token copy];
        _nextMessageId = 1;
    }
    return self;
}

- (void)dealloc {
    [self disconnect];
}

#pragma mark - Connection

- (void)connect {
    if (self.socket) {
        [self disconnect];
    }

    self.connected = NO;
    self.authenticated = NO;
    self.nextMessageId = 1;

    self.socket = [[SRWebSocket alloc] initWithURL:self.url];
    self.socket.delegate = self;
    [self.socket open];
}

- (void)disconnect {
    self.socket.delegate = nil;
    [self.socket close];
    self.socket = nil;
    self.connected = NO;
    self.authenticated = NO;
}

#pragma mark - Commands

- (NSInteger)subscribeToStateChanges {
    NSDictionary *command = @{
        @"type": @"subscribe_events",
        @"event_type": @"state_changed",
    };
    return [self sendCommand:command];
}

- (NSInteger)subscribeToLovelaceUpdates {
    NSDictionary *command = @{
        @"type": @"subscribe_events",
        @"event_type": @"lovelace_updated",
    };
    return [self sendCommand:command];
}

- (NSInteger)callService:(NSString *)service
                inDomain:(NSString *)domain
                withData:(NSDictionary *)data {
    NSMutableDictionary *command = [NSMutableDictionary dictionary];
    command[@"type"]    = @"call_service";
    command[@"domain"]  = domain;
    command[@"service"] = service;
    if (data) {
        command[@"service_data"] = data;
    }
    return [self sendCommand:command];
}

- (NSInteger)fetchDashboardList {
    return [self sendCommand:@{@"type": @"get_panels"}];
}

- (NSInteger)fetchLovelaceConfig {
    return [self fetchLovelaceConfigForDashboard:nil];
}

- (NSInteger)fetchLovelaceConfigForDashboard:(NSString *)urlPath {
    NSMutableDictionary *command = [NSMutableDictionary dictionary];
    command[@"type"] = @"lovelace/config";
    if (urlPath.length > 0) {
        command[@"url_path"] = urlPath;
    }
    return [self sendCommand:command];
}

- (NSInteger)fetchAreaRegistry {
    return [self sendCommand:@{@"type": @"config/area_registry/list"}];
}

- (NSInteger)fetchEntityRegistry {
    return [self sendCommand:@{@"type": @"config/entity_registry/list"}];
}

- (NSInteger)fetchDeviceRegistry {
    return [self sendCommand:@{@"type": @"config/device_registry/list"}];
}

- (NSInteger)sendCommand:(NSDictionary *)command {
    if (!self.authenticated) {
        HALogW(@"conn", @"Cannot send command — not authenticated");
        return -1;
    }

    NSInteger msgId = self.nextMessageId++;
    NSMutableDictionary *msg = [command mutableCopy];
    msg[@"id"] = @(msgId);

    [self sendJSON:msg];
    return msgId;
}

#pragma mark - Internal

- (void)sendJSON:(NSDictionary *)dict {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    if (error) {
        HALogE(@"conn", @"JSON serialization error: %@", error);
        return;
    }

    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self.socket send:string];
}

- (void)handleMessage:(NSDictionary *)message {
    NSString *type = message[@"type"];

    if ([type isEqualToString:@"auth_required"]) {
        // Server wants authentication — send our token
        [self sendJSON:@{
            @"type": @"auth",
            @"access_token": self.token,
        }];
        return;
    }

    if ([type isEqualToString:@"auth_ok"]) {
        self.authenticated = YES;
        NSString *haVersion = message[@"ha_version"];
        if (haVersion) {
            HALogI(@"conn", @"Home Assistant version: %@", haVersion);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webSocketClientDidAuthenticate:self];
        });
        return;
    }

    if ([type isEqualToString:@"auth_invalid"]) {
        HALogW(@"conn", @"auth_invalid — attempting token refresh");
        [self disconnect];
        [[HAAuthManager sharedManager] handleAuthFailureWithCompletion:^(NSString *newToken, NSError *refreshError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (newToken) {
                    HALogI(@"conn", @"Token refreshed, reconnecting");
                    self.token = newToken;
                    [self connect];
                } else {
                    HALogE(@"conn", @"Auth failed: %@", refreshError.localizedDescription);
                    [self.delegate webSocketClient:self didDisconnectWithError:refreshError];
                }
            });
        }];
        return;
    }

    // Forward all other messages (event, result, etc.) to delegate
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate webSocketClient:self didReceiveMessage:message];
    });
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    self.connected = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate webSocketClientDidConnect:self];
    });
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    NSData *data = nil;
    if ([message isKindOfClass:[NSString class]]) {
        data = [(NSString *)message dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([message isKindOfClass:[NSData class]]) {
        data = (NSData *)message;
    }

    if (!data) return;

    NSError *error = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![dict isKindOfClass:[NSDictionary class]]) {
        HALogE(@"conn", @"Failed to parse message: %@", error);
        return;
    }

    [self handleMessage:dict];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    self.connected = NO;
    self.authenticated = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate webSocketClient:self didDisconnectWithError:error];
    });
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason wasClean:(BOOL)wasClean {
    self.connected = NO;
    self.authenticated = NO;

    NSError *error = nil;
    if (!wasClean) {
        NSString *msg = reason ?: [NSString stringWithFormat:@"WebSocket closed with code %ld", (long)code];
        error = [NSError errorWithDomain:@"HAWebSocket" code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate webSocketClient:self didDisconnectWithError:error];
    });
}

- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload {
    // Connection alive
}

@end
