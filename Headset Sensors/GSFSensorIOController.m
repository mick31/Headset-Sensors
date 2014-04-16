//
//  GSFSensorIOController.m
//  GSFDataCollecter
//
//  Created by Mick Bennett on 3/30/14.
//  Copyright (c) 2014 Michael Baptist - LLNL. All rights reserved.
//

#import "GSFSensorIOController.h"
#import "ViewController.h"

#define kOutputBus   0
#define kInputBus  1

ViewController *dataView;

@interface GSFSensorIOController ()

// Private variables
@property AudioComponentInstance ioUnit;
@property AudioBuffer inBuffer;
@property AudioBuffer outBuffer;
@property AudioBuffer powerTone;
@property double sinPhase;
@property BOOL newDataOut;

@end

static OSStatus inputCallback(void *inRefCon,
                                   AudioUnitRenderActionFlags 	*ioActionFlags,
                                   const AudioTimeStamp 		*inTimeStamp,
                                   UInt32 						inBusNumber,
                                   UInt32 						inNumberFrames,
                                   AudioBufferList              *ioData) {
    // Scope reference to GSFSensorIOController class
    GSFSensorIOController *THIS = (__bridge GSFSensorIOController *) inRefCon;
    
    // Set up buffer to hold input data
    AudioBuffer buffer;
    buffer.mNumberChannels = 1;
    buffer.mDataByteSize = inNumberFrames * 2;
    buffer.mData = malloc( inNumberFrames * 2 );
    
    // Place buffer in an AudioBufferList
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer;
    
    // Grab the samples and place them in the buffer list
    AudioUnitRender(THIS.ioUnit,
                    ioActionFlags,
                    inTimeStamp,
                    inBusNumber,
                    inNumberFrames,
                    &bufferList);
    
    // Process data
    [THIS processIO:&bufferList];
    
    // Free allocated buffer
    free(bufferList.mBuffers[0].mData);
    
    return noErr;
}

static OSStatus outputCallback(void *inRefCon,
                              AudioUnitRenderActionFlags 	*ioActionFlags,
                              const AudioTimeStamp          *inTimeStamp,
                              UInt32 						inBusNumber,
                              UInt32 						inNumberFrames,
                              AudioBufferList               *ioData) {
    // Scope reference to GSFSensorIOController class
    GSFSensorIOController *THIS = (__bridge GSFSensorIOController *) inRefCon;
    
    // Communication out on left and right channel if new communication out
    AudioSampleType *outLeftSamples = (AudioSampleType *) ioData->mBuffers[0].mData;
    AudioSampleType *outRightSamples = (AudioSampleType *) ioData->mBuffers[0].mData;
    //AudioBuffer outRightSamples = ioData->mBuffers[1];
    
    // Set up power tone attributes
    float freq = 20000.00f;
    float sampleRate = 44100.00f;
    float phase = THIS.sinPhase;
    float sinSignal;
    
    double phaseInc = 2 * M_PI * freq / sampleRate;
    
    for (UInt32 curFrame = 0; curFrame < inNumberFrames; ++curFrame) {
        // Generate power tone on left channel
        sinSignal = sin(phase);
        outLeftSamples[curFrame] = (SInt16) ((sinSignal * 32767.0f) /2);
        outRightSamples[curFrame] = (SInt16) ((sinSignal * 32767.0f) /2);
        phase += phaseInc;
        if (phase >= 2 * M_PI * freq) {
            phase = phase - (2 * M_PI * freq);
        }
        /*
        // Check if new output flag is set and fill right channel buffer accordingly
        if (THIS.newDataOut) {
            UInt32 size = min(outRightSamples.mDataByteSize, THIS.outBuffer.mDataByteSize);
            memcpy(outRightSamples.mData, THIS.outBuffer.mData, size);
            outRightSamples.mDataByteSize = size;
        } else {
            UInt32 size = outRightSamples.mDataByteSize;
            memcpy(outRightSamples.mData, 0, size);
            outRightSamples.mDataByteSize = size;
        }
         */
    }
    
    // Save sine wave phase wave for next callback
    THIS.sinPhase = phase;
    
    return noErr;
}

