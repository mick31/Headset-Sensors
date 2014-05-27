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

@class GSFSensorIOController;

@protocol GSFSensorIOControllerDelgate <NSObject>

- (void) endCollection:(GSFSensorIOController *) sensorIOController;
- (void) popVCSensorIO:(GSFSensorIOController *) sensorIOController;

@end


// Public interface
@interface GSFSensorIOController : NSObject

// Public control properties
@property SDCAlertView *sensorAlert;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (nonatomic) int audioChangeReason;

// Public function prototypes
- (id) initWithView: (UIView *) view;       // Initializes sensor object. Takes the calling UIViews view for alert messages
- (void) monitorSensors: (BOOL) enable;     // Starts the power and communication with micro
- (void) checkAudioStatus;                  // Checks for changes in audio conditions that could disturb collection process.
- (NSMutableArray*) collectSensorData;      // Returns an array of sensor readings

// Delegate to limit number of sensor packets collected
@property (nonatomic, weak) id collectionDelegate;
- (void) collectionCompleteDelegate;

@property (nonatomic, weak) id popVCSensorIODelegate;

@end
