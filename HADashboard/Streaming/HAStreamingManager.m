#import "HAStreamingManager.h"
#import "HARTSPServer.h"
#import "HAAACEncoder.h"
#import "HARTSPCredentialManager.h"
#import "HAAuthManager.h"
#import "HACameraRegistrationManager.h"
#import "HADeviceIntegrationManager.h"
#import "HADeviceRegistration.h"
#import "HALog.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <VideoToolbox/VideoToolbox.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <math.h>

NSString *const HAStreamingManagerStateDidChangeNotification = @"HAStreamingManagerStateDidChangeNotification";
NSString *const HAStreamingManagerErrorKey = @"HAStreamingManagerErrorKey";

static NSString *const kHAStreamingEnabledKey = @"ha_local_camera_stream_enabled";
static NSString *const kHAStreamingCameraModeKey = @"ha_local_camera_stream_mode";
static NSString *const kHAStreamingQualityScaleKey = @"ha_local_camera_stream_quality_scale";
static NSString *const kHAStreamingLegacyQualityPresetKey = @"ha_local_camera_stream_quality";
static NSString *const kHAStreamingLegacyRearCameraKey = @"ha_local_camera_stream_rear";
static NSString *const HAStreamingManagerErrorDomain = @"HAStreamingManagerErrorDomain";
static char HAStreamingAudioCaptureQueueKey;

@interface HAStreamingQualityProfile : NSObject
@property (nonatomic, strong) AVCaptureDeviceFormat *format;
@property (nonatomic, assign) CMVideoDimensions dimensions;
@property (nonatomic, assign) NSInteger frameRate;
@property (nonatomic, assign) NSInteger bitRate;
@end

@implementation HAStreamingQualityProfile
@end

@interface HAStreamingManager () <AVCaptureVideoDataOutputSampleBufferDelegate,
                                  AVCaptureAudioDataOutputSampleBufferDelegate,
                                  HARTSPServerDelegate>
@property (nonatomic, assign, readwrite) BOOL featureEnabled;
@property (nonatomic, assign, readwrite, getter=isCapturing) BOOL capturing;
@property (nonatomic, assign, readwrite) BOOL streaming;
@property (nonatomic, assign, readwrite) HAStreamingCameraMode cameraMode;
@property (nonatomic, assign, readwrite) float qualityScale;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoDataOutput *frontVideoOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *rearVideoOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
@property (nonatomic, strong) dispatch_queue_t captureQueue;
@property (nonatomic, strong) dispatch_queue_t audioCaptureQueue;
@property (nonatomic, assign) BOOL configuringCapture;
@property (nonatomic, assign) VTCompressionSessionRef frontCompressionSession;
@property (nonatomic, assign) VTCompressionSessionRef rearCompressionSession;
@property (nonatomic, assign) BOOL forceFrontKeyFrame;
@property (nonatomic, assign) BOOL forceRearKeyFrame;
@property (nonatomic, strong) HAAACEncoder *audioEncoder;
@property (nonatomic, strong) HARTSPServer *primaryRTSPServer;
@property (nonatomic, strong) HARTSPServer *secondaryRTSPServer;
@property (nonatomic, strong) NSData *publishedFrontConfiguration;
@property (nonatomic, strong) NSData *publishedRearConfiguration;
@property (nonatomic, strong) NSData *publishedAudioConfiguration;
@property (nonatomic, assign) NSUInteger publishedAudioChannels;
@property (nonatomic, assign) NSUInteger publishedAudioSampleRate;
@property (nonatomic, assign) CMTime mediaStartTime;
@property (nonatomic, assign) BOOL loggedFrontVideo;
@property (nonatomic, assign) BOOL loggedRearVideo;
@property (nonatomic, assign) BOOL loggedAudioInput;
@property (nonatomic, assign) NSUInteger audioInputBufferCount;
@property (nonatomic, assign) BOOL loggedAudioConfiguration;
@property (nonatomic, assign) BOOL loggedEncodedAudio;
@property (nonatomic, assign) AVCaptureVideoOrientation captureOrientation;
@property (nonatomic, assign) NSUInteger orientationChangeGeneration;
@property (nonatomic, assign) NSUInteger observedAuthenticationRevision;
@property (nonatomic, assign) BOOL observedDemoMode;
+ (BOOL)supportsOperatingSystemVersion:(NSOperatingSystemVersion)version;
+ (BOOL)usesAudioCompatiblePresetForOperatingSystemVersion:(NSOperatingSystemVersion)version;
+ (NSArray<NSString *> *)preferredLegacySessionPresetsForQualityScale:(float)qualityScale;
- (void)handleCompressedVideoSample:(CMSampleBufferRef)sampleBuffer
                             status:(OSStatus)status
                             output:(AVCaptureVideoDataOutput *)output;
- (void)clearAudioMediaStateSynchronously;
@end

static void HAStreamingCompressionOutput(void *context,
                                         void *sourceFrameRefCon,
                                         OSStatus status,
                                         VTEncodeInfoFlags flags,
                                         CMSampleBufferRef sampleBuffer) {
    (void)flags;
    HAStreamingManager *manager = (__bridge HAStreamingManager *)context;
    AVCaptureVideoDataOutput *output = (__bridge AVCaptureVideoDataOutput *)sourceFrameRefCon;
    [manager handleCompressedVideoSample:sampleBuffer status:status output:output];
}

@implementation HAStreamingManager

