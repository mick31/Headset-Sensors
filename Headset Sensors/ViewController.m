//
//  ViewController.m
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ViewController.h"

ViewController* audioIO;

void ToneInterruptionListener(void *inClientData, UInt32 inInterruptionState) {
	ViewController *viewController =
    (__bridge ViewController *)inClientData;
	
    // turn power off if interruption occurs
	[viewController togglePower:NO];
}

@implementation ViewController

@synthesize runningTotal = _runningTotal;
@synthesize lastBit = _lastBit;
@synthesize cutOff = _cutOff;
@synthesize inputThroughput = _inputThroughput;
@synthesize inputSource = _inputSource;
@synthesize currentBitLabel =_currentBitLabel;
@synthesize cutOffSlider = _cutOffSlider;

@synthesize sensorAlert = _sensorAlert;
@synthesize headsetSwitch = _headsetSwitch;
@synthesize volumeSlider = _volumeSlider;
@synthesize frequencyOut = _frequencyOut;
@synthesize amplitudeOut = _amplitudeOut;


- (void)viewDidLoad {
    [super viewDidLoad];
    
}

- (void)audioRouteChangeListener: (NSNotification*)notification {
    if (self.isHeadsetPluggedIn && self.headsetSwitch.on) {
        // Dismiss alert and set headsetswitch to on
        [self.sensorAlert dismissWithClickedButtonIndex:0 animated:YES];
        self.headsetSwitch.on = YES;
        [self flippedHeadset:self];
    } else if (!self.isHeadsetPluggedIn && self.headsetSwitch.on) {
        // Stop all services
        [self flippedHeadset:self];
    } else
        self.inputSource.text = @"Poop";
}


- (void)handleVolumeChanged:(id)sender{
    if (self.powerTone) self.volumeSlider.value = 1.0f;
}


// Dismiss alertview if headset is found
- (void) alertTimerCallBack:(NSTimer *) timer {
    if (self.isHeadsetPluggedIn) {
        //Disable alert Timer
        [self.alertTimer invalidate];
        self.alertTimer = nil;
        
        // Dismiss alert and set headsetswitch to on
        [self.sensorAlert dismissWithClickedButtonIndex:0 animated:YES];
        self.headsetSwitch.on = YES;
        
        // Call flippHeadset to start transmission functionallity
        [self flippedHeadset:self];
    }
}

- (void)secondTimerCallBack:(NSTimer *)timer {
    self.inputThroughput.text = [NSString stringWithFormat:@"%d", self.runningTotal];
    self.runningTotal = 0;
    NSLog(@"                    One Second");
}

- (void)alertView:(SDCAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        case 0:
            // Set switch to off and change input label text
            self.headsetSwitch.on = NO ;
            self.inputSource.text = @"None";
            
            //Disable sliders
            self.cutOffSlider.userInteractionEnabled = NO;
            self.cutOffSlider.tintColor = [UIColor grayColor];
            self.timeIntervalSlider.userInteractionEnabled = NO;
            self.timeIntervalSlider.tintColor = [UIColor grayColor];
            break;
        case 1:
            // Start level timer
            self.levelTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
            self.secondTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(secondTimerCallBack:) userInfo:nil repeats:YES];
            
            // Change input label text
            self.inputSource.text = @"Mic";
            
            //Enable sliders
            self.cutOffSlider.userInteractionEnabled = YES;
            self.cutOffSlider.tintColor = [UIColor greenColor];
            self.timeIntervalSlider.userInteractionEnabled = YES;
            self.timeIntervalSlider.tintColor = [UIColor greenColor];
            break;
        default:
            NSLog(@"Blowing It: Alert not handled");
            break;
    }
    
    //Disable alert Timer
    [self.alertTimer invalidate];
    self.alertTimer = nil;
}


