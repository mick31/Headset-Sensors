//
//  ViewController.m
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ViewController.h"

ViewController* audioIO;

void checkStatus(int status){
	if (status) {
		printf("Status not 0! %d\n", status);
//        exit(1);
	}
}

static OSStatus renderToneCallback(void *inRefCon,
                                   AudioUnitRenderActionFlags 	*ioActionFlags,
                                   const AudioTimeStamp 		*inTimeStamp,
                                   UInt32 						inBusNumber,
                                   UInt32 						inNumberFrames,
                                   AudioBufferList              *ioData) {
    
	// Get the tone parameters out of the view controller
	ViewController *viewController =
    (__bridge ViewController *)inRefCon;
	double theta = viewController.theta;
	double theta_increment = 2.0 * M_PI * viewController.frequency / viewController.sampleRate;
    
	// This is a mono tone generator so we only need the first buffer
	const int channel = 0;
	Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;
	
	// Generate the samples
	for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
		buffer[frame] = sin(theta) * viewController.amplitude;
		
		theta += theta_increment;
		if (theta > 2.0 * M_PI) {
			theta -= 2.0 * M_PI;
		}
	}
	
	// Store the theta back in the view controller
	viewController.theta = theta;
    
	return noErr;
}

void ToneInterruptionListener(void *inClientData, UInt32 inInterruptionState) {
	ViewController *viewController =
    (__bridge ViewController *)inClientData;
	
    // turn power off if interruption occurs
	[viewController togglePower:NO];
}

@implementation ViewController

@synthesize recorder = _recorder;
@synthesize levelTimer = _levelTimer;
@synthesize alertTimer = _alertTimer;
@synthesize timerInterval = _timerInterval;
@synthesize runningTotal = _runningTotal;
@synthesize lastBit = _lastBit;
@synthesize inputThroughput = _inputThroughput;
@synthesize inputSource = _inputSource;
@synthesize headsetSwitch = _headsetSwitch;
@synthesize currentBitLabel =_currentBitLabel;
@synthesize sensorAlert = _sensorAlert;
@synthesize timeIntervalLabel = _timeIntervalLabel;
@synthesize timeIntervalSlider =_timeIntervalSlider;

@synthesize powerTone = _powerTone;
@synthesize frequency = _frequency;
@synthesize amplitude = _amplitude;
@synthesize sampleRate = _sampleRate;
@synthesize theta = _theta;
@synthesize volumeSlider = _volumeSlider;
@synthesize frequencySlider = _frequencySlider;
@synthesize frequencyOut = _frequencyOut;
@synthesize amplitudeSlider = _amplitudeSlider;
@synthesize amplitudeOut = _amplitudeOut;


- (void)viewDidLoad {
    [super viewDidLoad];
	
    // Set up AVAudioSession
    AVAudioSession *session = [AVAudioSession sharedInstance];
    BOOL success;
    NSError *error;
    
    success = [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    
	if (!success) NSLog(@"ERROR viewDidLoad: AVAudioSession failed overrideOutputAudio- %@", error);
    
    success = [session setActive:YES error:&error];
    if(!success) NSLog(@"ERROR viewDidLoad: AVAudioSession failed activating- %@", error);
    else NSLog(@"audioSession active");
    
    // MIC Input Setup
    NSURL *url = [NSURL fileURLWithPath:@"dev/null"];
    
    NSDictionary *settings =  [NSDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithFloat:44100.0],
                               AVSampleRateKey,
                               [NSNumber numberWithInt:kAudioFormatAppleLossless],
                               AVFormatIDKey,
                               [NSNumber numberWithInt:1],
                               AVNumberOfChannelsKey,
                               [NSNumber numberWithInt:AVAudioQualityMax],
                               AVEncoderAudioQualityKey,
                               nil];
    NSError *err;
    
    _recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&err];
    
    if (_recorder) {
        [_recorder prepareToRecord];
        _recorder.meteringEnabled = YES;
        [_recorder record];
    } else
        NSLog(@"%@",[err description]);
    
    _timerInterval = 0.03;
    _runningTotal = 0;
    _lastBit = 0;
    
    // Power tone setup
    _sampleRate = 44100;
    _frequency = 5000;
    _amplitude = 0.0;
    
    // Setup master volume controller
    MPVolumeView *volumeView = [MPVolumeView new];
    volumeView.showsRouteButton = NO;
    volumeView.showsVolumeSlider = NO;
    [self.view addSubview:volumeView];
    
    __weak __typeof(self)weakSelf = self;
    [[volumeView subviews] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[UISlider class]]) {
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            strongSelf.volumeSlider = obj;
            *stop = YES;
        }
    }];
    
    [self.volumeSlider addTarget:self action:@selector(handleVolumeChanged:) forControlEvents:UIControlEventValueChanged];
}


