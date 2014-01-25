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


@interface ViewController : UIViewController {
    AVAudioRecorder *recorder;
    NSTimer *levelTimer;
    double lowPassFiltered;
}
@property (weak, nonatomic) IBOutlet UILabel *avgInput;
@property (weak, nonatomic) IBOutlet UILabel *peakInput;
@property (weak, nonatomic) IBOutlet UILabel *lowpassInput;
@property (weak, nonatomic) IBOutlet UILabel *inputSource;
@property (weak, nonatomic) IBOutlet UISwitch *headsetSwitch;

-(void) levelTimerCallBack:(NSTimer *) timer;
-(BOOL) isHeadsetPluggedIn;
- (IBAction)flippedHeadset:(id)sender;

@end
