//
//  ViewController.m
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ViewController.h"

#define kOutputBus 0
#define kInputBus 1

ViewController* audioIO;

void checkStatus(int status, char *call){
	if (status) {
		printf("%s Failed: %d\n", call, status);
        //		exit(1);
	}
}

static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
	
	// Because of the way our audio format (setup below) is chosen:
	// we only need 1 buffer, since it is mono
	// Samples are 16 bits = 2 bytes.
	// 1 frame includes only 1 sample
	
	AudioBuffer buffer;
	
	buffer.mNumberChannels = 1;
	buffer.mDataByteSize = inNumberFrames * 2;
	buffer.mData = malloc( inNumberFrames * 2 );
	
	// Put buffer in a AudioBufferList
	AudioBufferList bufferList;
	bufferList.mNumberBuffers = 1;
	bufferList.mBuffers[0] = buffer;
	
    // Then:
    // Obtain recorded samples
	
    OSStatus status;
	
    status = AudioUnitRender(audioIO.inputAudioUnit,
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &bufferList);
	checkStatus(status, (char *) "recordingCallback-AudioUnitRender");
	
    // Now, we have the samples we just read sitting in buffers in bufferList
	// Process the new data
	[audioIO processInput:&bufferList];
	
	// release the malloc'ed data in the buffer we created earlier
	free(bufferList.mBuffers[0].mData);
	
    return noErr;
}

/**
 This callback is called when the audioUnit needs new data to play through the
 speakers. If you don't have any, just don't write anything in the buffers
 */
static OSStatus playbackCallback(void *inRefCon,
								 AudioUnitRenderActionFlags *ioActionFlags,
								 const AudioTimeStamp *inTimeStamp,
								 UInt32 inBusNumber,
								 UInt32 inNumberFrames,
								 AudioBufferList *ioData) {
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
	
	double theta = audioIO.theta;
	double theta_increment = 2.0 * M_PI * audioIO.frequency / audioIO.sampleRate;
    
	// This is a mono tone generator therefore only requires the first buffer
	const int channel = 0;
	Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;
	
	// Generate the samples
	for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
		buffer[frame] = sin(theta) * audioIO.amplitude;
		
		theta += theta_increment;
		if (theta > 2.0 * M_PI) {
			theta -= 2.0 * M_PI;
		}
	}
	
	// Store the theta back in the view controller
	audioIO.theta = theta;
    
	return noErr;
}

void routeInterruptionListener(void *inClientData, UInt32 inInterruptionState) {
	ViewController *viewController =
    (__bridge ViewController *)inClientData;
	
    // turn power off if interruption occurs
	[viewController toggleCollectIO:NO];
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
    
    // Intialize remote IO with input and output settings
    [self initRemoteIO];
    
    // Setup master volume controller
    MPVolumeView *volumeView = [MPVolumeView new];
    volumeView.showsRouteButton = NO;
    volumeView.showsVolumeSlider = NO;
    [self.view addSubview:volumeView];
    
    // Link dummy slider with master volume slider
    __weak __typeof(self)weakSelf = self;
    [[volumeView subviews] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[UISlider class]]) {
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            strongSelf.volumeSlider = obj;
            *stop = YES;
        }
    }];
    
    // Initialize dummy slider with change callback
    [self.volumeSlider addTarget:self action:@selector(handleVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    
    // Add audio route change listner
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListener:) name:AVAudioSessionRouteChangeNotification object:nil];
}