+ (instancetype)sharedManager {
    static HAStreamingManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL persistedEnabled = [defaults boolForKey:kHAStreamingEnabledKey];
    _featureEnabled = persistedEnabled && self.supported;
    if (persistedEnabled && !_featureEnabled) {
        // A restored preference or legacy deployment must never bypass the
        // platform gate and request camera/microphone access on iOS 9.
        [defaults setBool:NO forKey:kHAStreamingEnabledKey];
        [defaults synchronize];
    }
    _captureQueue = dispatch_queue_create("com.hadashboard.localstream.capture", DISPATCH_QUEUE_SERIAL);
    _audioCaptureQueue = dispatch_queue_create("com.hadashboard.localstream.audio", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_audioCaptureQueue, &HAStreamingAudioCaptureQueueKey,
                                &HAStreamingAudioCaptureQueueKey, NULL);
    _mediaStartTime = kCMTimeInvalid;
    _captureOrientation = [self currentVideoOrientation];
    _observedAuthenticationRevision = [HAAuthManager sharedManager].authenticationRevision;
    _observedDemoMode = [HAAuthManager sharedManager].isDemoMode;

    NSNumber *storedMode = [defaults objectForKey:kHAStreamingCameraModeKey];
    if (storedMode) {
        _cameraMode = (HAStreamingCameraMode)storedMode.integerValue;
    } else if ([defaults boolForKey:kHAStreamingLegacyRearCameraKey]) {
        _cameraMode = HAStreamingCameraModeRear;
    } else {
        _cameraMode = [self cameraForPosition:AVCaptureDevicePositionBack]
            ? HAStreamingCameraModeRear : HAStreamingCameraModeFront;
    }
    _cameraMode = [self validatedCameraMode:_cameraMode];
    NSNumber *storedScale = [defaults objectForKey:kHAStreamingQualityScaleKey];
    if (storedScale) {
        _qualityScale = MIN(1.0f, MAX(0.0f, storedScale.floatValue));
    } else {
        NSNumber *legacyPreset = [defaults objectForKey:kHAStreamingLegacyQualityPresetKey];
        if (legacyPreset.integerValue <= 0 && legacyPreset) _qualityScale = 0.0f;
        else if (legacyPreset.integerValue >= 2) _qualityScale = 1.0f;
        else _qualityScale = [self defaultQualityScale];
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(resign:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(auth:) name:HAAuthManagerDidUpdateNotification object:nil];
    [center addObserver:self selector:@selector(interrupted:) name:AVCaptureSessionWasInterruptedNotification object:nil];
    [center addObserver:self selector:@selector(interrupted:) name:AVCaptureSessionRuntimeErrorNotification object:nil];
    [center addObserver:self selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(orientationChanged:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [self stopWithTrigger:HAStreamingStopTriggerUser error:nil];
}

#pragma mark - Public state

- (BOOL)supported {
    return [[self class] supportsOperatingSystemVersion:[NSProcessInfo processInfo].operatingSystemVersion];
}

+ (BOOL)supportsOperatingSystemVersion:(NSOperatingSystemVersion)version {
    if (version.majorVersion > 10) return YES;
    if (version.majorVersion < 10 || version.minorVersion < 3) return NO;
    if (version.minorVersion > 3) return YES;
    return version.patchVersion >= 3;
}

- (BOOL)configured { return YES; }
- (NSString *)streamURL { return self.primaryRTSPServer.streamURL; }
- (NSString *)secondaryStreamURL { return self.secondaryRTSPServer.streamURL; }

- (NSArray<NSString *> *)streamURLs {
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    if (self.streamURL.length) [urls addObject:self.streamURL];
    if (self.secondaryStreamURL.length) [urls addObject:self.secondaryStreamURL];
    return urls;
}

- (NSUInteger)streamClientCount {
    return self.primaryRTSPServer.clientCount + self.secondaryRTSPServer.clientCount;
}

- (NSUInteger)streamConnectionCount {
    return self.primaryRTSPServer.connectionCount + self.secondaryRTSPServer.connectionCount;
}

- (NSUInteger)streamPlayingClientCount {
    return self.primaryRTSPServer.playingClientCount + self.secondaryRTSPServer.playingClientCount;
}

- (BOOL)frontCameraAvailable {
    return self.supported && [self cameraForPosition:AVCaptureDevicePositionFront] != nil;
}

- (BOOL)rearCameraAvailable {
    return self.supported && [self cameraForPosition:AVCaptureDevicePositionBack] != nil;
}

- (BOOL)multiCamSupported {
    if (@available(iOS 13.0, *)) {
        return self.frontCameraAvailable && self.rearCameraAvailable &&
               [AVCaptureMultiCamSession isMultiCamSupported];
    }
    return NO;
}

- (BOOL)useRearCamera { return self.cameraMode == HAStreamingCameraModeRear; }

- (BOOL)setFeatureEnabled:(BOOL)enabled error:(NSError **)error {
    if (enabled && !self.supported) {
        if (error) *error = [self error:@"Local camera streaming requires iOS 10.3.3 or newer."];
        return NO;
    }
    self.featureEnabled = enabled;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kHAStreamingEnabledKey];
    [defaults synchronize];
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    if (!enabled) {
        [[HACameraRegistrationManager sharedManager] cancelRegistration];
        [self stopWithTrigger:HAStreamingStopTriggerFeatureDisabled error:nil];
    }
    [self post:nil];
    return YES;
}

- (BOOL)setCameraMode:(HAStreamingCameraMode)cameraMode error:(NSError **)error {
    HAStreamingCameraMode validated = [self validatedCameraMode:cameraMode];
    if (validated != cameraMode) {
        NSString *description = cameraMode == HAStreamingCameraModeBoth
            ? @"This device cannot capture its front and rear cameras simultaneously."
            : @"The selected camera is not available on this device.";
        if (error) *error = [self error:description];
        return NO;
    }
    if (self.cameraMode == cameraMode) return YES;

    BOOL shouldRearm = self.featureEnabled && self.streaming;
    if (shouldRearm) [self stopWithTrigger:HAStreamingStopTriggerUser error:nil];
    self.cameraMode = cameraMode;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:cameraMode forKey:kHAStreamingCameraModeKey];
    [defaults setBool:(cameraMode == HAStreamingCameraModeRear) forKey:kHAStreamingLegacyRearCameraKey];
    [defaults synchronize];
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    [self post:nil];
    if (shouldRearm) [self armLocalStreamWithCompletion:nil];
    return YES;
}

- (void)setUseRearCamera:(BOOL)useRearCamera {
    [self setCameraMode:useRearCamera ? HAStreamingCameraModeRear : HAStreamingCameraModeFront error:nil];
}

- (BOOL)setQualityScale:(float)qualityScale error:(NSError **)error {
    if (!isfinite(qualityScale)) {
        if (error) *error = [self error:@"The selected stream quality is invalid."];
        return NO;
    }
    float clampedScale = MIN(1.0f, MAX(0.0f, qualityScale));
    if (fabsf(self.qualityScale - clampedScale) < 0.001f) return YES;

    BOOL shouldRestartCapture = self.isCapturing && self.streamClientCount > 0;
    self.qualityScale = clampedScale;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:clampedScale forKey:kHAStreamingQualityScaleKey];
    [defaults synchronize];
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    [self post:nil];
    if (shouldRestartCapture) [self restartCapturePreservingClients];
    return YES;
}

- (void)clearLocalStreamConfiguration {
    [self setFeatureEnabled:NO error:nil];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kHAStreamingCameraModeKey];
    [defaults removeObjectForKey:kHAStreamingQualityScaleKey];
    [defaults removeObjectForKey:kHAStreamingLegacyQualityPresetKey];
    [defaults removeObjectForKey:kHAStreamingLegacyRearCameraKey];
    [defaults synchronize];

    self.cameraMode = self.rearCameraAvailable
        ? HAStreamingCameraModeRear : HAStreamingCameraModeFront;
    self.qualityScale = [self defaultQualityScale];
    NSError *credentialError = nil;
    if (![[HARTSPCredentialManager sharedManager] deleteCredentialsWithError:&credentialError]) {
        HALogW(@"localstream", @"Protected stream credential reset failed: %@",
               credentialError.localizedDescription);
    }
    [self post:nil];
}

#pragma mark - Permissions and arming

- (void)permission:(NSString *)mediaType done:(void (^)(BOOL granted))done {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    if (status == AVAuthorizationStatusAuthorized) {
        done(YES);
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(granted); });
        }];
    } else {
        done(NO);
    }
}

- (void)armLocalStreamWithCompletion:(void (^)(BOOL, NSError *))completion {
    if (!self.supported) {
        [self finish:completion ok:NO error:[self error:@"Local camera streaming requires iOS 10.3.3 or newer."]];
        return;
    }
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        [self finish:completion ok:NO error:[self error:@"Start Local Stream while HA Dashboard is in the foreground."]];
        return;
    }
    if (!self.featureEnabled) {
        [self finish:completion ok:NO error:[self error:@"Enable Local Camera Stream before arming its listener."]];
        return;
    }
    if (self.streaming) {
        [self finish:completion ok:YES error:nil];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self permission:AVMediaTypeVideo done:^(BOOL cameraGranted) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!cameraGranted) {
            [strongSelf finish:completion ok:NO error:[strongSelf error:@"Camera permission is required."]];
            return;
        }
        if (![strongSelf canContinueArming]) {
            [strongSelf finish:completion ok:NO error:[strongSelf error:@"Local Camera Stream was disabled or left the foreground while requesting permission."]];
            return;
        }
        [strongSelf permission:AVMediaTypeAudio done:^(BOOL microphoneGranted) {
            typeof(self) innerSelf = weakSelf;
            if (!innerSelf) return;
            if (!microphoneGranted) {
                [innerSelf finish:completion ok:NO error:[innerSelf error:@"Microphone permission is required."]];
                return;
            }
            if (![innerSelf canContinueArming]) {
                [innerSelf finish:completion ok:NO error:[innerSelf error:@"Local Camera Stream was disabled or left the foreground while requesting permission."]];
                return;
            }
            [innerSelf startRTSPWithCompletion:completion];
        }];
    }];
}

