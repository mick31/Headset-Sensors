//
//  ViewController.m
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

@synthesize avgInput = _avgInput;
@synthesize peakInput = _peakInput;
@synthesize lowpassInput = _lowpassInput;
@synthesize inputSource = _inputSource;
@synthesize headsetSwitch = _headsetSwitch;

- (void)viewDidLoad
{
    [super viewDidLoad];
	
    NSURL *url = [NSURL fileURLWithPath:@"dev/null"];
    
    NSDictionary *settings =  [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                              [NSNumber numberWithInt:kAudioFormatAppleLossless], AVFormatIDKey,
                              [NSNumber numberWithInt:1], AVNumberOfChannelsKey,
                              [NSNumber numberWithInt:AVAudioQualityMax], AVEncoderAudioQualityKey,
                              nil];
    NSError *err;
    
    recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&err];
    
    if (recorder) {
        [recorder prepareToRecord];
        recorder.meteringEnabled = YES;
        [recorder record];
        levelTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
    } else
        NSLog([err description]);
}

-(void) levelTimerCallBack:(NSTimer *)timer{
    [recorder updateMeters];
    
    const double ALPHA = 0.05;
    double peakPowerForChannel = pow(10, (0.05 * [recorder peakPowerForChannel:0]));
    lowPassFiltered = ALPHA * peakPowerForChannel + (1.0 - ALPHA) * lowPassFiltered;
    
    _avgInput.text = [NSString stringWithFormat:@"%f", [recorder averagePowerForChannel:0]];
    _peakInput.text = [NSString stringWithFormat:@"%f", [recorder peakPowerForChannel:0]];
    _lowpassInput.text = [NSString stringWithFormat:@"%f", lowPassFiltered];
    
    if (self.isHeadsetPluggedIn)
        _inputSource.text = @"Headset";
    else
        _inputSource.text = @"Mic";
    
}

-(BOOL) isHeadsetPluggedIn {
    UInt32 routeSize = sizeof (CFStringRef);
    CFStringRef route;
    
    OSStatus error = AudioSessionGetProperty (kAudioSessionProperty_AudioRoute,
                                              &routeSize,
                                              &route);
    
    if (!error && (route != NULL)) {
        
        NSString* routeStr = (__bridge NSString *)route;
        
        //NSLog(routeStr);
        
        NSRange headphoneRange = [routeStr rangeOfString : @"MicrophoneWired"];
        if (headphoneRange.location != NSNotFound) {
            return YES;
        }
    }
    
    return NO;
}

- (IBAction)flippedHeadset:(id)sender {
    if (self.headsetSwitch.on) {
        AudioSessionSetProperty (kAudioSessionProperty_InputSource, sizeof(kAudioSessionInputRoute_HeadsetMic), &kAudioSessionInputRoute_HeadsetMic);
    } else {
        
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
