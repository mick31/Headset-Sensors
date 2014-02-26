//
//  ToneGenerator.h
//  Headset Sensors
//
//  Created by Mick on 2/3/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioUnit/AudioUnit.h>

@interface ToneGenerator : NSObject

@property AudioComponentInstance powerTone;
@property double frequency;
@property double sampleRate;
@property double theta;

- (void)togglePowerOn:(BOOL)state;

@end