- (void)startRTSPWithCompletion:(void (^)(BOOL, NSError *))completion {
    if (![self canContinueArming]) {
        [self finish:completion ok:NO error:[self error:@"Local Camera Stream must remain enabled in the foreground while arming."]];
        return;
    }
    NSString *host = [self localIPv4];
    if (!host.length) {
        [self finish:completion ok:NO error:[self error:@"Connect this device to a private local network on its primary interface before starting its stream."]];
        return;
    }

    NSError *credentialError = nil;
    HARTSPCredentials *credentials = [[HARTSPCredentialManager sharedManager]
        credentialsWithError:&credentialError];
    if (!credentials) {
        [self finish:completion ok:NO error:credentialError ?: [self error:@"Protected stream credentials are unavailable."]];
        return;
    }

    HARTSPServer *primary = [[HARTSPServer alloc] initWithHost:host port:8554
        username:credentials.username password:credentials.password];
    primary.delegate = self;
    NSError *serverError = nil;
    if (![primary start:&serverError]) {
        HALogE(@"localstream", @"Primary RTSP listener failed: %@", serverError.localizedDescription);
        [self finish:completion ok:NO error:serverError];
        return;
    }

    HARTSPServer *secondary = nil;
    if (self.cameraMode == HAStreamingCameraModeBoth) {
        secondary = [[HARTSPServer alloc] initWithHost:host port:8555
            username:credentials.username password:credentials.password];
        secondary.delegate = self;
        if (![secondary start:&serverError]) {
            [primary stop];
            HALogE(@"localstream", @"Secondary RTSP listener failed: %@", serverError.localizedDescription);
            [self finish:completion ok:NO error:serverError];
            return;
        }
    }

    self.primaryRTSPServer = primary;
    self.secondaryRTSPServer = secondary;
    self.streaming = YES;
    HALogI(@"localstream", @"RTSP listener armed at %@%@", primary.streamURL,
           secondary ? [NSString stringWithFormat:@" and %@", secondary.streamURL] : @"");
    [self post:nil];
    [self finish:completion ok:YES error:nil];

    if ([HADeviceIntegrationManager sharedManager].enabled) {
        [[HACameraRegistrationManager sharedManager]
            ensureCameraEntriesForStreamURLs:self.streamURLs
            deviceName:[HADeviceRegistration sharedManager].deviceName
            username:credentials.username
            password:credentials.password
            credentialRevision:credentials.revision
            framesPerSecond:self.targetFrameRate
            completion:^(BOOL success, NSError *registrationError) {
                if (!success) {
                    HALogW(@"localstream", @"Home Assistant camera registration skipped: %@",
                           registrationError.localizedDescription);
                }
            }];
    }
}

- (BOOL)canContinueArming {
    return self.featureEnabled &&
           [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
}

- (void)rotateStreamCredentialWithCompletion:(void (^)(BOOL, NSError *))completion {
    if (![self canContinueArming]) {
        [self finish:completion ok:NO error:[self error:@"Rotate the stream password only while Local Camera Stream is enabled in the foreground."]];
        return;
    }
    NSError *credentialError = nil;
    HARTSPCredentials *credentials = [[HARTSPCredentialManager sharedManager]
        rotateCredentialsWithError:&credentialError];
    if (!credentials) {
        [self finish:completion ok:NO error:credentialError];
        return;
    }
    if ([HADeviceIntegrationManager sharedManager].enabled) {
        HALogI(@"localstream", @"Protected stream credential rotated; disconnecting viewers; Home Assistant entry reconciliation will start asynchronously after the listener re-arms");
    } else {
        HALogI(@"localstream", @"Protected stream credential rotated; disconnecting viewers; manual clients require the new credential");
    }
    if (self.streaming || self.isCapturing || self.configuringCapture) {
        [self stopWithTrigger:HAStreamingStopTriggerUser error:nil];
    }
    [self armLocalStreamWithCompletion:completion];
}

#pragma mark - Capture configuration

- (void)configureCaptureWithCompletion:(void (^)(BOOL, NSError *))completion {
    if (self.captureSession || self.configuringCapture) {
        [self finish:completion ok:YES error:nil];
        return;
    }
    self.configuringCapture = YES;

    NSError *audioError = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setPreferredSampleRate:48000 error:nil];
    [audioSession setPreferredIOBufferDuration:0.01 error:nil];
    if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&audioError] ||
        ![audioSession setActive:YES error:&audioError]) {
        self.configuringCapture = NO;
        [self finish:completion ok:NO error:audioError ?: [self error:@"Could not activate the microphone."]];
        return;
    }

    if (self.cameraMode == HAStreamingCameraModeBoth) {
        [self configureMultiCamCaptureWithCompletion:completion];
    } else {
        [self configureSingleCameraCaptureWithCompletion:completion];
    }
}

- (void)configureSingleCameraCaptureWithCompletion:(void (^)(BOOL, NSError *))completion {
    AVCaptureDevicePosition position = self.cameraMode == HAStreamingCameraModeRear
        ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    AVCaptureDevice *camera = [self cameraForPosition:position];
    AVCaptureDevice *microphone = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (!camera || !microphone) {
        self.configuringCapture = NO;
        [self finish:completion ok:NO error:[self error:@"Camera or microphone is unavailable."]];
        return;
    }

    NSError *inputError = nil;
    AVCaptureDeviceInput *cameraInput = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&inputError];
    AVCaptureDeviceInput *microphoneInput = [AVCaptureDeviceInput deviceInputWithDevice:microphone error:&inputError];
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];
    if (!cameraInput || !microphoneInput || ![session canAddInput:cameraInput] || ![session canAddInput:microphoneInput]) {
        [session commitConfiguration];
        self.configuringCapture = NO;
        [self finish:completion ok:NO error:inputError ?: [self error:@"Could not open camera or microphone."]];
        return;
    }
    [session addInput:cameraInput];
    [session addInput:microphoneInput];
    BOOL usesLegacyPreset = [[self class] usesAudioCompatiblePresetForOperatingSystemVersion:
        [NSProcessInfo processInfo].operatingSystemVersion];
    if (usesLegacyPreset) {
        BOOL selectedPreset = NO;
        for (NSString *preset in [[self class]
                preferredLegacySessionPresetsForQualityScale:self.qualityScale]) {
            if (![session canSetSessionPreset:preset]) continue;
            session.sessionPreset = preset;
            selectedPreset = YES;
            HALogI(@"localstream", @"Using %@ capture preset to retain microphone audio on iOS 10.", preset);
            break;
        }
        if (!selectedPreset) {
            [session commitConfiguration];
            self.configuringCapture = NO;
            [self finish:completion ok:NO error:[self error:@"No audio-compatible camera quality is available on this device."]];
            return;
        }
    } else {
        if ([session canSetSessionPreset:AVCaptureSessionPresetInputPriority]) {
            session.sessionPreset = AVCaptureSessionPresetInputPriority;
        }
        HAStreamingQualityProfile *qualityProfile = [self qualityProfileForDevice:camera scale:self.qualityScale];
        if (![self applyQualityProfile:qualityProfile toDevice:camera error:&inputError]) {
            [session commitConfiguration];
            self.configuringCapture = NO;
            [self finish:completion ok:NO error:inputError ?: [self error:@"Could not apply the selected camera quality."]];
            return;
        }
    }

    AVCaptureVideoDataOutput *videoOutput = [self newVideoOutput];
    AVCaptureAudioDataOutput *audioOutput = [self newAudioOutput];
    if (![session canAddOutput:videoOutput] || ![session canAddOutput:audioOutput]) {
        [session commitConfiguration];
        self.configuringCapture = NO;
        [self finish:completion ok:NO error:[self error:@"Device cannot produce local camera and audio streams."]];
        return;
    }
    [session addOutput:videoOutput];
    [session addOutput:audioOutput];
    [session commitConfiguration];

    if (position == AVCaptureDevicePositionBack) self.rearVideoOutput = videoOutput;
    else self.frontVideoOutput = videoOutput;
    self.audioOutput = audioOutput;
    [self applyVideoOrientationToOutputs];
    [self startCaptureSession:session completion:completion];
}

