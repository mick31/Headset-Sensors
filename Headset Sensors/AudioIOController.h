//
//  AudioIOController.h
//  Headset Sensors
//
//  Created by Mick Bennett on 3/14/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import <MediaPlayer/MPVolumeView.h>

#ifndef max
#define max( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

#ifndef min
#define min( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif

@interface AudioIOController : NSObject

@property AudioComponentInstance inputAudioUnit;
@property AudioBuffer micBuffer;
@property AudioComponentInstance powerOutAudioUnit;
@property double frequency;
@property double amplitude;
@property double sampleRate;
@property double theta;

- (void)processInputAudio: (AudioBufferList*) bufferlist;

@end

// global audioIO variable to be accessed in callbacks
extern AudioIOController* audioIO;