@implementation GSFSensorIOController

@synthesize ioUnit = _ioUnit;
@synthesize inBuffer = _inBuffer;
@synthesize outBuffer = _outBuffer;
@synthesize powerTone = _powerTone;
@synthesize sensorAlert = _sensorAlert;
@synthesize sinPhase = _sinPhase;
@synthesize newDataOut = _newDataOut;

/**
 *  Initializes the audio session and audio units when class is instantiated.
 *
 *  @return The class instance with initailized audio session and units
 */
- (id) init {
    self = [super init];
    if (!self) return nil;
    
    // Set up AVAudioSession
    AVAudioSession *session = [AVAudioSession sharedInstance];
    BOOL success;
    NSError *error;
    
    success = [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
	if (!success) NSLog(@"ERROR viewDidLoad: AVAudioSession failed overrideOutputAudio- %@", error);
    
    success = [session setActive:YES error:&error];
    if(!success) NSLog(@"ERROR viewDidLoad: AVAudioSession failed activating- %@", error);
    
    // Set up master volume controller
    MPVolumeView *volumeView = [MPVolumeView new];
    volumeView.showsRouteButton = NO;
    volumeView.showsVolumeSlider = NO;
    [dataView.view addSubview:volumeView];
    
    // Bind master volume slider to class volume slider
    __weak __typeof(self)weakSelf = self;
    [[volumeView subviews] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[UISlider class]]) {
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            strongSelf.volumeSlider = obj;
            *stop = YES;
        }
    }];
    
    // Add volume change callback
    [self.volumeSlider addTarget:self action:@selector(handleVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    
    return self;
}


/**
 *  Auto adjuct iOS devices master volume when the sensor is attached.
 *
 *  @param sender NSNotification containing the master volume slider.
 */
- (void) handleVolumeChanged:(id)sender{
    if (self.ioUnit) self.volumeSlider.value = 1.0f;
}


- (void) setUpSensorIO {
    // Audio component description
    AudioComponentDescription desc;
    desc.componentType          = kAudioUnitType_Output;
    desc.componentSubType       = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer  = kAudioUnitManufacturer_Apple;
    desc.componentFlags         = 0;
    desc.componentFlagsMask     = 0;
    
    // Get component
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    
    // Mono ASBD
    AudioStreamBasicDescription monoStreamFormat;
    monoStreamFormat.mSampleRate          = 44100.00;
    monoStreamFormat.mFormatID            = kAudioFormatLinearPCM;
    monoStreamFormat.mFormatFlags         = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    monoStreamFormat.mBytesPerPacket      = 2;
    monoStreamFormat.mBytesPerFrame       = 2;
    monoStreamFormat.mFramesPerPacket     = 1;
    monoStreamFormat.mChannelsPerFrame    = 1;
    monoStreamFormat.mBitsPerChannel      = 16;
     
    // Stereo ASBD
    AudioStreamBasicDescription stereoStreamFormat;
    stereoStreamFormat.mSampleRate          = 44100.00;
    stereoStreamFormat.mFormatID            = kAudioFormatLinearPCM;
    stereoStreamFormat.mFormatFlags         = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    stereoStreamFormat.mBytesPerPacket      = 4;
    stereoStreamFormat.mBytesPerFrame       = 4;
    stereoStreamFormat.mFramesPerPacket     = 1;
    stereoStreamFormat.mChannelsPerFrame    = 2;
    stereoStreamFormat.mBitsPerChannel      = 16;
    
    OSErr err;
    @try {
        // Get Audio units
        err = AudioComponentInstanceNew(inputComponent, &_ioUnit);
        NSAssert1(err == noErr, @"Error setting input component: %hd", err);
        
        // Enable input, which is disabled by default. Output is enabled by default
        UInt32 enableInput = 1;
        err = AudioUnitSetProperty(_ioUnit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input,
                             kInputBus,
                             &enableInput,
                             sizeof(enableInput));
        NSAssert1(err == noErr, @"Error enable input: %hd", err);
        
        err = AudioUnitSetProperty(_ioUnit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output,
                             kOutputBus,
                             &enableInput,
                             sizeof(enableInput));
        NSAssert1(err == noErr, @"Error setting output: %hd", err);
        
        // Apply format to input of ioUnit
        err = AudioUnitSetProperty(self.ioUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input,
                             kOutputBus,
                             &monoStreamFormat,
                             sizeof(monoStreamFormat));
        NSAssert1(err == noErr, @"Error setting input ASBD: %hd", err);
        
        // Apply format to output of ioUnit
        err = AudioUnitSetProperty(self.ioUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output,
                             kInputBus,
                             &stereoStreamFormat,
                             sizeof(stereoStreamFormat));
        NSAssert1(err == noErr, @"Error setting output ASBD: %hd", err);
        
        // Set input callback
        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = inputCallback;
        callbackStruct.inputProcRefCon = (__bridge void *)(self);
        err = AudioUnitSetProperty(self.ioUnit,
                             kAudioOutputUnitProperty_SetInputCallback,
                             kAudioUnitScope_Global,
                             kInputBus,
                             &callbackStruct,
                             sizeof(callbackStruct));
        NSAssert1(err == noErr, @"Error setting input callback: %hd", err);
        
        // Set output callback
        callbackStruct.inputProc = outputCallback;
        callbackStruct.inputProcRefCon = (__bridge void *)(self);
        err = AudioUnitSetProperty(self.ioUnit,
                             kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Global,
                             kOutputBus,
                             &callbackStruct,
                             sizeof(callbackStruct));
        NSAssert1(err == noErr, @"Error setting output callback: %hd", err);
        
        // Initialize audio unit
        err = AudioUnitInitialize(self.ioUnit);
        NSAssert1(err == noErr, @"Error initializing unit: %hd", err);
        //AudioUnitInitialize(self.ioUnit);
        
        // Start audio IO
        err = AudioOutputUnitStart(self.ioUnit);
        NSAssert1(err == noErr, @"Error starting unit: %hd", err);
        //AudioOutputUnitStart(self.ioUnit);

    }
    @catch (NSException *exception) {
        NSLog(@"Failed with exception: %@", exception);
    }
    
}


- (void) monitorSensors: (BOOL) enable {
    if (enable){// && self.isSensorConnected) {
        // Start IO communication
        [self startCollecting];
        
        // Register audio route change listner with notification callback
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListener:) name:AVAudioSessionRouteChangeNotification object:nil];
        
        NSLog(@"Sensor monitor STARTED");
    } else {
        // Unregister notification callbacks
        [[NSNotificationCenter defaultCenter] removeObserver: self];
        
        // Stop IO communication
        if (self.ioUnit) {
            [self stopCollecting];
        }
        
        NSLog(@"Sensor monitor STOPPED");
    }
}