- (void)configureMultiCamCaptureWithCompletion:(void (^)(BOOL, NSError *))completion {
    if (@available(iOS 13.0, *)) {
        if (!self.multiCamSupported) {
            self.configuringCapture = NO;
            [self finish:completion ok:NO error:[self error:@"This device does not support simultaneous front and rear capture."]];
            return;
        }

        AVCaptureDevice *frontCamera = [self cameraForPosition:AVCaptureDevicePositionFront];
        AVCaptureDevice *rearCamera = [self cameraForPosition:AVCaptureDevicePositionBack];
        AVCaptureDevice *microphone = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        NSError *configurationError = nil;
        if (![self configureMultiCamFormatForDevice:frontCamera error:&configurationError] ||
            ![self configureMultiCamFormatForDevice:rearCamera error:&configurationError]) {
            self.configuringCapture = NO;
            [self finish:completion ok:NO error:configurationError];
            return;
        }

        AVCaptureDeviceInput *frontInput = [AVCaptureDeviceInput deviceInputWithDevice:frontCamera error:&configurationError];
        AVCaptureDeviceInput *rearInput = [AVCaptureDeviceInput deviceInputWithDevice:rearCamera error:&configurationError];
        AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:microphone error:&configurationError];
        if (!frontInput || !rearInput || !audioInput) {
            self.configuringCapture = NO;
            [self finish:completion ok:NO error:configurationError ?: [self error:@"Could not open both cameras and the microphone."]];
            return;
        }

        AVCaptureMultiCamSession *session = [[AVCaptureMultiCamSession alloc] init];
        [session beginConfiguration];
        NSArray<AVCaptureInput *> *inputs = @[frontInput, rearInput, audioInput];
        for (AVCaptureInput *input in inputs) {
            if (![session canAddInput:input]) {
                [session commitConfiguration];
                self.configuringCapture = NO;
                [self finish:completion ok:NO error:[self error:@"Could not add both cameras and the microphone."]];
                return;
            }
            [session addInputWithNoConnections:input];
        }

        AVCaptureVideoDataOutput *frontOutput = [self newVideoOutput];
        AVCaptureVideoDataOutput *rearOutput = [self newVideoOutput];
        AVCaptureAudioDataOutput *audioOutput = [self newAudioOutput];
        NSArray<AVCaptureOutput *> *outputs = @[frontOutput, rearOutput, audioOutput];
        for (AVCaptureOutput *output in outputs) {
            if (![session canAddOutput:output]) {
                [session commitConfiguration];
                self.configuringCapture = NO;
                [self finish:completion ok:NO error:[self error:@"Could not add both camera stream outputs."]];
                return;
            }
            [session addOutputWithNoConnections:output];
        }

        AVCaptureInputPort *frontPort = [self videoPortForInput:frontInput position:AVCaptureDevicePositionFront];
        AVCaptureInputPort *rearPort = [self videoPortForInput:rearInput position:AVCaptureDevicePositionBack];
        AVCaptureInputPort *audioPort = [self audioPortForInput:audioInput];
        if (![self addConnectionFromPort:frontPort output:frontOutput toSession:session] ||
            ![self addConnectionFromPort:rearPort output:rearOutput toSession:session] ||
            ![self addConnectionFromPort:audioPort output:audioOutput toSession:session]) {
            [session commitConfiguration];
            self.configuringCapture = NO;
            [self finish:completion ok:NO error:[self error:@"Could not connect both cameras to their stream tracks."]];
            return;
        }
        [session commitConfiguration];

        if (@available(iOS 16.0, *)) {
            if (session.hardwareCost > 1.0f) {
                self.configuringCapture = NO;
                [self finish:completion ok:NO error:[self error:@"This front and rear camera combination exceeds the device capture budget."]];
                return;
            }
        }

        self.frontVideoOutput = frontOutput;
        self.rearVideoOutput = rearOutput;
        self.audioOutput = audioOutput;
        [self applyVideoOrientationToOutputs];
        HALogI(@"localstream", @"Configured simultaneous front/rear MultiCam capture.");
        [self startCaptureSession:session completion:completion];
        return;
    }

    self.configuringCapture = NO;
    [self finish:completion ok:NO error:[self error:@"MultiCam requires iOS 13 or newer."]];
}

- (AVCaptureVideoDataOutput *)newVideoOutput {
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
    [output setSampleBufferDelegate:self queue:self.captureQueue];
    return output;
}

- (AVCaptureAudioDataOutput *)newAudioOutput {
    AVCaptureAudioDataOutput *output = [[AVCaptureAudioDataOutput alloc] init];
    // Audio must not share the old-device video callback queue. On A6-era
    // hardware, real-time H.264 submission can keep that serial queue busy
    // enough for AVCaptureAudioDataOutput to stop delivering after its first
    // buffer. A dedicated queue keeps full-rate microphone delivery alive.
    [output setSampleBufferDelegate:self queue:self.audioCaptureQueue];
    return output;
}

- (void)startCaptureSession:(AVCaptureSession *)session completion:(void (^)(BOOL, NSError *))completion {
    self.captureSession = session;
    self.loggedFrontVideo = NO;
    self.loggedRearVideo = NO;
    self.loggedAudioInput = NO;
    self.audioInputBufferCount = 0;
    self.loggedAudioConfiguration = NO;
    self.loggedEncodedAudio = NO;
    dispatch_async(self.captureQueue, ^{
        [session startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.captureSession != session) return;
            self.configuringCapture = NO;
            self.capturing = YES;
            [self post:nil];
            [self finish:completion ok:YES error:nil];
        });
    });
}

#pragma mark - Device and MultiCam helpers

