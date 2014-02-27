//
//  ViewController.m
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ViewController.h"

OSStatus RenderTone(
                    void *inRefCon,
                    AudioUnitRenderActionFlags 	*ioActionFlags,
                    const AudioTimeStamp 		*inTimeStamp,
                    UInt32 						inBusNumber,
                    UInt32 						inNumberFrames,
                    AudioBufferList 			*ioData)

{
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
@synthesize lowPassFiltered = _lowPassFiltered;
@synthesize avgInput = _avgInput;
@synthesize peakInput = _peakInput;
@synthesize lowpassInput = _lowpassInput;
@synthesize inputSource = _inputSource;
@synthesize headsetSwitch = _headsetSwitch;

@synthesize powerTone = _powerTone;
@synthesize frequency = _frequency;
@synthesize amplitude = _amplitude;
@synthesize sampleRate = _sampleRate;
@synthesize theta = _theta;
@synthesize frequencySlider = _frequencySlider;
@synthesize frequencyOut = _frequencyOut;
@synthesize amplitudeSlider = _amplitudeSlider;
@synthesize amplitudeOut = _amplitudeOut;



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
	input.inputProc = RenderTone;
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
        if (_powerTone) {
            // Set master volume to 50%
            MPMusicPlayerController* appVolume = [MPMusicPlayerController applicationMusicPlayer];
            [appVolume setVolume:0.5];
        }
        
		// Stop and release power tone
        AudioOutputUnitStop(_powerTone);
		AudioUnitUninitialize(_powerTone);
		AudioComponentInstanceDispose(_powerTone);
		_powerTone = nil;
	} else {
		[self createToneUnit];
		
		// Stop changing parameters on the unit
		OSErr err = AudioUnitInitialize(_powerTone);
		NSAssert1(err == noErr, @"Error initializing unit: %hd", err);
		
        // Set master volume to max
        MPMusicPlayerController* appVolume = [MPMusicPlayerController applicationMusicPlayer];
        [appVolume setVolume:1.0];
        
		// Start playback
		err = AudioOutputUnitStart(_powerTone);
		NSAssert1(err == noErr, @"Error starting unit: %hd", err);
	}
}


- (void)viewDidLoad {
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
    
    _recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&err];
    
    if (_recorder) {
        [_recorder prepareToRecord];
        _recorder.meteringEnabled = YES;
        [_recorder record];
    } else
        NSLog(@"%@",[err description]);
    
    // Power tone setup
    _sampleRate = 44100;
    _frequency = 5000;
    _amplitude = 0.5;
    OSStatus result = AudioSessionInitialize(NULL,
                                             NULL,
                                             ToneInterruptionListener,
                                             (_powerTone));
	if (result == kAudioSessionNoError) {
        // allows for both mic and speaker output
		UInt32 sessionCategory = kAudioSessionCategory_PlayAndRecord;
		AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(sessionCategory), &sessionCategory);
	}
	AudioSessionSetActive(true);
}

-(void) levelTimerCallBack:(NSTimer *)timer {
    [_recorder updateMeters];
    
    const double ALPHA = 0.05;
    double peakPowerForChannel = pow(10, (0.05 * [_recorder peakPowerForChannel:0]));
    _lowPassFiltered = ALPHA * peakPowerForChannel + (1.0 - ALPHA) * _lowPassFiltered;
    
    _avgInput.text = [NSString stringWithFormat:@"%f", [_recorder averagePowerForChannel:0]];
    _peakInput.text = [NSString stringWithFormat:@"%f", [_recorder peakPowerForChannel:0]];
    _lowpassInput.text = [NSString stringWithFormat:@"%f", _lowPassFiltered];
    
    if (self.isHeadsetPluggedIn)
        _inputSource.text = @"Headset";
    else if ([_inputSource.text isEqualToString:@"Headset"]) {
        // Stop Timer
        [timer invalidate];
        timer = nil;
        
        // Kill power Tone
        [self togglePower:NO];
        
        // Setup image for Alert View
        UIImageView *alertImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"GSF_Insert_sensor_alert-v2.png"]];
        
        
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
        [alertImageView sdc_horizontallyCenterInSuperview];
        [noHeadsetAlertView.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[alertImageView]|"
                                                                                               options:0
                                                                                               metrics:nil
                                                                                                 views:NSDictionaryOfVariableBindings(alertImageView)]];
        // Alert Callback Setup
        //_alertTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(alertTimerCallBack:) userInfo:nil repeats:YES];
        [noHeadsetAlertView show];
    } else
        _inputSource.text = @"Mic";
}

// Dismiss alertview if headset is found
- (void) alertTimerCallBack:(NSTimer *) timer {
    if (self.isHeadsetPluggedIn) {
        /* ************************
         * Note:
         *  Make AlertView a property of ViewController so that it can be released from here
         * ***********************/
        NSLog(@"alertTimerCallback: **** Release Alert Here ***");
    }
}

- (void)alertView:(SDCAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        case 0:
            self.headsetSwitch.on = NO ;
            _inputSource.text = @"None";
            
            //Disable sliders
            _frequencySlider.userInteractionEnabled = NO;
            _frequencySlider.tintColor = [UIColor grayColor];
            _amplitudeSlider.userInteractionEnabled = NO;
            _amplitudeSlider.tintColor = [UIColor grayColor];
            break;
        case 1:
            _levelTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
            _inputSource.text = @"Mic";
            
            //Disable sliders
            _frequencySlider.userInteractionEnabled = NO;
            _frequencySlider.tintColor = [UIColor grayColor];
            _amplitudeSlider.userInteractionEnabled = NO;
            _amplitudeSlider.tintColor = [UIColor grayColor];
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
        _levelTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(levelTimerCallBack:) userInfo:nil repeats:YES];
        
        // Start Power Tone
        [self togglePower:YES];
        
        //Enable sliders
        _frequencySlider.userInteractionEnabled = YES;
        _frequencySlider.tintColor = [UIColor greenColor];
        _amplitudeSlider.userInteractionEnabled = YES;
        _amplitudeSlider.tintColor = [UIColor greenColor];
    } else if (!self.headsetSwitch.on){
        [_levelTimer invalidate];
        _levelTimer = nil;
        _inputSource.text = @"None";
        
        // Stop Power Tone
        [self togglePower:NO];
        
        //Disable sliders
        _frequencySlider.userInteractionEnabled = NO;
        _frequencySlider.tintColor = [UIColor grayColor];
        _amplitudeSlider.userInteractionEnabled = NO;
        _amplitudeSlider.tintColor = [UIColor grayColor];
    } else {
        [_levelTimer invalidate];
        _levelTimer = nil;
        
        // Stop Power Tone
        [self togglePower:NO];
        
        // Setup image for Alert View
        UIImageView *alertImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"GSF_Insert_sensor_alert-v2.png"]];

        
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
        [alertImageView sdc_horizontallyCenterInSuperview];
        [noHeadsetAlertView.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[alertImageView]|"
        options:0
        metrics:nil
        views:NSDictionaryOfVariableBindings(alertImageView)]];
        
        // Alert Callback Setup
        _alertTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(alertTimerCallBack:) userInfo:nil repeats:YES];
        
        [noHeadsetAlertView show];
    }
}

- (IBAction)frequencySliderChange:(id)sender {
    _frequency = _frequencySlider.value;
	_frequencyOut.text = [NSString stringWithFormat:@"%4.1f Hz", _frequency];
}

- (IBAction)amplitudeSliderChange:(id)sender {
    _amplitude = _amplitudeSlider.value;
	_amplitudeOut.text = [NSString stringWithFormat:@"%3.0f", _amplitude*100];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