- (void) startCollecting {
    [self setUpSensorIO];
    // Set Master Volume to 100%
    self.volumeSlider.value = 1.0f;
}


- (void) stopCollecting {
    // Set Master Volume to 50%
    self.volumeSlider.value = 0.5f;
    
    // Stop and release audio unit
    AudioOutputUnitStop(self.ioUnit);
    AudioUnitUninitialize(self.ioUnit);
    AudioComponentInstanceDispose(self.ioUnit);
    self.ioUnit = nil;
}

/**
 *  Detects sensor connection
 *
 *  @return True if audio route is the one used by sensor system and false otherwise
 */
- (BOOL) isSensorConnected {
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


/**
 *  Audio route change listener callback, for GSFSensorIOController class, that is invoked whenever a change occurs in the audio route.
 *
 *  @param notification A notification containing audio change reason
 */
- (void) audioRouteChangeListener: (NSNotification*)notification {
    // Initiallize dictionary with notification and grab route change reason
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    NSLog(@"MADE IT: sensorAudioRouteChageListener");
    
    switch (routeChangeReason) {
        // Sensor inserted
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            // Start IO communication
            [self startCollecting];
            
            
            NSLog(@"Sensor INSERTED");
            break;
            
        // Sensor removed
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            // Stop IO audio unit
            [self stopCollecting];
            
            
            NSLog(@"Sensor REMOVED");
            break;
            
        // Category changed from PlayAndRecord
        case AVAudioSessionRouteChangeReasonCategoryChange:
            // Stop IO audio unit
            [self stopCollecting];
            
            NSLog(@"Category CHANGED");
            break;
            
        default:
            NSLog(@"Blowing it in- audioRouteChangeListener with route change reason: %ld", (long)routeChangeReason);
            break;
    }
}


/**
 *  Adds the alert view to the data staging area after an audio route change occurs
 *
 *  @param view         The UIView for the data staging area
 *  @param changeReason The NSInteger holding the reason why the audio route changed
 */
- (void) addAlertViewToView:(UIView*) view :(NSInteger) changeReason {
    // Dismiss any existing alert
    if (self.sensorAlert) {
        [self.sensorAlert dismissWithClickedButtonIndex:0 animated:NO];
    }
    
    // Set up image for alert View
    UIImageView *alertImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"GSF_Insert_sensor_alert-v2.png"]];
    
    switch (changeReason) {
        case 1:
            // Set up alert View
            self.sensorAlert =
            [[SDCAlertView alloc]
             initWithTitle:@"No Sensor"
             message:@"Please insert the GSF sensor to collect this data. Pressing \"Cancel\" will end sensor data collection."
             delegate:self
             cancelButtonTitle:nil
             otherButtonTitles:@"Cancel", nil];
            
            [alertImageView setTranslatesAutoresizingMaskIntoConstraints:NO];
            [self.sensorAlert.contentView addSubview:alertImageView];
            [alertImageView sdc_horizontallyCenterInSuperview];
            [self.sensorAlert.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[alertImageView]|"
                                                                                                 options:0
                                                                                                 metrics:nil
                                                                                                   views:NSDictionaryOfVariableBindings(alertImageView)]];
            break;
        case 2:
            // Set up Alert View
            self.sensorAlert =
            [[SDCAlertView alloc]
             initWithTitle:@"Audio Source Changed"
             message:@"The audio input has changed from the GSF App. To continue collecting sensor data press \"Continue\". Pressing \"Cancel\" will end sensor data collection."
             delegate:self
             cancelButtonTitle:nil
             otherButtonTitles:@"Cancel", @"Continue", nil];
            break;
        default:
            NSLog(@"Blowing It In- addAlertViewToView");
    }
    
    // Add alertView to current view
    [view addSubview:self.sensorAlert];
    
    // Show Alert
    [self.sensorAlert show];
}


