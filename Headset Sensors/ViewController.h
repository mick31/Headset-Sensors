//
//  ViewController.h
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>


@interface ViewController : UIViewController {
    AVAudioRecorder *recorder;
    NSTimer *levelTimer;
    double lowPassFiltered;
}

-(void) levelTimerCallBack:(NSTimer *) timer;

@end
