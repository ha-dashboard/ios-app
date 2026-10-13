#import "HAEntity+MediaPlayer.h"

NSString *const HAMediaControlTurnOn        = @"turn_on";
NSString *const HAMediaControlTurnOff       = @"turn_off";
NSString *const HAMediaControlShuffle       = @"shuffle_set";
NSString *const HAMediaControlPreviousTrack = @"media_previous_track";
NSString *const HAMediaControlPlay          = @"media_play";
NSString *const HAMediaControlPause         = @"media_pause";
NSString *const HAMediaControlStop          = @"media_stop";
NSString *const HAMediaControlPlayPause     = @"media_play_pause";
NSString *const HAMediaControlNextTrack     = @"media_next_track";
NSString *const HAMediaControlRepeat        = @"repeat_set";
NSString *const HAMediaControlVolumeMute    = @"volume_mute";
NSString *const HAMediaControlVolumeDown    = @"volume_down";
NSString *const HAMediaControlVolumeUp      = @"volume_up";
NSString *const HAMediaControlVolumeSet     = @"volume_set";
NSString *const HAMediaControlSelectSource  = @"select_source";

@implementation HAEntity (MediaPlayer)

- (NSNumber *)mediaDuration {
    return HAAttrNumber(self.attributes, HAAttrMediaDuration);
}

- (NSNumber *)mediaPosition {
    return HAAttrNumber(self.attributes, HAAttrMediaPosition);
}

- (NSString *)mediaAppName {
    return HAAttrString(self.attributes, HAAttrAppName);
}

- (NSString *)mediaSoundMode {
    return HAAttrString(self.attributes, HAAttrSoundMode);
}

- (NSArray<NSString *> *)mediaSoundModes {
    return HAAttrArray(self.attributes, HAAttrSoundModeList) ?: @[];
}

- (NSString *)mediaSource {
    return HAAttrString(self.attributes, @"source");
}

- (NSArray<NSString *> *)mediaSourceList {
    return HAAttrArray(self.attributes, @"source_list") ?: @[];
}

- (BOOL)mediaShuffle {
    return HAAttrBool(self.attributes, @"shuffle", NO);
}

- (NSString *)mediaRepeat {
    return HAAttrString(self.attributes, @"repeat") ?: @"off";
}

#pragma mark - Controls

+ (BOOL)mediaPlayerStateIsActive:(NSString *)state {
    if (state.length == 0) return NO;
    return ![state isEqualToString:@"off"] && ![state isEqualToString:@"standby"] &&
           ![state isEqualToString:@"unavailable"] && ![state isEqualToString:@"unknown"];
}

+ (NSArray<NSString *> *)mediaControlsForState:(NSString *)state
                             supportedFeatures:(NSInteger)features
                                    attributes:(NSDictionary *)attributes {
    if (state.length == 0 || [state isEqualToString:@"unavailable"]) return @[];

    BOOL (^supports)(HAMediaPlayerFeature) = ^BOOL(HAMediaPlayerFeature f) { return (features & f) != 0; };
    BOOL assumed = HAAttrBool(attributes, @"assumed_state", NO);

    if (![self mediaPlayerStateIsActive:state] && !assumed) {
        return supports(HAMediaPlayerFeatureTurnOn) ? @[HAMediaControlTurnOn] : @[];
    }

    NSMutableArray<NSString *> *controls = [NSMutableArray array];
    BOOL playing = [state isEqualToString:@"playing"];
    BOOL paused = [state isEqualToString:@"paused"];
    BOOL playingOrPaused = playing || paused || assumed;

    if (assumed && supports(HAMediaPlayerFeatureTurnOn)) [controls addObject:HAMediaControlTurnOn];
    if (supports(HAMediaPlayerFeatureTurnOff)) [controls addObject:HAMediaControlTurnOff];
    if (playingOrPaused && supports(HAMediaPlayerFeatureShuffleSet)) [controls addObject:HAMediaControlShuffle];
    if (playingOrPaused && supports(HAMediaPlayerFeaturePreviousTrack)) [controls addObject:HAMediaControlPreviousTrack];

    if (!assumed) {
        if (playing && (supports(HAMediaPlayerFeaturePause) || supports(HAMediaPlayerFeatureStop))) {
            [controls addObject:supports(HAMediaPlayerFeaturePause) ? HAMediaControlPause : HAMediaControlStop];
        } else if ((paused || [state isEqualToString:@"idle"]) && supports(HAMediaPlayerFeaturePlay)) {
            [controls addObject:HAMediaControlPlay];
        } else if ([state isEqualToString:@"on"] &&
                   (supports(HAMediaPlayerFeaturePlay) || supports(HAMediaPlayerFeaturePause))) {
            [controls addObject:HAMediaControlPlayPause];
        }
    } else {
        if (supports(HAMediaPlayerFeaturePlay)) [controls addObject:HAMediaControlPlay];
        if (supports(HAMediaPlayerFeaturePause)) [controls addObject:HAMediaControlPause];
        if (supports(HAMediaPlayerFeatureStop)) [controls addObject:HAMediaControlStop];
    }

    if (playingOrPaused && supports(HAMediaPlayerFeatureNextTrack)) [controls addObject:HAMediaControlNextTrack];
    if (playingOrPaused && supports(HAMediaPlayerFeatureRepeatSet)) [controls addObject:HAMediaControlRepeat];

    BOOL volumeSet = supports(HAMediaPlayerFeatureVolumeSet);
    BOOL volumeStep = supports(HAMediaPlayerFeatureVolumeStep);
    if (volumeSet || volumeStep) {
        if (supports(HAMediaPlayerFeatureVolumeMute)) [controls addObject:HAMediaControlVolumeMute];
        if (volumeStep && !volumeSet) {
            [controls addObject:HAMediaControlVolumeDown];
            [controls addObject:HAMediaControlVolumeUp];
        }
        if (volumeSet) [controls addObject:HAMediaControlVolumeSet];
    }

    if (supports(HAMediaPlayerFeatureSelectSource) && HAAttrArray(attributes, @"source_list").count > 0) {
        [controls addObject:HAMediaControlSelectSource];
    }
    return [controls copy];
}

- (NSArray<NSString *> *)mediaControls {
    return [HAEntity mediaControlsForState:self.state
                         supportedFeatures:[self supportedFeatures]
                                attributes:self.attributes];
}

@end