/**
 *  Custom alert view callback handler that responds to user button selection
 *
 *  @param alertView   A SDCAlertView instance
 *  @param buttonIndex The button index selected by user.
 */
- (void)alertView:(SDCAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        // Cancel Button pushed
        case 0:
            // Unregister notification center observer
            [[NSNotificationCenter defaultCenter] removeObserver: self];
            
            // Stop IO audio unit
            [self stopCollecting];
            break;
            
        // Continue
        case 1:
            // Start IO communication
            [self startCollecting];
            break;
            
        default:
            NSLog(@"Blowing It In- alertView: Button index not handled: %ld", (long)buttonIndex);
            break;
    }
}

/**
 *  Process Input readinga and fills right channel output buffer with any response
 *
 *  @param bufferList This is list of buffers containing the input from the mic line
 */
- (void) processIO: (AudioBufferList*) bufferList {
    AudioBuffer sourceBuffer = bufferList->mBuffers[0];
	
	// fix tempBuffer size if it's the wrong size
	if (self.inBuffer.mDataByteSize != sourceBuffer.mDataByteSize) {
		free(self.inBuffer.mData);
		_inBuffer.mDataByteSize = sourceBuffer.mDataByteSize;
		_inBuffer.mData = malloc(sourceBuffer.mDataByteSize);
	}
	
	// copy incoming audio data to temporary buffer
	memcpy(_inBuffer.mData, bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
    
    SInt16 *buffer = (SInt16 *) bufferList->mBuffers[0].mData;
    
    /**** DEBUG: Prints contents of input buffer to consol ****/
    for (int i = 0; i < (_inBuffer.mDataByteSize / sizeof(_inBuffer)); i++) {
        NSLog(@"%d", buffer[i]);
    }
    
    // Fill output buffer with commands and set new output data flag
    
}

@end