- (void)createToneUnit {
	// Configure the search parameters to find the default playback output unit
	// (called the kAudioUnitSubType_RemoteIO on iOS but
	// kAudioUnitSubType_DefaultOutput on Mac OS X)
	AudioComponentDescription defaultOutputDescription;
	defaultOutputDescription.componentType = kAudioUnitType_Output;
	defaultOutputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
	defaultOutputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	defaultOutputDescription.componentFlags = 0;
	defaultOutputDescription.componentFlagsMask = 0;
	
	// Get the default playback output unit
	AudioComponent defaultOutput = AudioComponentFindNext(NULL, &defaultOutputDescription);
	NSAssert(defaultOutput, @"Can't find default output");
	
	// Create a new unit based on this that we'll use for output
	OSErr err = AudioComponentInstanceNew(defaultOutput, &_powerTone);
	NSAssert1(_powerTone, @"Error creating unit: %hd", err);
	
	// Set our tone rendering function on the unit
	AURenderCallbackStruct input;
	input.inputProc = renderToneCallback;
	input.inputProcRefCon = (__bridge void *)(self);
	err = AudioUnitSetProperty(_powerTone,
                               kAudioUnitProperty_SetRenderCallback,
                               kAudioUnitScope_Input,
                               0,
                               &input,
                               sizeof(input));
	NSAssert1(err == noErr, @"Error setting callback: %hd", err);
	
	// Set the format to 32 bit, single channel, floating point, linear PCM
	const int four_bytes_per_float = 4;
	const int eight_bits_per_byte = 8;
	AudioStreamBasicDescription streamFormat;
	streamFormat.mSampleRate = _sampleRate;
	streamFormat.mFormatID = kAudioFormatLinearPCM;
	streamFormat.mFormatFlags =
    kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
	streamFormat.mBytesPerPacket = four_bytes_per_float;
	streamFormat.mFramesPerPacket = 1;
	streamFormat.mBytesPerFrame = four_bytes_per_float;
	streamFormat.mChannelsPerFrame = 1;
	streamFormat.mBitsPerChannel = four_bytes_per_float * eight_bits_per_byte;
	err = AudioUnitSetProperty (_powerTone,
                                kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Input,
                                0,
                                &streamFormat,
                                sizeof(AudioStreamBasicDescription));
	NSAssert1(err == noErr, @"Error setting stream format: %hd", err);
}

- (void)togglePower:(BOOL)powerOn {
	if (!powerOn) {
        // Set Master Volume to 50%
        self.volumeSlider.value = 0.5f;
        
		// Stop and release power tone
        AudioOutputUnitStop(self.powerTone);
		AudioUnitUninitialize(self.powerTone);
		AudioComponentInstanceDispose(self.powerTone);
		self.powerTone = nil;
	} else {
		[self createToneUnit];
		
		// Stop changing parameters on the unit
		OSErr err = AudioUnitInitialize(self.powerTone);
		NSAssert1(err == noErr, @"Error initializing unit: %hd", err);
		
        // Set Master Volume to 100%
        self.volumeSlider.value = 1.0f;
        
		// Start playback
		err = AudioOutputUnitStart(self.powerTone);
		NSAssert1(err == noErr, @"Error starting unit: %hd", err);
	}
}

