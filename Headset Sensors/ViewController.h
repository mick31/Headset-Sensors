//
//  ViewController.h
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVFoundation/AVAudioSession.h>
#import <CoreAudio/CoreAudioTypes.h>

@import MapKit;
#import <SDCAlertView.h>
#import <UIView+SDCAutoLayout.h>


@interface ViewController : UIViewController

// input properties
@property AVAudioRecorder *recorder;
@property NSTimer *levelTimer;
@property double lowPassFiltered;
@property (weak, nonatomic) IBOutlet UILabel *avgInput;
@property (weak, nonatomic) IBOutlet UILabel *peakInput;
@property (weak, nonatomic) IBOutlet UILabel *lowpassInput;
@property (weak, nonatomic) IBOutlet UILabel *inputSource;
@property (weak, nonatomic) IBOutlet UISwitch *headsetSwitch;

// output properties
@property AudioComponentInstance powerTone;
@property double frequency;
@property double amplitude;
@property double sampleRate;
@property double theta;
@property (weak, nonatomic) IBOutlet UISlider *frequencySlider;
@property (weak, nonatomic) IBOutlet UILabel *frequencyOut;
@property (weak, nonatomic) IBOutlet UISlider *amplitudeSlider;
@property (weak, nonatomic) IBOutlet UILabel *amplitudeOut;

// function prototypes
- (void)levelTimerCallBack:(NSTimer *) timer;
- (BOOL)isHeadsetPluggedIn;
- (IBAction)flippedHeadset:(id)sender;

- (IBAction)frequencySliderChange:(id)sender;
- (IBAction)amplitudeSliderChange:(id)sender;
- (void)togglePower:(BOOL)powerOn;

@end
