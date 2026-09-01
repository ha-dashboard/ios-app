#import "HADeviceIntegrationManager.h"
#import "HALog.h"
#import "HASensorReporter.h"
#import "HARemoteCommandHandler.h"
#import "HANotificationPresenter.h"
#import "HADeviceRegistration.h"
#import "HAConnectionManager.h"
#import "HACameraRegistrationManager.h"

extern NSString *const HARemoteCommandReloadNotification;

static NSString *const kEnabledKey = @"HADeviceIntegration_enabled";

@interface HADeviceIntegrationManager ()
@property (nonatomic, strong) HASensorReporter *sensorReporter;
@property (nonatomic, strong) HARemoteCommandHandler *commandHandler;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL registering;
@property (nonatomic, assign) BOOL registrationMetadataRefreshInFlight;
@property (nonatomic, assign) BOOL registrationMetadataRefreshComplete;
- (void)refreshRegistrationMetadataIfNeeded;
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
    [[NSUserDefaults standardUserDefaults] synchronize];
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);

    if (enabled && [HAConnectionManager sharedManager].isConnected) {
        [self ensureRegistrationThenStart];
    } else if (!enabled) {
        [[HACameraRegistrationManager sharedManager] cancelRegistration];
        [self stop];
    }
}

#pragma mark - Start / Stop

- (void)start {
    if (self.running) return;
    if (!self.enabled || !self.isRegistered) return;

    self.running = YES;

    [self refreshRegistrationMetadataIfNeeded];

    // Start sensor reporting
    self.sensorReporter = [[HASensorReporter alloc] init];
    [self.sensorReporter registerSensors];
    [self.sensorReporter startReporting];
    HALogI(@"device", @"Sensor reporter started");

    // Start command handler
    self.commandHandler = [[HARemoteCommandHandler alloc] init];
    [self.commandHandler startListening];
    HALogI(@"device", @"Command handler started");

    // Start notification presenter (displays non-command notifications as banners)
    [[HANotificationPresenter sharedPresenter] start];
}

- (void)refreshRegistrationMetadataIfNeeded {
    if (self.registrationMetadataRefreshComplete ||
        self.registrationMetadataRefreshInFlight) return;

    self.registrationMetadataRefreshInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [[HADeviceRegistration sharedManager]
        updateRegistrationMetadataWithCompletion:^(BOOL success, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.registrationMetadataRefreshInFlight = NO;
        if (success) {
            strongSelf.registrationMetadataRefreshComplete = YES;
        } else {
            HALogW(@"device", @"Will retry registration metadata refresh after reconnect: %@",
                   error.localizedDescription ?: @"Unknown error");
        }
    }];
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;

    [self.sensorReporter stopReporting];
    self.sensorReporter = nil;
    [self.commandHandler stopListening];
    self.commandHandler = nil;
    [[HANotificationPresenter sharedPresenter] stop];
    HALogI(@"device", @"Stopped");
}

#pragma mark - Notifications

- (void)connectionDidConnect:(NSNotification *)note {
    if (self.enabled) [self ensureRegistrationThenStart];
}

- (void)ensureRegistrationThenStart {
    if (!self.enabled || ![HAConnectionManager sharedManager].isConnected) return;
    if (self.isRegistered) {
        if (self.running) [self.commandHandler startListening];
        else [self start];
        return;
    }
    if (self.registering) return;
    self.registering = YES;
    [[HADeviceRegistration sharedManager] registerWithCompletion:^(BOOL success, NSError *error) {
        self.registering = NO;
        if (success) {
            [self start];
        } else {
            HALogE(@"device", @"Automatic registration failed: %@", error.localizedDescription);
        }
    }];
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
    HALogI(@"device", @"Reload: stop → disconnect → reconnect → start");
    [self stop];
    HAConnectionManager *cm = [HAConnectionManager sharedManager];
    [cm disconnect];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [cm connect];
        // start will be called by connectionDidConnect: notification
    });
}

@end