- (void)handleVolumeChanged:(id)sender{
    if (self.powerTone) self.volumeSlider.value = 1.0f;
}

-(void) levelTimerCallBack:(NSTimer *)timer {
    [self.recorder updateMeters];
    
    double avgDBInput = [self.recorder averagePowerForChannel:0];
    double peakDBInput = [self.recorder peakPowerForChannel:0];
    int currentBit = 0;
    
    if (avgDBInput > -1.0f && peakDBInput > 0.5f) {
        currentBit = 1;
    }
    
    self.currentBitLabel.text = [NSString stringWithFormat:@"%d", currentBit];
    
    if (currentBit != self.lastBit) {
        self.runningTotal++;
        self.lastBit = currentBit;
    }
    
    if (self.isHeadsetPluggedIn)
        self.inputSource.text = @"Headset";
    else if ([self.inputSource.text isEqualToString:@"Headset"]) {
        // Stop Timer
        [timer invalidate];
        timer = nil;
        
        // Kill power Tone
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
        
        // Show Alert
        [self.sensorAlert show];
    } else
        self.inputSource.text = @"Mic";
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
    self.inputThroughput.text = [NSString stringWithFormat:@"%3d", self.runningTotal];
    self.runningTotal = 0;
}

- (void)alertView:(SDCAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        case 0:
            // Set switch to off and change input label text
            self.headsetSwitch.on = NO ;
            self.inputSource.text = @"None";
            
            //Disable sliders
            self.frequencySlider.userInteractionEnabled = NO;
            self.frequencySlider.tintColor = [UIColor grayColor];
            self.amplitudeSlider.userInteractionEnabled = NO;
            self.amplitudeSlider.tintColor = [UIColor grayColor];
            break;
        case 1:
            // Start level timer
            self.levelTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
            self.secondTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(secondTimerCallBack:) userInfo:nil repeats:YES];
            
            // Change input label text
            self.inputSource.text = @"Mic";
            
            //Disable sliders
            self.frequencySlider.userInteractionEnabled = NO;
            self.frequencySlider.tintColor = [UIColor grayColor];
            self.amplitudeSlider.userInteractionEnabled = NO;
            self.amplitudeSlider.tintColor = [UIColor grayColor];
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
        self.frequencySlider.userInteractionEnabled = YES;
        self.frequencySlider.tintColor = [UIColor greenColor];
        self.amplitudeSlider.userInteractionEnabled = YES;
        self.amplitudeSlider.tintColor = [UIColor greenColor];
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
        self.frequencySlider.userInteractionEnabled = NO;
        self.frequencySlider.tintColor = [UIColor grayColor];
        self.amplitudeSlider.userInteractionEnabled = NO;
        self.amplitudeSlider.tintColor = [UIColor grayColor];
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

- (IBAction)timerSliderChange:(id)sender {
    self.timerInterval = self.timeIntervalSlider.value;
    self.timeIntervalLabel.text = [NSString stringWithFormat:@"%3.2f", self.timerInterval];
    
    // Stop samplers
    [self.levelTimer invalidate];
    self.levelTimer = nil;
    [self.secondTimer invalidate];
    self.secondTimer = nil;
    
    // Start samplers
    self.levelTimer = [NSTimer scheduledTimerWithTimeInterval:self.timerInterval target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
    self.secondTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(secondTimerCallBack:) userInfo:nil repeats:YES];
}

- (IBAction)frequencySliderChange:(id)sender {
    self.frequency = self.frequencySlider.value;
	self.frequencyOut.text = [NSString stringWithFormat:@"%4.1f Hz", self.frequency];
}

- (IBAction)amplitudeSliderChange:(id)sender {
    if (self.amplitudeSlider.value < 0.75f) {
        self.amplitude = self.amplitudeSlider.value;
        self.amplitudeOut.text = [NSString stringWithFormat:@"%3.0f", self.amplitude*100];
    } else {
        self.amplitude = 0.75f;
        self.amplitudeOut.text = [NSString stringWithFormat:@"%3.0f", self.amplitude*100];
    }
}



- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
