#import "HADeviceIntegrationManager.h"
#import "HASensorReporter.h"
#import "HARemoteCommandHandler.h"
#import "HADeviceRegistration.h"
#import "HAConnectionManager.h"

extern NSString *const HARemoteCommandReloadNotification;

static NSString *const kEnabledKey = @"HADeviceIntegration_enabled";

@interface HADeviceIntegrationManager ()
@property (nonatomic, strong) HASensorReporter *sensorReporter;
@property (nonatomic, strong) HARemoteCommandHandler *commandHandler;
@property (nonatomic, assign) BOOL running;
@end

@implementation HADeviceIntegrationManager

+ (instancetype)sharedManager {
    static HADeviceIntegrationManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HADeviceIntegrationManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnabledKey];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(connectionDidConnect:)
                   name:HAConnectionManagerDidConnectNotification object:nil];
        [nc addObserver:self selector:@selector(connectionDidDisconnect:)
                   name:HAConnectionManagerDidDisconnectNotification object:nil];
        [nc addObserver:self selector:@selector(registrationDidComplete:)
                   name:HADeviceRegistrationDidCompleteNotification object:nil];
        [nc addObserver:self selector:@selector(reloadRequested:)
                   name:HARemoteCommandReloadNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Properties

- (BOOL)isRegistered {
    return [HADeviceRegistration sharedManager].isRegistered;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kEnabledKey];

    if (enabled && self.isRegistered && [HAConnectionManager sharedManager].isConnected) {
        [self start];
    } else if (!enabled) {
        [self stop];
    }
}

#pragma mark - Start / Stop

- (void)start {
    if (self.running) return;
    if (!self.enabled || !self.isRegistered) return;

    self.running = YES;

    // Start sensor reporting
    self.sensorReporter = [[HASensorReporter alloc] init];
    [self.sensorReporter registerSensors];
    [self.sensorReporter startReporting];
    NSLog(@"[HADeviceIntegration] Sensor reporter started");

    // Start command handler
    self.commandHandler = [[HARemoteCommandHandler alloc] init];
    [self.commandHandler startListening];
    NSLog(@"[HADeviceIntegration] Command handler started");
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;

    [self.sensorReporter stopReporting];
    self.sensorReporter = nil;
    [self.commandHandler stopListening];
    self.commandHandler = nil;
    NSLog(@"[HADeviceIntegration] Stopped");
}

#pragma mark - Notifications

- (void)connectionDidConnect:(NSNotification *)note {
    if (self.enabled && self.isRegistered) {
        [self start];
    }
}

- (void)connectionDidDisconnect:(NSNotification *)note {
    [self stop];
}

- (void)registrationDidComplete:(NSNotification *)note {
    // Device just registered — start if connected and enabled
    if (self.enabled && [HAConnectionManager sharedManager].isConnected) {
        [self start];
    }
}

- (void)reloadRequested:(NSNotification *)note {
    NSLog(@"[HADeviceIntegration] Reload: stop → disconnect → reconnect → start");
    [self stop];
    HAConnectionManager *cm = [HAConnectionManager sharedManager];
    [cm disconnect];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [cm connect];
        // start will be called by connectionDidConnect: notification
    });
}

@end