- (NSArray<HAStreamingQualityProfile *> *)qualityProfilesForDevice:(AVCaptureDevice *)device
                                                      multiCamOnly:(BOOL)multiCamOnly {
    NSMutableDictionary<NSString *, HAStreamingQualityProfile *> *profilesBySize = [NSMutableDictionary dictionary];
    for (AVCaptureDeviceFormat *format in device.formats) {
        if (@available(iOS 13.0, *)) {
            if (multiCamOnly && !format.isMultiCamSupported) continue;
        } else if (multiCamOnly) {
            continue;
        }
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        if (dimensions.width < 320 || dimensions.height < 240) continue;
        double aspectRatio = (double)dimensions.width / (double)dimensions.height;
        if (aspectRatio < 1.2 || aspectRatio > 2.0) continue;

        Float64 maximumRate = 0;
        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
            maximumRate = MAX(maximumRate, range.maxFrameRate);
        }
        NSInteger frameRate = (NSInteger)floor(MIN(maximumRate, multiCamOnly ? 15.0 : 30.0));
        if (frameRate < 10) continue;

        NSString *key = [NSString stringWithFormat:@"%dx%d", dimensions.width, dimensions.height];
        HAStreamingQualityProfile *existing = profilesBySize[key];
        if (existing && existing.frameRate >= frameRate) continue;

        HAStreamingQualityProfile *profile = [[HAStreamingQualityProfile alloc] init];
        profile.format = format;
        profile.dimensions = dimensions;
        profile.frameRate = frameRate;
        double bitsPerSecond = (double)dimensions.width * dimensions.height * frameRate * 0.10;
        if (multiCamOnly) bitsPerSecond *= 0.75;
        profile.bitRate = (NSInteger)MIN(8000000.0, MAX(180000.0, bitsPerSecond));
        profilesBySize[key] = profile;
    }

    NSArray *profiles = profilesBySize.allValues;
    return [profiles sortedArrayUsingComparator:^NSComparisonResult(HAStreamingQualityProfile *left,
                                                                    HAStreamingQualityProfile *right) {
        uint64_t leftArea = (uint64_t)left.dimensions.width * left.dimensions.height;
        uint64_t rightArea = (uint64_t)right.dimensions.width * right.dimensions.height;
        if (leftArea < rightArea) return NSOrderedAscending;
        if (leftArea > rightArea) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (HAStreamingQualityProfile *)profileFromProfiles:(NSArray<HAStreamingQualityProfile *> *)profiles
                                              scale:(float)scale {
    if (profiles.count == 0) return nil;
    NSUInteger index = (NSUInteger)lroundf(MIN(1.0f, MAX(0.0f, scale)) * (profiles.count - 1));
    return profiles[index];
}

- (float)defaultQualityScale {
    if (!self.supported) return 0.5f;
    AVCaptureDevicePosition position = self.cameraMode == HAStreamingCameraModeRear
        ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    AVCaptureDevice *device = [self cameraForPosition:position];
    NSArray<HAStreamingQualityProfile *> *profiles =
        [self qualityProfilesForDevice:device multiCamOnly:self.cameraMode == HAStreamingCameraModeBoth];
    if (profiles.count <= 1) return 0.0f;
    uint64_t targetArea = 640ULL * 480ULL;
    NSUInteger closestIndex = 0;
    uint64_t closestDistance = UINT64_MAX;
    for (NSUInteger index = 0; index < profiles.count; index++) {
        CMVideoDimensions dimensions = profiles[index].dimensions;
        uint64_t area = (uint64_t)dimensions.width * dimensions.height;
        uint64_t distance = area > targetArea ? area - targetArea : targetArea - area;
        if (distance < closestDistance) { closestDistance = distance; closestIndex = index; }
    }
    return (float)closestIndex / (float)(profiles.count - 1);
}

- (HAStreamingQualityProfile *)qualityProfileForDevice:(AVCaptureDevice *)device scale:(float)scale {
    BOOL multiCam = self.cameraMode == HAStreamingCameraModeBoth;
    NSArray<HAStreamingQualityProfile *> *profiles = [self qualityProfilesForDevice:device multiCamOnly:multiCam];
    if (!multiCam) return [self profileFromProfiles:profiles scale:scale];

    AVCaptureDevicePosition otherPosition = device.position == AVCaptureDevicePositionFront
        ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    AVCaptureDevice *otherDevice = [self cameraForPosition:otherPosition];
    NSArray<HAStreamingQualityProfile *> *otherProfiles =
        [self qualityProfilesForDevice:otherDevice multiCamOnly:YES];
    NSMutableSet<NSString *> *otherSizes = [NSMutableSet set];
    for (HAStreamingQualityProfile *profile in otherProfiles) {
        [otherSizes addObject:[NSString stringWithFormat:@"%dx%d", profile.dimensions.width, profile.dimensions.height]];
    }
    NSMutableArray<HAStreamingQualityProfile *> *commonProfiles = [NSMutableArray array];
    for (HAStreamingQualityProfile *profile in profiles) {
        NSString *key = [NSString stringWithFormat:@"%dx%d", profile.dimensions.width, profile.dimensions.height];
        if ([otherSizes containsObject:key]) [commonProfiles addObject:profile];
    }
    return [self profileFromProfiles:commonProfiles.count ? commonProfiles : profiles scale:scale];
}

- (HAStreamingQualityProfile *)currentQualityProfile {
    AVCaptureDevicePosition position = self.cameraMode == HAStreamingCameraModeRear
        ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    return [self qualityProfileForDevice:[self cameraForPosition:position] scale:self.qualityScale];
}

- (NSInteger)targetFrameRate {
    return [self currentQualityProfile].frameRate ?: 15;
}

- (NSInteger)targetBitRate {
    return [self currentQualityProfile].bitRate ?: 600000;
}

- (NSString *)qualityDescription {
    return [self qualityDescriptionForScale:self.qualityScale];
}

- (NSString *)qualityDescriptionForScale:(float)qualityScale {
    if (!self.supported) return @"Requires iOS 10.3.3 or newer";
    AVCaptureDevicePosition position = self.cameraMode == HAStreamingCameraModeRear
        ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    HAStreamingQualityProfile *profile =
        [self qualityProfileForDevice:[self cameraForPosition:position] scale:qualityScale];
    if (!profile) return @"No compatible camera format";
    double megabits = profile.bitRate / 1000000.0;
    NSString *base = [NSString stringWithFormat:@"%d×%d · %ld fps · %.1f Mbps",
        profile.dimensions.width, profile.dimensions.height, (long)profile.frameRate, megabits];
    return self.cameraMode == HAStreamingCameraModeBoth
        ? [base stringByAppendingString:@" per camera"] : base;
}

- (AVCaptureDevice *)cameraForPosition:(AVCaptureDevicePosition)position {
    NSArray<AVCaptureDevice *> *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) return device;
    }
    if (position == AVCaptureDevicePositionFront) {
        AVCaptureDevice *defaultDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (defaultDevice && defaultDevice.position != AVCaptureDevicePositionBack) return defaultDevice;
    }
    return nil;
}

- (HAStreamingCameraMode)validatedCameraMode:(HAStreamingCameraMode)mode {
    if (!self.supported) return HAStreamingCameraModeFront;
    if (mode == HAStreamingCameraModeBoth && self.multiCamSupported) return mode;
    if (mode == HAStreamingCameraModeRear && self.rearCameraAvailable) return mode;
    if (mode == HAStreamingCameraModeFront && self.frontCameraAvailable) return mode;
    if (self.rearCameraAvailable) return HAStreamingCameraModeRear;
    return HAStreamingCameraModeFront;
}

+ (BOOL)usesAudioCompatiblePresetForOperatingSystemVersion:(NSOperatingSystemVersion)version {
    // AVFoundation documents that before iOS 11, selecting a photo-equivalent
    // activeFormat makes the AVCaptureAudioDataOutput connection inactive.
    // Video session presets retain the microphone connection on iOS 10.
    return version.majorVersion < 11;
}

+ (NSArray<NSString *> *)preferredLegacySessionPresetsForQualityScale:(float)qualityScale {
    float scale = MIN(1.0f, MAX(0.0f, qualityScale));
    if (scale < 0.34f) {
        return @[AVCaptureSessionPreset640x480,
                 AVCaptureSessionPreset1280x720,
                 AVCaptureSessionPresetHigh];
    }
    if (scale < 0.67f) {
        return @[AVCaptureSessionPreset1280x720,
                 AVCaptureSessionPresetHigh,
                 AVCaptureSessionPreset640x480];
    }
    return @[AVCaptureSessionPreset1920x1080,
             AVCaptureSessionPreset1280x720,
             AVCaptureSessionPresetHigh,
             AVCaptureSessionPreset640x480];
}

- (BOOL)configureMultiCamFormatForDevice:(AVCaptureDevice *)device error:(NSError **)error {
    if (@available(iOS 13.0, *)) {
        HAStreamingQualityProfile *profile = [self qualityProfileForDevice:device scale:self.qualityScale];
        return [self applyQualityProfile:profile toDevice:device error:error];
    }
    if (error) *error = [self error:@"MultiCam requires iOS 13 or newer."];
    return NO;
}

- (BOOL)applyQualityProfile:(HAStreamingQualityProfile *)profile
                    toDevice:(AVCaptureDevice *)device
                       error:(NSError **)error {
    if (!profile || !device) {
        if (error) *error = [self error:@"No compatible camera quality is available."];
        return NO;
    }
    NSError *lockError = nil;
    if (![device lockForConfiguration:&lockError]) {
        if (error) *error = lockError;
        return NO;
    }
    device.activeFormat = profile.format;
    CMTime duration = CMTimeMake(1, (int32_t)profile.frameRate);
    device.activeVideoMinFrameDuration = duration;
    device.activeVideoMaxFrameDuration = duration;
    [device unlockForConfiguration];
    return YES;
}

- (AVCaptureInputPort *)videoPortForInput:(AVCaptureDeviceInput *)input
                                  position:(AVCaptureDevicePosition)position API_AVAILABLE(ios(13.0)) {
    AVCaptureInputPort *port = [input portsWithMediaType:AVMediaTypeVideo
                                        sourceDeviceType:input.device.deviceType
                                     sourceDevicePosition:position].firstObject;
    if (port) return port;
    for (AVCaptureInputPort *candidate in input.ports) {
        if ([candidate.mediaType isEqualToString:AVMediaTypeVideo]) return candidate;
    }
    return nil;
}

