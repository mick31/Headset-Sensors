//
//  GSFSensorIOController.h
//  GSFDataCollecter
//
//  Created by Mick Bennett on 3/30/14.
//  Copyright (c) 2014 Michael Baptist - LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>               // Audio Session APIs
#import <MediaPlayer/MPVolumeView.h>                // For Master Volume control
#import <AudioUnit/AudioUnit.h>                     // Audio Unit access
#import <AudioToolbox/AudioToolbox.h>               // Audio unit control
#import <Accelerate/Accelerate.h>                   // DSP functions

#import <SDCAlertView.h>                            // Custom Alert View
#import <UIView+SDCAutoLayout.h>                    // Layout Control for custom Alert View

// Public interface
@interface GSFSensorIOController : NSObject

// Public control properties
@property SDCAlertView *sensorAlert;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (nonatomic) int audioChangeReason;

// Public function prototypes
- (id) init: (UIView *) view;                               // Uses idea of ONE associated view
- (void) monitorSensors: (UIView *) view : (BOOL) enable;   // Uses idea of ANY calling view
- (void) processIO: (AudioBufferList*) bufferList;
- (void) checkAudioStatus: (UIView *) view;                 // Uses idea of ANY calling view

@end
