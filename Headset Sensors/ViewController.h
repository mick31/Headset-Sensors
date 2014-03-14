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
#import <MediaPlayer/MPMusicPlayerController.h>
#import <MediaPlayer/MPVolumeView.h>
#import <AudioToolbox/AudioToolbox.h>

@import MapKit;
#import <SDCAlertView.h>
#import <UIView+SDCAutoLayout.h>


@interface ViewController : UIViewController

// input properties
@property AVAudioRecorder *recorder;
@property NSTimer *levelTimer;
@property NSTimer *alertTimer;
@property NSTimer *secondTimer;
@property double timerInterval;
@property int runningTotal;
@property int lastBit;
@property double cutOff;
@property (weak, nonatomic) IBOutlet UILabel *inputSource;
@property (weak, nonatomic) IBOutlet UILabel *inputThroughput;
@property (weak, nonatomic) IBOutlet UILabel *currentBitLabel;
@property (weak, nonatomic) IBOutlet UISwitch *headsetSwitch;
@property SDCAlertView *sensorAlert;
@property (weak, nonatomic) IBOutlet UILabel *timeIntervalLabel;
@property (weak, nonatomic) IBOutlet UISlider *timeIntervalSlider;
@property (weak, nonatomic) IBOutlet UILabel *cutOffLabel;
@property (weak, nonatomic) IBOutlet UISlider *cutOffSlider;

// output properties
@property AudioComponentInstance powerTone;
@property double frequency;
@property double amplitude;
@property double sampleRate;
@property double theta;
@property (nonatomic, strong) UISlider *volumeSlider;
@property (weak, nonatomic) IBOutlet UILabel *frequencyOut;
@property (weak, nonatomic) IBOutlet UILabel *amplitudeOut;

// function prototypes
- (void)levelTimerCallBack:(NSTimer *) timer;
- (void)alertTimerCallBack:(NSTimer *) timer;
- (void)secondTimerCallBack:(NSTimer *) timer;
- (BOOL)isHeadsetPluggedIn;
- (IBAction)flippedHeadset:(id)sender;
- (IBAction)timeSliderChange:(id)sender;
- (IBAction)cutOffSliderChange:(id)sender;

- (void)togglePower:(BOOL)powerOn;

@end

// global audioIO variable to be accessed in callbacks
extern ViewController* audioIO;