- (AVCaptureInputPort *)audioPortForInput:(AVCaptureDeviceInput *)input API_AVAILABLE(ios(13.0)) {
    AVCaptureInputPort *port = [input portsWithMediaType:AVMediaTypeAudio
                                        sourceDeviceType:nil
                                     sourceDevicePosition:AVCaptureDevicePositionUnspecified].firstObject;
    if (port) return port;
    for (AVCaptureInputPort *candidate in input.ports) {
        if ([candidate.mediaType isEqualToString:AVMediaTypeAudio]) return candidate;
    }
    return nil;
}

- (BOOL)addConnectionFromPort:(AVCaptureInputPort *)port
                        output:(AVCaptureOutput *)output
                     toSession:(AVCaptureSession *)session API_AVAILABLE(ios(13.0)) {
    if (!port) return NO;
    AVCaptureConnection *connection = [AVCaptureConnection connectionWithInputPorts:@[port] output:output];
    if (![session canAddConnection:connection]) return NO;
    [session addConnection:connection];
    return YES;
}

#pragma mark - Encoding

- (void)captureOutput:(AVCaptureOutput *)output
 didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    (void)connection;
    if (!self.captureSession) return;
    if (output == self.frontVideoOutput || output == self.rearVideoOutput) {
        [self encodeVideo:sampleBuffer output:(AVCaptureVideoDataOutput *)output];
    } else if (output == self.audioOutput && self.streaming) {
        [self encodeAudio:sampleBuffer];
    }
}

- (void)encodeVideo:(CMSampleBufferRef)sampleBuffer output:(AVCaptureVideoDataOutput *)output {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return;

    BOOL isFront = output == self.frontVideoOutput;
    VTCompressionSessionRef session = isFront ? self.frontCompressionSession : self.rearCompressionSession;
    if (!session) {
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(CMSampleBufferGetFormatDescription(sampleBuffer));
        OSStatus status = VTCompressionSessionCreate(kCFAllocatorDefault, dimensions.width, dimensions.height,
            kCMVideoCodecType_H264, NULL, NULL, NULL, HAStreamingCompressionOutput,
            (__bridge void *)self, &session);
        if (status != noErr || !session) {
            [self captureError:@"Could not create H.264 encoder."];
            return;
        }
        NSInteger frameRate = [self targetFrameRate];
        NSNumber *expectedRate = @(frameRate);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)expectedRate);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@([self targetBitRate]));
        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(MAX(1, frameRate / 2)));
        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (__bridge CFTypeRef)@0.5);
        if (@available(iOS 14.0, *)) {
            VTSessionSetProperty(session, kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue);
        }
        VTCompressionSessionPrepareToEncodeFrames(session);
        if (isFront) self.frontCompressionSession = session;
        else self.rearCompressionSession = session;
    }

    BOOL forceKeyFrame = isFront ? self.forceFrontKeyFrame : self.forceRearKeyFrame;
    if (isFront) self.forceFrontKeyFrame = NO;
    else self.forceRearKeyFrame = NO;
    CFDictionaryRef options = forceKeyFrame
        ? (__bridge CFDictionaryRef)@{(__bridge id)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES}
        : NULL;
    OSStatus status = VTCompressionSessionEncodeFrame(session, imageBuffer,
        CMSampleBufferGetPresentationTimeStamp(sampleBuffer), kCMTimeInvalid, options,
        (__bridge void *)output, NULL);
    if (status != noErr) [self captureError:@"H.264 encoder stopped accepting frames."];
}

- (void)handleCompressedVideoSample:(CMSampleBufferRef)sampleBuffer
                             status:(OSStatus)status
                             output:(AVCaptureVideoDataOutput *)output {
    if (output != self.frontVideoOutput && output != self.rearVideoOutput) return;
    if (status != noErr || !sampleBuffer || !CMSampleBufferDataIsReady(sampleBuffer)) {
        [self captureError:@"H.264 encoding failed."];
        return;
    }

    CMVideoFormatDescriptionRef format = (CMVideoFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer);
    const uint8_t *sps = NULL, *pps = NULL;
    size_t spsLength = 0, ppsLength = 0, parameterCount = 0;
    if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &spsLength, &parameterCount, NULL) != noErr ||
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pps, &ppsLength, NULL, NULL) != noErr ||
        spsLength < 4) {
        [self captureError:@"H.264 stream configuration is invalid."];
        return;
    }

    NSMutableData *configuration = [NSMutableData data];
    uint8_t header[6] = {1, sps[1], sps[2], sps[3], 0xFF, 0xE1};
    [configuration appendBytes:header length:sizeof(header)];
    uint16_t length = CFSwapInt16HostToBig((uint16_t)spsLength);
    [configuration appendBytes:&length length:sizeof(length)];
    [configuration appendBytes:sps length:spsLength];
    uint8_t one = 1;
    [configuration appendBytes:&one length:1];
    length = CFSwapInt16HostToBig((uint16_t)ppsLength);
    [configuration appendBytes:&length length:sizeof(length)];
    [configuration appendBytes:pps length:ppsLength];

    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t contiguousLength = 0, totalLength = 0;
    char *bytes = NULL;
    if (CMBlockBufferGetDataPointer(block, 0, &contiguousLength, &totalLength, &bytes) != noErr || !bytes) return;
    NSData *nalUnits = nil;
    if (contiguousLength >= totalLength) {
        nalUnits = [NSData dataWithBytes:bytes length:totalLength];
    } else {
        NSMutableData *copy = [NSMutableData dataWithLength:totalLength];
        if (CMBlockBufferCopyDataBytes(block, 0, totalLength, copy.mutableBytes) != noErr) return;
        nalUnits = copy;
    }
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    BOOL keyFrame = !(attachments && CFArrayGetCount(attachments) &&
                      CFDictionaryContainsKey(CFArrayGetValueAtIndex(attachments, 0), kCMSampleAttachmentKey_NotSync));
    BOOL isFront = output == self.frontVideoOutput;
    if (isFront) {
        self.publishedFrontConfiguration = configuration;
        if (!self.loggedFrontVideo) { self.loggedFrontVideo = YES; HALogI(@"localstream", @"Encoded first front-camera H.264 frame."); }
    } else {
        self.publishedRearConfiguration = configuration;
        if (!self.loggedRearVideo) { self.loggedRearVideo = YES; HALogI(@"localstream", @"Encoded first rear-camera H.264 frame."); }
    }
    uint32_t timestamp = [self timestamp:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
    HARTSPServer *server = [self serverForVideoOutput:output];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.streaming || !server.running) return;
        [server setVideoConfiguration:configuration];
        [server sendVideoSample:nalUnits keyFrame:keyFrame timestamp:timestamp];
    });
}

