//
//  GSFSensorIOController.m
//  GSFDataCollecter
//
//  Created by Mick Bennett on 3/30/14.
//  Copyright (c) 2014 Michael Baptist - LLNL. All rights reserved.
//

#import "GSFSensorIOController.h"
#import "ViewController.h"

// Defined Macros
#define kOutputBus          0
#define kInputBus           1
#define kSamplesPerCheck    10
#define kHighMin            30000
#define kLowMin             -30000
#define kSampleRate         44100.00f
#define kManchesterZero     0
#define kManchesterOne      1

#ifndef min
#define min( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif

#ifndef max
#define max( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

// Pointer to associated view controller
ViewController *dataView;

// Private interface
@interface GSFSensorIOController () {
    AUGraph auGraph;
    AUNode ioNode;
}
@property(assign) AudioUnit ioUnit;
@property AVAudioSession* sensorAudioSession;
@property NSMutableArray *sensorData;
@property NSMutableArray *rawInputData;
@property double sinPhase;
@property BOOL newDataOut;
@property BOOL startBit;
@property BOOL startRise;
@property int curState;
@property int lastState;
@property int durationCount;

@end

static OSStatus hardwareIOCallback(void                         *inRefCon,
                                   AudioUnitRenderActionFlags 	*ioActionFlags,
                                   const AudioTimeStamp 		*inTimeStamp,
                                   UInt32 						inBusNumber,
                                   UInt32 						inNumberFrames,
                                   AudioBufferList              *ioData) {
    // Scope reference to GSFSensorIOController class
    GSFSensorIOController *sensorIO = (__bridge GSFSensorIOController *) inRefCon;
    
    // Grab the samples and place them in the buffer list
    AudioUnit ioUnit = sensorIO.ioUnit;

    OSStatus result = AudioUnitRender(ioUnit,
                                   ioActionFlags,
                                   inTimeStamp,
                                   kInputBus,
                                   inNumberFrames,
                                   ioData);
    
    // Process input data
    [sensorIO processIO:ioData];
    
    // Set up power tone attributes
    float freq = 20000.00f;
    float sampleRate = 44100.00f;
    float phase = sensorIO.sinPhase;
    float sinSignal;
    
    double phaseInc = 2 * M_PI * freq / sampleRate;
    
    // Write to output buffers
    for(size_t i = 0; i < ioData->mNumberBuffers; ++i) {
        AudioBuffer buffer = ioData->mBuffers[i];
        for(size_t sampleIdx = 0; sampleIdx < inNumberFrames; ++sampleIdx) {
            // Grab sample buffer
            SInt16 *sampleBuffer = buffer.mData;
            
            // Generate power tone on left channel
            sinSignal = sin(phase);
            sampleBuffer[2 * sampleIdx] = (SInt16)((sinSignal * 32767.0f) /2);
            
            // Write to commands to Atmel on right channel as necessary
            if(sensorIO.newDataOut)
                sampleBuffer[2*sampleIdx + 1] = (SInt16)((sinSignal * 32767.0f) /2);
            else
                sampleBuffer[2*sampleIdx + 1] = 0;
            
            phase += phaseInc;
            if (phase >= 2 * M_PI * freq) {
                phase -= (2 * M_PI * freq);
            }
        }
    }
    
    // Store sine wave phase for next callback
    sensorIO.sinPhase = phase;
    
    return result;
}

@implementation GSFSensorIOController

@synthesize ioUnit = _ioUnit;

/**
 *  Initializes the audio session and audio units when class is instantiated.
 *
 *  @return The class instance with initailized audio session and units
 */