- (void) initRemoteIO {
	// Describe audio component
	AudioComponentDescription desc;
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	
	// Get component
	AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
	
	// Get input audio unit
	checkStatus(AudioComponentInstanceNew(inputComponent, &_powerOutAudioUnit), (char *) "initRemotIO- AudioComponenInstanceNew- powerOutAudioUnit");
    checkStatus(AudioComponentInstanceNew(inputComponent, &_inputAudioUnit), (char *) "initRemotIO- AudioComponenInstanceNew- inputAudioUnit");
	
	// Enable IO for recording
	UInt32 flag = 1;
	checkStatus(AudioUnitSetProperty(audioIO.inputAudioUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Input,
                                     kInputBus,
                                     &flag,
                                     sizeof(flag)), (char *) "initRemotIO- AudioUnitSetProperty- kAudioOutputUnitProperty_EnableIO- inputAudioUnit");
	
	// Enable IO for playback
	checkStatus(AudioUnitSetProperty(audioIO.powerOutAudioUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Output,
                                     kOutputBus,
                                     &flag,
                                     sizeof(flag)), (char *) "initRemotIO- AudioUnitSetProperty- kAudioOutputUnitProperty_EnableIO- powerOutAudioUnit");
	
	// Describe input format
	AudioStreamBasicDescription audioInFormat;
	audioInFormat.mSampleRate		= 44100.00;
	audioInFormat.mFormatID         = kAudioFormatLinearPCM;
	audioInFormat.mFormatFlags		= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	audioInFormat.mFramesPerPacket	= 1;
	audioInFormat.mChannelsPerFrame	= 1;
	audioInFormat.mBitsPerChannel	= 16;
	audioInFormat.mBytesPerPacket	= 2;
	audioInFormat.mBytesPerFrame	= 2;
	
    // Describe output format
    // Set the format to 32 bit, single channel, floating point, linear PCM
	const int four_bytes_per_float = 4;
	const int eight_bits_per_byte = 8;
	AudioStreamBasicDescription powerOutFormat;
	powerOutFormat.mSampleRate        = _sampleRate;
	powerOutFormat.mFormatID          = kAudioFormatLinearPCM;
	powerOutFormat.mFormatFlags       =
    kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
	powerOutFormat.mBytesPerPacket    = four_bytes_per_float;
	powerOutFormat.mFramesPerPacket   = 1;
	powerOutFormat.mBytesPerFrame     = four_bytes_per_float;
	powerOutFormat.mChannelsPerFrame  = 1;
	powerOutFormat.mBitsPerChannel    = four_bytes_per_float * eight_bits_per_byte;
    
	// Apply formats
	checkStatus(AudioUnitSetProperty(audioIO.inputAudioUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Output,
                                     kInputBus,
                                     &audioInFormat,
                                     sizeof(audioInFormat)), (char *) "initRemotIO- AudioUnitSetProperty- kAudioUnitProperty_StreamFormat- inputAudioUnit");
    
	checkStatus(AudioUnitSetProperty(audioIO.powerOutAudioUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Input,
                                     kOutputBus,
                                     &powerOutFormat,
                                     sizeof(powerOutFormat)), (char *) "initRemotIO- AudioUnitSetProperty- kAudioUnitProperty_StreamFormat- powerOutAudioUnit");
	
	
	// Set input callback
	AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProc = recordingCallback;
	callbackStruct.inputProcRefCon = (__bridge void *)(self);
	checkStatus(AudioUnitSetProperty(audioIO.inputAudioUnit,
                                     kAudioOutputUnitProperty_SetInputCallback,
                                     kAudioUnitScope_Global,
                                     kInputBus,
                                     &callbackStruct,
                                     sizeof(callbackStruct)), (char *) "initRemotIO- AudioUnitSetProperty- kAudioOutputUnitProperty_SetInputCallback- inputAudioUnit");
	
	// Set output callback
	callbackStruct.inputProc = playbackCallback;
	callbackStruct.inputProcRefCon = (__bridge void *)(self);
	checkStatus(AudioUnitSetProperty(audioIO.powerOutAudioUnit,
                                     kAudioUnitProperty_SetRenderCallback,
                                     kAudioUnitScope_Global,
                                     kOutputBus,
                                     &callbackStruct,
                                     sizeof(callbackStruct)), (char *) "initRemotIO- AudioUnitSetProperty- kAudioOutputUnitProperty_SetInputCallback- powerOutAudioUnit");
	
    
	// Allocate our own buffers (1 channel, 16 bits per sample, thus 16 bits per frame, thus 2 bytes per frame).
	// Practice learns the buffers used contain 512 frames, if this changes it will be fixed in processAudio.
	_micBuffer.mNumberChannels = 1;
	_micBuffer.mDataByteSize = 512 * 2;
	_micBuffer.mData = malloc( 512 * 2 );
	
	// Initialise both audio units
	checkStatus(AudioUnitInitialize(audioIO.inputAudioUnit), (char *) "initRemotIO- AudioUnitSetProperty- inputAudioUnit");
	checkStatus(AudioUnitInitialize(audioIO.powerOutAudioUnit), (char *) "initRemotIO- AudioUnitSetProperty- powerOutAudioUnit");
}