- (void)encodeAudio:(CMSampleBufferRef)sampleBuffer {
    self.audioInputBufferCount++;
    NSError *encodingError = nil;
    CMAudioFormatDescriptionRef inputFormat =
        (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer);
    if (!inputFormat) {
        [self captureError:@"The microphone audio format is unavailable."];
        return;
    }
    const AudioStreamBasicDescription *description =
        CMAudioFormatDescriptionGetStreamBasicDescription(inputFormat);
    if (!description) {
        [self captureError:@"The microphone audio format is unavailable."];
        return;
    }
    if (!self.loggedAudioInput) {
        self.loggedAudioInput = YES;
        HALogI(@"localstream", @"Received first microphone PCM buffer (%ld frames, %lu Hz, %lu channel%@).",
               (long)CMSampleBufferGetNumSamples(sampleBuffer),
               (unsigned long)description->mSampleRate,
               (unsigned long)description->mChannelsPerFrame,
               description->mChannelsPerFrame == 1 ? @"" : @"s");
    } else if (self.audioInputBufferCount == 10) {
        HALogI(@"localstream", @"Microphone PCM delivery is sustained.");
    }
    if (!self.audioEncoder) {
        self.audioEncoder = [[HAAACEncoder alloc] initWithInputFormat:inputFormat
                                                               error:&encodingError];
    }
    if (!self.audioEncoder) {
        [self captureError:encodingError.localizedDescription ?: @"Could not create AAC encoder."];
        return;
    }

    NSData *configuration = self.audioEncoder.audioSpecificConfig;
    NSUInteger channels = self.audioEncoder.channelCount;
    NSUInteger sampleRate = (NSUInteger)description->mSampleRate;
    BOOL configurationChanged =
        ![self.publishedAudioConfiguration isEqualToData:configuration] ||
        self.publishedAudioChannels != channels ||
        self.publishedAudioSampleRate != sampleRate;
    self.publishedAudioConfiguration = configuration;
    self.publishedAudioChannels = channels;
    self.publishedAudioSampleRate = sampleRate;
    if (configurationChanged) {
        if (!self.loggedAudioConfiguration) {
            self.loggedAudioConfiguration = YES;
            HALogI(@"localstream", @"AAC stream configuration is ready (%lu Hz, %lu channel%@); publishing before the first encoded frame.",
                   (unsigned long)sampleRate, (unsigned long)channels,
                   channels == 1 ? @"" : @"s");
        }
        NSArray<HARTSPServer *> *servers = [self activeServers];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.streaming) return;
            for (HARTSPServer *server in servers) {
                if (!server.running) continue;
                [server setAudioConfiguration:configuration channels:channels sampleRate:sampleRate];
            }
        });
    }

    NSData *aac = [self.audioEncoder encodeSampleBuffer:sampleBuffer error:&encodingError];
    if (encodingError) {
        [self captureError:encodingError.localizedDescription];
        return;
    }
    if (!aac) return;
    if (!self.loggedEncodedAudio) {
        self.loggedEncodedAudio = YES;
        HALogI(@"localstream", @"Encoded first shared AAC frame.");
    }

    uint32_t timestamp = [self timestamp:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
    NSArray<HARTSPServer *> *servers = [self activeServers];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.streaming) return;
        for (HARTSPServer *server in servers) {
            if (!server.running) continue;
            [server sendAudioSample:aac timestamp:timestamp];
        }
    });
}

- (HARTSPServer *)serverForVideoOutput:(AVCaptureVideoDataOutput *)output {
    if (self.cameraMode == HAStreamingCameraModeBoth && output == self.rearVideoOutput) {
        return self.secondaryRTSPServer;
    }
    return self.primaryRTSPServer;
}

- (uint32_t)timestamp:(CMTime)time {
    @synchronized (self) {
        if (!CMTIME_IS_VALID(self.mediaStartTime)) self.mediaStartTime = time;
        Float64 milliseconds = CMTimeGetSeconds(CMTimeSubtract(time, self.mediaStartTime)) * 1000.0;
        return milliseconds > 0 ? (uint32_t)MIN(milliseconds, UINT32_MAX) : 0;
    }
}

#pragma mark - RTSP delegate

- (void)rtspServerDidChangeClientCount:(HARTSPServer *)server {
    (void)server;
    if (self.streamClientCount == 0) [self stopCaptureKeepListeners];
    [self post:nil];
}

- (void)rtspServerNeedsVideoKeyFrame:(HARTSPServer *)server {
    dispatch_async(self.captureQueue, ^{
        if (server == self.secondaryRTSPServer) self.forceRearKeyFrame = YES;
        else if (self.cameraMode == HAStreamingCameraModeRear) self.forceRearKeyFrame = YES;
        else self.forceFrontKeyFrame = YES;
    });
}

- (void)rtspServerNeedsMediaConfiguration:(HARTSPServer *)server {
    if (server != self.primaryRTSPServer && server != self.secondaryRTSPServer) return;
    if (self.captureSession || self.configuringCapture) return;
    HALogI(@"localstream", @"RTSP client requested %@ media; starting capture.",
           server == self.secondaryRTSPServer ? @"rear-camera" : @"primary-camera");
    [self configureCaptureWithCompletion:^(BOOL success, NSError *error) {
        if (!success) [self stopWithTrigger:HAStreamingStopTriggerCaptureInterrupted error:error];
    }];
}

- (void)rtspServer:(HARTSPServer *)server didFailWithError:(NSError *)error {
    if (server == self.primaryRTSPServer || server == self.secondaryRTSPServer) {
        [self stopWithTrigger:HAStreamingStopTriggerServerFailure error:error];
    }
}

#pragma mark - Stop and lifecycle

- (void)restartCapturePreservingClients {
    AVCaptureSession *session = self.captureSession;
    if (!session || !self.streaming || self.streamClientCount == 0) return;

    HALogI(@"localstream", @"Applying %@ without closing RTSP clients.", self.qualityDescription);
    self.captureSession = nil;
    self.configuringCapture = YES;
    self.capturing = NO;
    self.frontVideoOutput = nil;
    self.rearVideoOutput = nil;
    self.audioOutput = nil;
    self.publishedFrontConfiguration = nil;
    self.publishedRearConfiguration = nil;
    [self clearAudioMediaStateSynchronously];
    self.forceFrontKeyFrame = YES;
    self.forceRearKeyFrame = YES;

    VTCompressionSessionRef front = self.frontCompressionSession;
    VTCompressionSessionRef rear = self.rearCompressionSession;
    self.frontCompressionSession = NULL;
    self.rearCompressionSession = NULL;
    dispatch_async(self.captureQueue, ^{
        [self invalidateCompressionSession:front];
        [self invalidateCompressionSession:rear];
        [session stopRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.configuringCapture = NO;
            if (!self.streaming || self.streamClientCount == 0) return;
            [self configureCaptureWithCompletion:^(BOOL success, NSError *error) {
                if (!success) [self stopWithTrigger:HAStreamingStopTriggerCaptureInterrupted error:error];
            }];
        });
    });
}

- (void)stopCaptureKeepListeners {
    if (!self.captureSession && !self.configuringCapture) return;
    HALogI(@"localstream", @"Last RTSP client left; stopping all camera and microphone capture.");
    AVCaptureSession *session = self.captureSession;
    self.captureSession = nil;
    self.configuringCapture = NO;
    self.frontVideoOutput = nil;
    self.rearVideoOutput = nil;
    self.audioOutput = nil;
    self.capturing = NO;
    [self clearMediaState];
    [self.primaryRTSPServer clearMediaConfiguration];
    [self.secondaryRTSPServer clearMediaConfiguration];

    VTCompressionSessionRef front = self.frontCompressionSession;
    VTCompressionSessionRef rear = self.rearCompressionSession;
    self.frontCompressionSession = NULL;
    self.rearCompressionSession = NULL;
    dispatch_async(self.captureQueue, ^{
        [self invalidateCompressionSession:front];
        [self invalidateCompressionSession:rear];
        [session stopRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[AVAudioSession sharedInstance] setActive:NO
                                           withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                                 error:nil];
        });
    });
}

- (void)stopWithTrigger:(HAStreamingStopTrigger)trigger error:(NSError *)error {
    (void)trigger;
    HARTSPServer *primary = self.primaryRTSPServer;
    HARTSPServer *secondary = self.secondaryRTSPServer;
    self.primaryRTSPServer = nil;
    self.secondaryRTSPServer = nil;
    [primary stop];
    [secondary stop];
    BOOL wasActive = self.streaming || self.captureSession || self.configuringCapture;
    self.streaming = NO;
    [self stopCaptureKeepListeners];
    if (wasActive || error) [self post:error];
}

- (void)clearMediaState {
    [self clearAudioMediaStateSynchronously];
    self.publishedFrontConfiguration = nil;
    self.publishedRearConfiguration = nil;
    self.mediaStartTime = kCMTimeInvalid;
    self.forceFrontKeyFrame = NO;
    self.forceRearKeyFrame = NO;
}

- (void)clearAudioMediaStateSynchronously {
    // Audio callbacks run independently of the video/capture queue on old
    // devices. Once captureSession/audioOutput are cleared, drain every callback
    // that already passed the delegate guard before resetting shared AAC state.
    // This prevents a late callback from repopulating configuration after stop
    // and causing the next listener to miss setAudioConfiguration:.
    dispatch_block_t clear = ^{
        self.audioEncoder = nil;
        self.audioInputBufferCount = 0;
        self.publishedAudioConfiguration = nil;
        self.publishedAudioChannels = 0;
        self.publishedAudioSampleRate = 0;
    };
    if (dispatch_get_specific(&HAStreamingAudioCaptureQueueKey)) clear();
    else dispatch_sync(self.audioCaptureQueue, clear);
}