- (id) init {
    self = [super init];
    if (!self) {
        NSLog(@"ERROR viewDidLoad: GSFSensorIOController Failed to initialize");
        return nil;
    }
    
    // Set up AVAudioSession
    self.sensorAudioSession = [AVAudioSession sharedInstance];
    BOOL success;
    NSError *error;
    
    success = [self.sensorAudioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
	if (!success) NSLog(@"ERROR viewDidLoad: AVAudioSession failed setting category- %@", error);
    
    // Make the sensor AVAudioSession active
    success = [self.sensorAudioSession setActive:YES error:&error];
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
    
    // Setup AUGraph
    [self setUpSensorIO];
    
    return self;
}


/**
 *  Auto adjuct iOS devices master volume when the sensor is attached.
 *
 *  @param sender NSNotification containing the master volume slider.
 */
- (void) handleVolumeChanged:(id)sender{
    if (self->auGraph) self.volumeSlider.value = 1.0f;
}


- (void) setUpSensorIO {
    // Initialize input data buffer/states
    self.curState = 0;
    self.lastState = 0;
    self.startBit = false;
    self.startRise = false;
    self.sensorData = [NSMutableArray array];
    self.rawInputData = [NSMutableArray array];
    
    // Audio component description
    AudioComponentDescription desc;
    bzero(&desc, sizeof(AudioComponentDescription));
    desc.componentType          = kAudioUnitType_Output;
    desc.componentSubType       = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer  = kAudioUnitManufacturer_Apple;
    desc.componentFlags         = 0;
    desc.componentFlagsMask     = 0;
    
    // Stereo ASBD
    AudioStreamBasicDescription stereoStreamFormat;
    bzero(&stereoStreamFormat, sizeof(AudioStreamBasicDescription));
    stereoStreamFormat.mSampleRate          = kSampleRate;
    stereoStreamFormat.mFormatID            = kAudioFormatLinearPCM;
    stereoStreamFormat.mFormatFlags         = kAudioFormatFlagsCanonical;
    stereoStreamFormat.mBytesPerPacket      = 4;
    stereoStreamFormat.mBytesPerFrame       = 4;
    stereoStreamFormat.mFramesPerPacket     = 1;
    stereoStreamFormat.mChannelsPerFrame    = 2;
    stereoStreamFormat.mBitsPerChannel      = 16;
    
    OSErr err = noErr;
    @try {
        // Create new AUGraph
        err = NewAUGraph(&auGraph);
        NSAssert1(err == noErr, @"Error creating AUGraph: %hd", err);
        
        // Add node to AUGraph
        err = AUGraphAddNode(auGraph,
                             &desc,
                             &ioNode);
        NSAssert1(err == noErr, @"Error adding AUNode: %hd", err);
        
        // Open AUGraph
        err = AUGraphOpen(auGraph);
        NSAssert1(err == noErr, @"Error opening AUGraph: %hd", err);
        
        // Add AUGraph node info
        err = AUGraphNodeInfo(auGraph,
                              ioNode,
                              &desc,
                              &_ioUnit);
        NSAssert1(err == noErr, @"Error adding noe info to AUGraph: %hd", err);
        
        // Enable input, which is disabled by default.
        UInt32 enabled = 1;
        err = AudioUnitSetProperty(_ioUnit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input,
                             kInputBus,
                             &enabled,
                             sizeof(enabled));
        NSAssert1(err == noErr, @"Error enabling input: %hd", err);
        /*
        // Set bandpass filter for input.
        UInt32 bandWidthCenter = 5000;
        err = AudioUnitSetParameter(_ioUnit,
                                    kBandpassParam_CenterFrequency,
                                    kAudioUnitScope_Global,
                                    0,
                                    bandWidthCenter,
                                    0);
        NSAssert1(err == noErr, @"Error enabling bandwidth center: %hd", err);
        
        UInt32 bandWidthEdges = 100;
        err = AudioUnitSetParameter(_ioUnit,
                                   kBandpassParam_Bandwidth,
                                   kAudioUnitScope_Global,
                                   0,
                                   bandWidthEdges,
                                   0);
        NSAssert1(err == noErr, @"Error enabling bandwidth edges: %hd", err);
        */
        // Apply format to input of ioUnit
        err = AudioUnitSetProperty(_ioUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input,
                             kOutputBus,
                             &stereoStreamFormat,
                             sizeof(stereoStreamFormat));
        NSAssert1(err == noErr, @"Error setting input ASBD: %hd", err);
        
        // Apply format to output of ioUnit
        err = AudioUnitSetProperty(_ioUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output,
                             kInputBus,
                             &stereoStreamFormat,
                             sizeof(stereoStreamFormat));
        NSAssert1(err == noErr, @"Error setting output ASBD: %hd", err);
        
        // Set hardware IO callback
        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = hardwareIOCallback;
        callbackStruct.inputProcRefCon = (__bridge void *)(self);
        err = AUGraphSetNodeInputCallback(auGraph,
                                          ioNode,
                                          kOutputBus,
                                          &callbackStruct);
        NSAssert1(err == noErr, @"Error setting IO callback: %hd", err);
        
        // Initialize AudioGraph
        err = AUGraphInitialize(auGraph);
        NSAssert1(err == noErr, @"Error initializing AUGraph: %hd", err);
        
        // Start audio unit
        err = AUGraphStart(auGraph);
        NSAssert1(err == noErr, @"Error starting AUGraph: %hd", err);

    }
    @catch (NSException *exception) {
        NSLog(@"Failed with exception: %@", exception);
    }
}


- (void) monitorSensors: (UIView *) view : (BOOL) enable {
    if (enable){
        if (!self->auGraph) {
            // Start IO communication
            [self startCollecting];
        }
        
        // Check that audio route is correct
        [self checkAudioStatus:view];
        
        // **** DEBUG ****
        NSLog(@"Sensor monitor STARTED");
    } else {
        // Stop IO communication
        if (self->auGraph) {
            [self stopCollecting];
        }
        
        // **** DEBUG ****
        NSLog(@"Sensor monitor STOPPED");
    }
}


- (void) startCollecting {
    // Set up audio associate sensor IO
    [self setUpSensorIO];
    
    // Register audio route change listner with notification callback
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListener:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    // Set Master Volume to 100%
    self.volumeSlider.value = 1.0f;
}


- (void) stopCollecting {
    // Unregister notification callbacks
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    
    Boolean isRunning = false;
    AUGraphIsRunning (auGraph, &isRunning);
    
    if (isRunning) {
        // Stop and release audio unit
        AUGraphStop(self->auGraph);
        AUGraphUninitialize(self->auGraph);
        self->auGraph = nil;
    }
    
    // Set Master Volume to 50%
    self.volumeSlider.value = 0.5f;
    
    
    /***************************************************************************
     **** DEBUG: Prints contents of input buffer to file. Doing this in     ****
     ****        will cut power out to micro down to 2.1 VDC.               ****
     ***************************************************************************/
    // Grabs Document directory path and file name
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSMutableString *docs_dir = [paths objectAtIndex:0];
    NSString *path = [NSString stringWithFormat:@"%@/HeadsetSensor_inData_100Hz_ManZero_5kHzOne_NoDelay_Repeat_NoBufDur.txt",docs_dir];
    const char *file = [path UTF8String];
    
    // Remove Last File
    NSError *err;
    NSString *lastPath = [NSString stringWithFormat:@"%@/HeadsetSensor_inData_100Hz_ManZero_5kHzOne_NoDelay_Repeat_NoProcessIO_NoBufDur.txt",docs_dir];
    [[NSFileManager defaultManager] removeItemAtPath:lastPath error:&err];
    
    if (err != noErr) {
        NSLog(@"ERROR: %@- Failed to delete last file: %@", err, lastPath);
    }
    
    // Open and write to file
    FILE *fp;
    fp = fopen(file, "w+");
    if (fp == NULL) {
        printf("ERROR processIO: Couldn't open file \"inputData.txt\"\n");
        exit(0);
    }
    
    int buf_indx = 0;
    for (buf_indx = 0; buf_indx < [self.rawInputData count]; buf_indx++) {
        fprintf(fp, "%d\n", (int)self.rawInputData[buf_indx]);
    }
    fclose(fp);

    NSLog(@"Data In decoded: %@", self.sensorData);
    /***************************************************************************
     **** DEBUG: Prints contents of input buffer to file. Doing this in     ****
     ****        will cut power out to micro down to 2.1 VDC.               ****
     ***************************************************************************/
}

- (void) checkAudioStatus: (UIView *) view {
    
}

/**
 *  Detects sensor (headset) connection by pulling the current input and output routes from the active AVAudioSession.
 *
 *  @return The function returns TRUE if audio route is the one used by sensor system and FALSE otherwise
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
 *  @param notification A NSNotification containing audio change reason
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
            
            // **** DEBUG ****
            NSLog(@"Sensor INSERTED");
            break;
            
        // Sensor removed
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            // Stop IO audio unit
            [self stopCollecting];
            
            // **** DEBUG ****
            NSLog(@"Sensor REMOVED");
            break;
            
        // Category changed from PlayAndRecord
        case AVAudioSessionRouteChangeReasonCategoryChange:
            // Stop IO audio unit
            [self stopCollecting];
            
            // **** DEBUG ****
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
             message:@"Please insert the GSF sensor to collect sensorIO data. Pressing \"Cancel\" will end sensor data collection."
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
 *  @param bufferList sensorIO is list of buffers containing the input from the mic line
 */
- (void) processIO: (AudioBufferList*) bufferList {
    for (int j = 0 ; j < bufferList->mNumberBuffers ; j++) {
        AudioBuffer sourceBuffer = bufferList->mBuffers[j];
        SInt16 *buffer = (SInt16 *) bufferList->mBuffers[j].mData;
        
        for (int i = 0; i < (sourceBuffer.mDataByteSize / sizeof(sourceBuffer)); i++) {
            SInt16 maxBufferPoint = 0;
            SInt16 minBufferPoint = 0;
            
            [self.rawInputData addObject:[NSNumber numberWithInt:buffer[i]]];
           
            // Find min and max points in current buffer
            for (int j = 0; j < kSamplesPerCheck; j++) {
                maxBufferPoint = max(buffer[i+j], maxBufferPoint);
                minBufferPoint = min(buffer[i+j], minBufferPoint);
            }
            
            // Associate current bit value based on min/max values and check if it's the start bit
            if ( (maxBufferPoint > kHighMin && minBufferPoint < kLowMin) ) {
                self.curState = 1;
                // Only enters this statement for the rising edge of the start bit
                if (!self.startRise && !self.startBit) {
                    self.startRise = true;
                }
            } else {
                self.curState = 0;
            }
            
            // Check for falling edge of start bit
            if (self.curState == 0 && self.startRise) {
                    self.startBit = true;
                    self.startRise = false;
                    self.durationCount = 0;
            }
            
            // When start bit is set check for data
            if (self.startBit) {
                // Increment and check duration for low-low or high-high state transitions
                self.durationCount++;
                if (self.durationCount == 300) {
                    self.durationCount = 0;
                    if (self.curState == self.lastState) {
                        self.lastState = self.curState;
                    }
                }
                // Check for state flip against last state value
                if (self.curState != self.lastState) {
                    if (self.curState == 1) {
                        [self.sensorData addObject:[NSNumber numberWithInt:kManchesterOne]];
                    } else {
                        [self.sensorData addObject:[NSNumber numberWithInt:kManchesterZero]];
                    }
                    self.lastState = self.curState;
                }
            }
        }
        
        // Fill output buffer with commands and set new output data flag

    }
}

- (NSMutableArray*) collectData {
    return self.sensorData;
}

@end
