//
//  ViewController.m
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ViewController.h"

@interface ViewController () {
    ToneGenerator *powerTone;
}

@end

// Stops tone when call or notification is received
void ToneIterruptionListner(void *inClientData, UInt32 inInterruptionState) {
    ToneGenerator * tone = CFBridgingRelease(inClientData);
    
    [tone togglePowerOn:NO];
}

@implementation ViewController

@synthesize avgInput = _avgInput;
@synthesize peakInput = _peakInput;
@synthesize lowpassInput = _lowpassInput;
@synthesize inputSource = _inputSource;
@synthesize headsetSwitch = _headsetSwitch;

- (void)viewDidLoad
{
    // Input Setup
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
    } else
        NSLog(@"%@",[err description]);
    
    // Power tone setup
    powerTone.sampleRate = 44100;
    powerTone.frequency = 2000;
    OSStatus result = AudioSessionInitialize(NULL,
                                             NULL,
                                             ToneIterruptionListner,
                                             (__bridge void *)(powerTone));
	if (result == kAudioSessionNoError)
	{
        // allows for both mic and speaker output
		UInt32 sessionCategory = kAudioSessionCategory_PlayAndRecord;
		AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(sessionCategory), &sessionCategory);
	}
	AudioSessionSetActive(true);
}

- (void) sliderHandler: (UISlider *)sender {
    int x = sender.value;
    NSLog(@"Volume: %d", x);
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
    else if ([_inputSource.text isEqualToString:@"Headset"]) {
        // Stop Timer
        [timer invalidate];
        timer = nil;
        
        // Kill power Tone
        [self->powerTone togglePowerOn:NO];
        
        // Setup image for Alert View
        UIView *alertImageView = [[UIView alloc] initWithFrame:CGRectMake(20, 50, 250, 150)];
        [alertImageView setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"GSF_insert_sensor_alert.png"]]];

        
        // Setup Alert View
        SDCAlertView *noHeadsetAlertView =
                   [[SDCAlertView alloc]
                    initWithTitle:@"No Headset"
                    message:@"You need a headset you fool!"
                    delegate:self
                    cancelButtonTitle:nil
                    otherButtonTitles:@"Cancel", @"Use Mic", nil];
        [alertImageView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [noHeadsetAlertView.contentView addSubview:alertImageView];
        
        //[alertImageView sdc_pinWidthToWidthOfView:noHeadsetAlertView.contentView offset: -20];
        [alertImageView sdc_horizontallyCenterInSuperview];
        
        [noHeadsetAlertView.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[alertImageView]|"
                                                                                  options:0
                                                                                  metrics:nil
                                                                                    views:NSDictionaryOfVariableBindings(alertImageView)]];
        
        [noHeadsetAlertView show];
        
    } else
        _inputSource.text = @"Mic";
}


- (void)alertView:(SDCAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        case 0:
            self.headsetSwitch.on = NO ;
            _inputSource.text = @"None";
            NSLog(@"alertView: Cancel Made it");
            break;
        case 1:
            levelTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
            _inputSource.text = @"Mic";
            
            /*************
             *** Debug ***
             *************/
            [self->powerTone togglePowerOn:YES];
            NSLog(@"alertView: Made it");
            
            break;
        default:
            NSLog(@"Blowing It: Alert not handled");
            break;
    }
}


- (BOOL)isHeadsetPluggedIn {
    UInt32 routeSize = sizeof (CFStringRef);
    CFStringRef route;
    
    OSStatus error = AudioSessionGetProperty (kAudioSessionProperty_AudioRoute,
                                              &routeSize,
                                              &route);
    
    if (!error && (route != NULL)) {
        
        NSString* routeStr = (__bridge NSString *)route;
        
        /* Known routes-
                MicrophoneWired
                MicrophoneBuiltIn
                Headphones
                Speaker
                HeadsetInOut
                ReceiverAndMicrophone
         */
        /*************
         *** Debug ***
         *************/
        //NSLog(@"%@", routeStr);
        
        // HeadsetInOut should allow for two way communicaiton and power
        NSRange headphoneRange = [routeStr rangeOfString : @"HeadsetInOut"];
        if (headphoneRange.location != NSNotFound) {
            return YES;
        }
    }
    
    return NO;
}

- (IBAction)flippedHeadset:(id)sender {
    if (self.headsetSwitch.on && self.isHeadsetPluggedIn) {
        // Start Sampler
        levelTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
        
        // Start Power Tone
        [self->powerTone togglePowerOn:YES];
    } else if (!self.headsetSwitch.on){
        [levelTimer invalidate];
        levelTimer = nil;
        _inputSource.text = @"None";
        
        // Stop Power Tone
        [self->powerTone togglePowerOn:NO];
    } else {
        [levelTimer invalidate];
        levelTimer = nil;
        
        // Stop Power Tone
        [self->powerTone togglePowerOn:NO];
        
        /*************
         *** Debug ***
         *************/
        NSLog(@"flippedHeadset: Made it!");
        
        // Setup image for Alert View
        UIView *alertImageView = [[UIView alloc] initWithFrame:CGRectMake(20, 50, 250, 150)];
        [alertImageView setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"GSF_insert_sensor_alert.png"]]];
        
        
        // Setup Alert View
        SDCAlertView *noHeadsetAlertView =
        [[SDCAlertView alloc]
         initWithTitle:@"No Sensor"
         message:@"Please insert the GSF sensor to collect this data."
         delegate:self
         cancelButtonTitle:nil
         otherButtonTitles:@"Cancel", @"Use Mic", nil];
        [alertImageView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [noHeadsetAlertView.contentView addSubview:alertImageView];
        
        //[alertImageView sdc_pinWidthToWidthOfView:noHeadsetAlertView.contentView offset: -20];
        [alertImageView sdc_horizontallyCenterInSuperview];
        
        [noHeadsetAlertView.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[alertImageView]|"
                                                                                               options:0
                                                                                               metrics:nil
                                                                                                 views:NSDictionaryOfVariableBindings(alertImageView)]];
        [noHeadsetAlertView show];

    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