- (void)invalidateCompressionSession:(VTCompressionSessionRef)session {
    if (!session) return;
    VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
    VTCompressionSessionInvalidate(session);
    CFRelease(session);
}

- (NSArray<HARTSPServer *> *)activeServers {
    NSMutableArray<HARTSPServer *> *servers = [NSMutableArray array];
    if (self.primaryRTSPServer) [servers addObject:self.primaryRTSPServer];
    if (self.secondaryRTSPServer) [servers addObject:self.secondaryRTSPServer];
    return servers;
}

+ (BOOL)shouldStopForTrigger:(HAStreamingStopTrigger)trigger {
    return trigger >= HAStreamingStopTriggerUser && trigger <= HAStreamingStopTriggerCaptureInterrupted;
}

- (void)resign:(NSNotification *)notification { (void)notification; [self stopWithTrigger:HAStreamingStopTriggerAppWillResignActive error:nil]; }
- (void)background:(NSNotification *)notification { (void)notification; [self stopWithTrigger:HAStreamingStopTriggerAppDidEnterBackground error:nil]; }
- (void)active:(NSNotification *)notification {
    (void)notification;
    if ((self.isCapturing || self.streaming) && ![self authorized]) {
        [self stopWithTrigger:HAStreamingStopTriggerPermissionLost error:[self error:@"Camera or microphone permission was removed."]];
    }
}
- (void)auth:(NSNotification *)notification {
    (void)notification;
    HAAuthManager *auth = [HAAuthManager sharedManager];
    BOOL identityChanged = auth.authenticationRevision != self.observedAuthenticationRevision ||
                           auth.isDemoMode != self.observedDemoMode;
    self.observedAuthenticationRevision = auth.authenticationRevision;
    self.observedDemoMode = auth.isDemoMode;
    if (!auth.isConfigured) {
        [[HACameraRegistrationManager sharedManager] cancelRegistration];
        [self stopWithTrigger:HAStreamingStopTriggerLogout error:nil];
        return;
    }
    if (auth.isDemoMode) {
        [[HACameraRegistrationManager sharedManager] cancelRegistration];
        return;
    }
    if (!identityChanged) return;

    [[HACameraRegistrationManager sharedManager] cancelRegistration];
    if (!self.streaming || ![HADeviceIntegrationManager sharedManager].enabled) return;

    NSError *credentialError = nil;
    HARTSPCredentials *credentials = [[HARTSPCredentialManager sharedManager]
        credentialsWithError:&credentialError];
    if (!credentials) {
        HALogW(@"localstream", @"Camera registration did not restart after the Home Assistant account changed: %@",
               credentialError.localizedDescription);
        return;
    }
    [[HACameraRegistrationManager sharedManager]
        ensureCameraEntriesForStreamURLs:self.streamURLs
        deviceName:[HADeviceRegistration sharedManager].deviceName
        username:credentials.username
        password:credentials.password
        credentialRevision:credentials.revision
        framesPerSecond:self.targetFrameRate
        completion:^(BOOL success, NSError *error) {
            if (!success) {
                HALogW(@"localstream", @"Camera registration after the Home Assistant account changed was skipped: %@",
                       error.localizedDescription);
            }
        }];
}
- (void)interrupted:(NSNotification *)notification {
    if (notification.object == self.captureSession) {
        [self stopWithTrigger:HAStreamingStopTriggerCaptureInterrupted error:[self error:@"Camera or microphone capture was interrupted."]];
    }
}
- (BOOL)authorized {
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized &&
           [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized;
}

- (AVCaptureVideoOrientation)currentVideoOrientation {
    UIInterfaceOrientation interfaceOrientation = UIInterfaceOrientationUnknown;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            interfaceOrientation = ((UIWindowScene *)scene).interfaceOrientation;
            break;
        }
    }
    if (interfaceOrientation == UIInterfaceOrientationUnknown) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        interfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
    }
    switch (interfaceOrientation) {
        case UIInterfaceOrientationPortrait: return AVCaptureVideoOrientationPortrait;
        case UIInterfaceOrientationPortraitUpsideDown: return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft: return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight: return AVCaptureVideoOrientationLandscapeRight;
        default: return self.captureOrientation ?: AVCaptureVideoOrientationPortrait;
    }
}

- (void)applyVideoOrientationToOutputs {
    self.captureOrientation = [self currentVideoOrientation];
    NSArray<AVCaptureVideoDataOutput *> *outputs = @[
        self.frontVideoOutput ?: (id)[NSNull null],
        self.rearVideoOutput ?: (id)[NSNull null],
    ];
    for (id candidate in outputs) {
        if (candidate == [NSNull null]) continue;
        AVCaptureConnection *connection = [(AVCaptureVideoDataOutput *)candidate connectionWithMediaType:AVMediaTypeVideo];
        if (connection.isVideoOrientationSupported) connection.videoOrientation = self.captureOrientation;
    }
}

- (void)orientationChanged:(NSNotification *)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger generation = ++self.orientationChangeGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != self.orientationChangeGeneration) return;
            AVCaptureVideoOrientation orientation = [self currentVideoOrientation];
            if (orientation == self.captureOrientation) return;
            self.captureOrientation = orientation;
            if (self.isCapturing && self.streamClientCount > 0) {
                [self restartCapturePreservingClients];
            } else {
                [self applyVideoOrientationToOutputs];
            }
        });
    });
}

#pragma mark - Network address

- (NSString *)localIPv4 {
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return nil;
    NSString *wifiAddress = nil;
    for (struct ifaddrs *interface = list; interface; interface = interface->ifa_next) {
        if (!interface->ifa_addr || interface->ifa_addr->sa_family != AF_INET) continue;
        if ((interface->ifa_flags & IFF_LOOPBACK) || !(interface->ifa_flags & IFF_UP)) continue;
        struct sockaddr_in *socketAddress = (struct sockaddr_in *)interface->ifa_addr;
        uint32_t address = ntohl(socketAddress->sin_addr.s_addr);
        if (address == INADDR_ANY || (address & 0xFFFF0000) == 0xA9FE0000) continue;
        char host[INET_ADDRSTRLEN];
        if (!inet_ntop(AF_INET, &socketAddress->sin_addr, host, sizeof(host))) continue;
        NSString *value = [NSString stringWithUTF8String:host];
        NSString *name = interface->ifa_name ? [NSString stringWithUTF8String:interface->ifa_name] : @"";
        BOOL isPrivate = (address & 0xFF000000) == 0x0A000000 ||
                         (address & 0xFFF00000) == 0xAC100000 ||
                         (address & 0xFFFF0000) == 0xC0A80000;
        if ([name isEqualToString:@"en0"] && isPrivate) { wifiAddress = value; break; }
    }
    freeifaddrs(list);
    // Do not fall back to cellular, VPN, CoreDevice, USB, or other host-side
    // adapters. The user can act on the displayed URL only when en0 is local.
    NSString *selected = wifiAddress;
    if (selected.length) HALogI(@"localstream", @"Selected LAN address %@ for the RTSP listener.", selected);
    return selected;
}

#pragma mark - Errors and notifications

- (void)captureError:(NSString *)description {
    HALogE(@"localstream", @"%@", description);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopWithTrigger:HAStreamingStopTriggerCaptureInterrupted error:[self error:description]];
    });
}

- (NSError *)error:(NSString *)description {
    return [NSError errorWithDomain:HAStreamingManagerErrorDomain code:1
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)finish:(void (^)(BOOL, NSError *))completion ok:(BOOL)ok error:(NSError *)error {
    if (completion) completion(ok, error);
}

- (void)post:(NSError *)error {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (error) userInfo[HAStreamingManagerErrorKey] = error;
    [[NSNotificationCenter defaultCenter] postNotificationName:HAStreamingManagerStateDidChangeNotification
                                                        object:self userInfo:userInfo];
}

@end
