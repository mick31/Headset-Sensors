//
//  GSFSensorIOController.h
//  GSFDataCollecter
//
//  Created by Mick Bennett on 3/30/14.
//  Copyright (c) 2014 Michael Baptist - LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>               // Audio session APIs
#import <MediaPlayer/MPVolumeView.h>                // For master volume control
#import <AudioToolbox/AudioToolbox.h>               // Audio unit control
#import <Accelerate/Accelerate.h>                   // DSP functions

#import <SDCAlertView.h>                            // Custom alert view
#import <UIView+SDCAutoLayout.h>                    // Layout Control for custom alert view

// Defined
#define kOutputBus   0
#define kInputBus  1

#ifndef min
#define min( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif

#ifndef max
#define max( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

@interface GSFSensorIOController : NSObject 

// Public control properties
@property SDCAlertView *sensorAlert;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (nonatomic) int audioChangeReason;

// Function prototypes
- (void) monitorSensors: (BOOL) enable;
- (void) processIO: (AudioBufferList*) bufferList;
- (BOOL) isSensorConnected;
- (void) addAlertViewToView:(UIView*)view :(NSInteger) changeReason;
@end
