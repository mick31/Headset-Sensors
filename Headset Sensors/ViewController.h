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

#import "ToneGenerator.h"

@interface ViewController : UIViewController <UIAlertViewDelegate> {
    AVAudioRecorder *recorder;
    NSTimer *levelTimer;
    double lowPassFiltered;
    IBOutlet UILabel *Foo;
}

// input properties
@property (weak, nonatomic) IBOutlet UILabel *avgInput;
@property (weak, nonatomic) IBOutlet UILabel *peakInput;
@property (weak, nonatomic) IBOutlet UILabel *lowpassInput;
@property (weak, nonatomic) IBOutlet UILabel *inputSource;
@property (weak, nonatomic) IBOutlet UISwitch *headsetSwitch;

// output properties
@property (weak, nonatomic) IBOutlet UILabel *freqOut;
@property (weak, nonatomic) IBOutlet UISlider *freqSlider;
@property (weak, nonatomic) IBOutlet UILabel *ampOut;
@property (weak, nonatomic) IBOutlet UISlider *ampSlider;

// function prototypes
- (void)levelTimerCallBack:(NSTimer *) timer;
- (BOOL)isHeadsetPluggedIn;
- (IBAction)flippedHeadset:(id)sender;
- (void)sliderHandler: (UISlider *)sender;

@end
