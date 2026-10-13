#import "HAEntity.h"

/// media_player supported_features bits (HA MediaPlayerEntityFeature).
typedef NS_OPTIONS(NSInteger, HAMediaPlayerFeature) {
    HAMediaPlayerFeaturePause         = 1,
    HAMediaPlayerFeatureSeek          = 2,
    HAMediaPlayerFeatureVolumeSet     = 4,
    HAMediaPlayerFeatureVolumeMute    = 8,
    HAMediaPlayerFeaturePreviousTrack = 16,
    HAMediaPlayerFeatureNextTrack     = 32,
    HAMediaPlayerFeatureTurnOn        = 128,
    HAMediaPlayerFeatureTurnOff       = 256,
    HAMediaPlayerFeatureVolumeStep    = 1024,
    HAMediaPlayerFeatureSelectSource  = 2048,
    HAMediaPlayerFeatureStop          = 4096,
    HAMediaPlayerFeaturePlay          = 16384,
    HAMediaPlayerFeatureShuffleSet    = 32768,
    HAMediaPlayerFeatureBrowseMedia   = 131072,
    HAMediaPlayerFeatureRepeatSet     = 262144,
};

/// Media player control identifiers. Each is the media_player service the
/// control calls, except HAMediaControlPlayPause (shown for the "on" state),
/// which calls media_play_pause.
extern NSString *const HAMediaControlTurnOn;         // turn_on
extern NSString *const HAMediaControlTurnOff;        // turn_off
extern NSString *const HAMediaControlShuffle;        // shuffle_set
extern NSString *const HAMediaControlPreviousTrack;  // media_previous_track
extern NSString *const HAMediaControlPlay;           // media_play
extern NSString *const HAMediaControlPause;          // media_pause
extern NSString *const HAMediaControlStop;           // media_stop
extern NSString *const HAMediaControlPlayPause;      // media_play_pause
extern NSString *const HAMediaControlNextTrack;      // media_next_track
extern NSString *const HAMediaControlRepeat;         // repeat_set
extern NSString *const HAMediaControlVolumeMute;     // volume_mute
extern NSString *const HAMediaControlVolumeDown;     // volume_down
extern NSString *const HAMediaControlVolumeUp;       // volume_up
extern NSString *const HAMediaControlVolumeSet;      // volume_set
extern NSString *const HAMediaControlSelectSource;   // select_source

@interface HAEntity (MediaPlayer)

// Existing in HAEntity.h: mediaTitle, mediaArtist, volumeLevel, isVolumeMuted, isPlaying, isPaused, isIdle

// New
- (NSNumber *)mediaDuration;
- (NSNumber *)mediaPosition;
- (NSString *)mediaAppName;
- (NSString *)mediaSoundMode;
- (NSArray<NSString *> *)mediaSoundModes;
- (NSString *)mediaSource;
- (NSArray<NSString *> *)mediaSourceList;
- (BOOL)mediaShuffle;
- (NSString *)mediaRepeat;  // "off", "all", "one"

/// The controls a media player offers in the given state, in Home
/// Assistant's order. Mirrors the HA frontend's computeMediaControls
/// (src/data/media-player.ts, extended controls) plus the volume and source
/// rules of its more-info dialog:
/// - unavailable: nothing.
/// - off/standby/unknown (and not assumed_state): only turn_on, when TURN_ON
///   is supported.
/// - otherwise: turn_off (TURN_OFF); shuffle/previous/next/repeat while
///   playing or paused and supported; play/pause/stop per state and
///   PLAY/PAUSE/STOP; volume_mute, volume_down + volume_up (VOLUME_STEP
///   without VOLUME_SET) and volume_set when VOLUME_SET or VOLUME_STEP is
///   supported; select_source with SELECT_SOURCE and a non-empty source_list.
/// Pure: depends only on its arguments.
+ (NSArray<NSString *> *)mediaControlsForState:(NSString *)state
                             supportedFeatures:(NSInteger)features
                                    attributes:(NSDictionary *)attributes;

/// +mediaControlsForState:supportedFeatures:attributes: for this entity.
- (NSArray<NSString *> *)mediaControls;

/// YES unless the player is off, standby, unavailable or unknown — HA's
/// stateActive() for the media_player domain.
+ (BOOL)mediaPlayerStateIsActive:(NSString *)state;

@end