- (void) processInput: (AudioBufferList*) bufferList{
	AudioBuffer sourceBuffer = bufferList->mBuffers[0];
	
	// fix tempBuffer size if it's the wrong size
	if (self.micBuffer.mDataByteSize != sourceBuffer.mDataByteSize) {
		free(self.micBuffer.mData);
		self->_micBuffer.mDataByteSize = sourceBuffer.mDataByteSize;
		self->_micBuffer.mData = malloc(sourceBuffer.mDataByteSize);
	}
	
	// copy incoming audio data to temporary buffer
	memcpy(self->_micBuffer.mData, bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
    
    SInt16 *buffer = (SInt16 *) bufferList->mBuffers[0].mData;
    
    for (int i = 0; i < (self.micBuffer.mDataByteSize / sizeof(self.micBuffer)); i++) {
        NSLog(@"%d", buffer[i]);
    }
}

- (void)toggleCollectIO:(BOOL)collect {
    if (!collect) {
        // Set Master Volume to 50%
        self.volumeSlider.value = 0.5f;
        
        if (self.powerOutAudioUnit) {
            // Stop and release power tone audio unit
            checkStatus(AudioOutputUnitStop(self.powerOutAudioUnit), (char *) "toggleCollectIO- AudioOutputUnitStop- powerOutAudioUnit");
            checkStatus(AudioUnitUninitialize(self.powerOutAudioUnit), (char *) "toggleCollectIO- AudioUnitUninitialize- powerOutAudioUnit");
            checkStatus(AudioComponentInstanceDispose(self.powerOutAudioUnit), (char *) "toggleCollectIO- AudioComponentInstanceDispose- powerOutAudioUnit");
            self.powerOutAudioUnit = nil;
        }
		if (self.inputAudioUnit) {
            // Stop and release mic audio unit
            checkStatus(AudioOutputUnitStop(self.inputAudioUnit), (char *) "toggleCollectIO- AudioOutputUnitStop- inputAudioUnit");
            checkStatus(AudioUnitUninitialize(self.inputAudioUnit), (char *) "toggleCollectIO- AudioUnitUninitialize- inputAudioUnit");
            checkStatus(AudioComponentInstanceDispose(self.inputAudioUnit), (char *) "toggleCollectIO- AudioComponentInstanceDispose- inputAudioUnit");
            self.inputAudioUnit = nil;
        }
	} else {
        // Set Master Volume to 100%
        self.volumeSlider.value = 1.0f;
        
        if (!self.powerOutAudioUnit){
            // Initialize and Start playback
            checkStatus(AudioUnitInitialize(self.powerOutAudioUnit), (char *) "toggleCollectIO- AudioUnitInitialize- powerOutAudioUnit");
            checkStatus(AudioOutputUnitStart(self.powerOutAudioUnit), (char *) "toggleCollectIO- AudioOutputUnitStart- powerOutAudioUnit");
        }
        if (!self.inputAudioUnit) {
            // Initialize and Start input
            checkStatus(AudioUnitInitialize(self.inputAudioUnit), (char *) "toggleCollectIO- AudioUnitInitialize- inputAudioUnit");
            checkStatus(AudioOutputUnitStart(self.inputAudioUnit), (char *) "toggleCollectIO- AudioUnitInitialize- inputAudioUnit");
        }
	}
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
    if (self.powerOutAudioUnit) self.volumeSlider.value = 1.0f;
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
            [self toggleCollectIO:NO];
            break;
        case 1:
            // Initialize and start mic callback
            if (!self.inputAudioUnit) {
                checkStatus(AudioUnitInitialize(self.inputAudioUnit), (char *) "alertView- AudioUnitInitialize- inputAudioUnit");
                checkStatus(AudioOutputUnitStart(self.inputAudioUnit), (char *) "alertView- AudioOutputUnitStart- inputAudioUnit");
            }
            
            // Change input label text
            self.inputSource.text = @"Mic";
            break;
        default:
            NSLog(@"Blowing It: Alert not handled");
            break;
    }
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
        // Start timer
        self.secondTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(secondTimerCallBack:) userInfo:nil repeats:YES];
        
        // Start IO
        [self toggleCollectIO:YES];
    } else if (!self.headsetSwitch.on){
        // Stop timer
        [self.secondTimer invalidate];
        self.secondTimer = nil;
        
        // Change input text
        self.inputSource.text = @"None";
        
        // Stop IO
        [self toggleCollectIO:NO];
    } else {
        // Stop timer
        [self.secondTimer invalidate];
        self.secondTimer = nil;
        
        // Stop IO
        [self toggleCollectIO:NO];
        
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
        
        
        [self.sensorAlert show];
    }
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
