//
//  ToneGenerator.h
//  Headset Sensors
//
//  Created by Mick on 2/3/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioUnit/AudioUnit.h>

@interface ToneGenerator : NSObject {
    AudioComponentInstance powerTone;
@public
    double frequency;
    double sampleRate;
    double theta;
}

- (void)togglePowerOn:(BOOL)state;

@end
