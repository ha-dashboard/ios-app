#import <Foundation/Foundation.h>

extern NSString *const HAStreamingManagerStateDidChangeNotification;
extern NSString *const HAStreamingManagerErrorKey;

typedef NS_ENUM(NSInteger, HAStreamingStopTrigger) {
    HAStreamingStopTriggerUser, HAStreamingStopTriggerFeatureDisabled,
    HAStreamingStopTriggerAppWillResignActive, HAStreamingStopTriggerAppDidEnterBackground,
    HAStreamingStopTriggerLogout, HAStreamingStopTriggerPermissionLost,
    HAStreamingStopTriggerServerFailure, HAStreamingStopTriggerCaptureInterrupted,
};

typedef NS_ENUM(NSInteger, HAStreamingCameraMode) {
    HAStreamingCameraModeFront = 0,
    HAStreamingCameraModeRear = 1,
    HAStreamingCameraModeBoth = 2,
};

/// Foreground-only local H.264/AAC source for Home Assistant. It contains its
/// own RTSP listener; no relay, recording, remote start, or cloud service.
@interface HAStreamingManager : NSObject
@property (nonatomic, readonly) BOOL featureEnabled;
@property (nonatomic, readonly) BOOL configured;
@property (nonatomic, readonly, getter=isCapturing) BOOL capturing;
@property (nonatomic, readonly) BOOL streaming;
@property (nonatomic, readonly) BOOL supported;
@property (nonatomic, copy, readonly) NSString *streamURL;
@property (nonatomic, copy, readonly) NSString *secondaryStreamURL;
@property (nonatomic, copy, readonly) NSArray<NSString *> *streamURLs;
@property (nonatomic, readonly) NSUInteger streamClientCount;
@property (nonatomic, readonly) NSUInteger streamConnectionCount;
@property (nonatomic, readonly) NSUInteger streamPlayingClientCount;
@property (nonatomic, readonly) BOOL frontCameraAvailable;
@property (nonatomic, readonly) BOOL rearCameraAvailable;
@property (nonatomic, readonly) BOOL multiCamSupported;
@property (nonatomic, readonly) HAStreamingCameraMode cameraMode;
@property (nonatomic, readonly) float qualityScale;
@property (nonatomic, copy, readonly) NSString *qualityDescription;
/// Frame rate of the currently selected device-quality profile.
@property (nonatomic, readonly) NSInteger targetFrameRate;
@property (nonatomic, readonly) BOOL useRearCamera;
+ (instancetype)sharedManager;
- (BOOL)setFeatureEnabled:(BOOL)enabled error:(NSError **)error;
- (BOOL)setCameraMode:(HAStreamingCameraMode)cameraMode error:(NSError **)error;
- (BOOL)setQualityScale:(float)qualityScale error:(NSError **)error;
- (NSString *)qualityDescriptionForScale:(float)qualityScale;
- (void)setUseRearCamera:(BOOL)useRearCamera;
- (void)clearLocalStreamConfiguration;
- (void)armLocalStreamWithCompletion:(void (^)(BOOL success, NSError *error))completion;
/// Rotates the local credential and re-arms the protected listener. Completion
/// does not wait for Home Assistant; when registration is enabled, camera-entry
/// reconciliation starts afterward and may continue retrying asynchronously.
- (void)rotateStreamCredentialWithCompletion:(void (^)(BOOL success, NSError *error))completion;
- (void)stopWithTrigger:(HAStreamingStopTrigger)trigger error:(NSError *)error;
+ (BOOL)shouldStopForTrigger:(HAStreamingStopTrigger)trigger;
@end