- (BOOL)isHeadsetPluggedIn {
    NSArray *outputs = [[AVAudioSession sharedInstance] currentRoute].outputs;
    NSString *portNameOut = [[outputs objectAtIndex:0] portName];
    NSArray *inputs = [[AVAudioSession sharedInstance] currentRoute].inputs;
    NSString *portNameIn = [[inputs objectAtIndex:0] portName];
    
    /* Known routes-
         Headset Microphone
         Headphones
         iPhone Microphone
         Receiver
    */
    
    /*************
     *** Debug:
     ***    Shows current audio in/out routes iDevice
     *************/
    //NSLog(@"%@", portNameOut);
    //NSLog(@"%@", portNameIn);
    
    if ([portNameOut isEqualToString:@"Headphones"] && [portNameIn isEqualToString:@"Headset Microphone"])
        return YES;
    
    return NO;
}

- (IBAction)flippedHeadset:(id)sender {
    if (self.headsetSwitch.on && self.isHeadsetPluggedIn) {
        // Start samplers
        self.levelTimer = [NSTimer scheduledTimerWithTimeInterval:self.timerInterval target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
        self.secondTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(secondTimerCallBack:) userInfo:nil repeats:YES];
        
        // Start Power Tone
        [self togglePower:YES];
        
        //Enable sliders
        self.timeIntervalSlider.userInteractionEnabled = YES;
        self.timeIntervalSlider.tintColor = [UIColor greenColor];
        self.cutOffSlider.userInteractionEnabled = YES;
        self.cutOffSlider.tintColor = [UIColor greenColor];
    } else if (!self.headsetSwitch.on){
        // Stop samplers
        [self.levelTimer invalidate];
        self.levelTimer = nil;
        [self.secondTimer invalidate];
        self.secondTimer = nil;
        
        // Change input text
        self.inputSource.text = @"None";
        
        // Stop Power Tone
        [self togglePower:NO];
        
        //Disable sliders
        self.timeIntervalSlider.userInteractionEnabled = NO;
        self.timeIntervalSlider.tintColor = [UIColor grayColor];
        self.cutOffSlider.userInteractionEnabled = NO;
        self.cutOffSlider.tintColor = [UIColor grayColor];
    } else {
        // Stop samplers
        [self.levelTimer invalidate];
        self.levelTimer = nil;
        [self.secondTimer invalidate];
        self.secondTimer = nil;
        
        // Stop Power Tone
        [self togglePower:NO];
        
        // Setup image for Alert View
        UIImageView *alertImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"GSF_Insert_sensor_alert-v2.png"]];
        
        // Setup Alert View
        self.sensorAlert =
        [[SDCAlertView alloc]
         initWithTitle:@"No Sensor"
         message:@"Please insert the GSF sensor to collect this data."
         delegate:self
         cancelButtonTitle:nil
         otherButtonTitles:@"Cancel", @"Use Mic", nil];
        
        [alertImageView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [self.sensorAlert.contentView addSubview:alertImageView];
        [alertImageView sdc_horizontallyCenterInSuperview];
        [self.sensorAlert.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[alertImageView]|"
                                                                                             options:0
                                                                                             metrics:nil
                                                                                               views:NSDictionaryOfVariableBindings(alertImageView)]];
        
        // Alert Callback Setup
        self.alertTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(alertTimerCallBack:) userInfo:nil repeats:YES];
        
        [self.sensorAlert show];
    }
}

- (IBAction)timeSliderChange:(id)sender {
    self.timerInterval = self.timeIntervalSlider.value;
    self.timeIntervalLabel.text = [NSString stringWithFormat:@"%3.2f", self.timerInterval*1000];
    
    // Stop samplers
    [self.levelTimer invalidate];
    self.levelTimer = nil;
    [self.secondTimer invalidate];
    self.secondTimer = nil;
    
    // Start samplers
    self.levelTimer = [NSTimer scheduledTimerWithTimeInterval:self.timerInterval target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
    self.secondTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(secondTimerCallBack:) userInfo:nil repeats:YES];
}

- (IBAction)cutOffSliderChange:(id)sender {
    self.cutOff = self.cutOffSlider.value;
    self.cutOffLabel.text = [NSString stringWithFormat:@"%3.3f", self.cutOff];
}



- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
