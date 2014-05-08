//
//  GSFSensorIOController.m
//  GSFDataCollecter
//
//  Created by Mick Bennett on 3/30/14.
//  Copyright (c) 2014 Michael Baptist - LLNL. All rights reserved.
//

#import "GSFSensorIOController.h"

// Defined Macros
#define OUTPUTBUS          0
#define INPUTBUS           1
#define SAMPLESPERCHECK    10
#define HIGHMIN            30000
#define LOWMIN             -30000
#define SAMPLERATE         44100
#define LOWSTATE           0
#define HIGHSTATE          1

#ifndef min
#define min( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif

#ifndef max
#define max( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

// Private interface
@interface GSFSensorIOController () {
    AUGraph auGraph;
    AUNode ioNode;
    AUNode highPassNode;
}
@property (assign) AudioUnit ioUnit;            // Audio unit handles in IO
@property AVAudioSession *sensorAudioSession;   // Pointer to sensor required audio session
@property NSMutableArray *inputDataDecoded;     // Decoded input
@property NSMutableArray *sensorData;           // Final sensor data
@property NSMutableArray *rawInputData;         // Raw input data for DEBUG printing
@property double sampleRate;                    // Sample rate
@property double bufferDuration;
@property double sinPhase;                      // Latest point of sine wave for power tone
@property BOOL newDataOut;                      // Flag for new communication to micro
@property BOOL startEdge;                       // First rise of input signal signifies start edge
@property int curState;                         // Current input state value (HIGH or LOW)
@property int lastState;                        // Last input state to compare with current state
@property int secondLastState;                  // Second to last input to check for pattern flaws
@property int doubleState;                      // Marks last double state (HIGH-HIGH or LOW-LOW)
@property int halfPeriodCount;                  // Count for half of the expected input period
@property int halfPeriodTC;                     // TC for half period count
@property BOOL firstHalfPeriod;                 // First half period for start edge
@property UIView *associatedView;               // *** View for ONE view alert system ***

- (void) grabInput: (AudioBufferList*) bufferList;

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
                                      INPUTBUS,
                                      inNumberFrames,
                                      ioData);
    
    
    [sensorIO grabInput:ioData];
    // Process input data
    //[sensorIO processIO:ioData];
    
    // Set up power tone attributes
    float freq = 20000.00f;
    float sampleRate = sensorIO.sampleRate;
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
- (id) init :(UIView *) view {
    self = [super init];
    if (!self) {
        NSLog(@"ERROR init: GSFSensorIOController Failed to initialize");
        return nil;
    }
    
    // Set up AVAudioSession
    self.sensorAudioSession = [AVAudioSession sharedInstance];
    BOOL success;
    NSError *error;
    
    // Set audio category
    success = [self.sensorAudioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
	if (!success) NSLog(@"ERROR init: AVAudioSession failed setting category- %@", error);
    
    // Request preferred hardware sample rate
    self.sampleRate = SAMPLERATE;
    success = [self.sensorAudioSession setPreferredSampleRate:self.sampleRate error:&error];
	if (!success) NSLog(@"ERROR init: AVAudioSession failed setting sample rate- %@", error);
    
    // Set buffer duration. Idealy it would be 5 ms for low latency
    success = [self.sensorAudioSession setPreferredIOBufferDuration:0.005 error:&error];
	if (!success) NSLog(@"ERROR init: AVAudioSession failed setting buffer duration- %@", error);
    
    // Make the sensor AVAudioSession active
    success = [self.sensorAudioSession setActive:YES error:&error];
    if(!success) NSLog(@"ERROR init: AVAudioSession failed activating- %@", error);
    
    // Grab actual sample rate and buffer duration
    self.sampleRate = [self.sensorAudioSession sampleRate];
    if(self.sampleRate != 44100.00) NSLog(@"WARNING init: Actual sample rate is: %f", self.sampleRate);
    self.bufferDuration = [self.sensorAudioSession IOBufferDuration];
    if(self.bufferDuration != 0.005) NSLog(@"WARNING init: Actual buffer duration is: %f", self.bufferDuration);
    
    // Add pointer to associated UIView controlerr for alerts
    self.associatedView = view;
    
    // Set up master volume controller
    MPVolumeView *volumeView = [MPVolumeView new];
    volumeView.showsRouteButton = NO;
    volumeView.showsVolumeSlider = NO;
    [self.associatedView addSubview:volumeView];
    
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
    self.startEdge = false;
    self.firstHalfPeriod = true;
    self.halfPeriodTC = 220;                 // Should make this a result of a calibration period
                                                // for greater accuracy
    self.sensorData = [[NSMutableArray alloc] init];
    self.inputDataDecoded = [[NSMutableArray alloc] init];
    self.rawInputData = [[NSMutableArray alloc] init];
    
    // RemoteIO component description
    AudioComponentDescription ioUnitdesc;
    bzero(&ioUnitdesc, sizeof(AudioComponentDescription));
    ioUnitdesc.componentType          = kAudioUnitType_Output;
    ioUnitdesc.componentSubType       = kAudioUnitSubType_RemoteIO;
    ioUnitdesc.componentManufacturer  = kAudioUnitManufacturer_Apple;
    ioUnitdesc.componentFlags         = 0;
    ioUnitdesc.componentFlagsMask     = 0;
    
    // High pass filter component description
    AudioComponentDescription inputHighPassDesc;
    bzero(&inputHighPassDesc, sizeof(AudioComponentDescription));
    inputHighPassDesc.componentType          = kAudioUnitType_Effect;
    inputHighPassDesc.componentSubType       = kAudioUnitSubType_HighPassFilter;
    inputHighPassDesc.componentManufacturer  = kAudioUnitManufacturer_Apple;
    
    // Stereo ASBD
    AudioStreamBasicDescription stereoStreamFormat;
    bzero(&stereoStreamFormat, sizeof(AudioStreamBasicDescription));
    stereoStreamFormat.mSampleRate          = SAMPLERATE;
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
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to create AUGraph: %hd", err);
        
        // Add nodes to AUGraph
        err = AUGraphAddNode(auGraph,
                             &ioUnitdesc,
                             &ioNode);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to add AUNode: %hd", err);
        /*
        err = AUGraphAddNode(auGraph,
                             &inputHighPassDesc,
                             &highPassNode);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to add AUNode: %hd", err);
        */
        // Open AUGraph
        err = AUGraphOpen(auGraph);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to open AUGraph: %hd", err);
        
        // Add AUGraph nodes info
        err = AUGraphNodeInfo(auGraph,
                              ioNode,
                              NULL,
                              &_ioUnit);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to add node info: %hd", err);
        /*
        err = AUGraphNodeInfo(auGraph,
                              highPassNode,
                              NULL,
                              &_ioUnit);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to add node info: %hd", err);
        
        // Connect highPassNode output to ioNode input
        err = AUGraphConnectNodeInput(auGraph,
                                      highPassNode, // Source node
                                      0,            // Source node output bus num
                                      ioNode,       // Dest node
                                      0);           // Dest node input bus num

        */
        // Enable input, which is disabled by default.
        UInt32 enabled = 1;
        err = AudioUnitSetProperty(_ioUnit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input,
                             INPUTBUS,
                             &enabled,
                             sizeof(enabled));
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to enable input: %hd", err);
        
        // Apply format to input of ioUnit
        err = AudioUnitSetProperty(_ioUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input,
                             OUTPUTBUS,
                             &stereoStreamFormat,
                             sizeof(stereoStreamFormat));
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to set input ASBD: %hd", err);
        
        // Apply format to output of ioUnit
        err = AudioUnitSetProperty(_ioUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output,
                             INPUTBUS,
                             &stereoStreamFormat,
                             sizeof(stereoStreamFormat));
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to set output ASBD: %hd", err);
        
        // Set hardware IO callback
        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = hardwareIOCallback;
        callbackStruct.inputProcRefCon = (__bridge void *)(self);
        err = AUGraphSetNodeInputCallback(auGraph,
                                          ioNode,
                                          OUTPUTBUS,
                                          &callbackStruct);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to set IO callback: %hd", err);
        
        // Initialize AudioGraph
        err = AUGraphInitialize(auGraph);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to initialize AUGraph: %hd", err);
        /*
        // Set highpass filter for input.
        UInt32 highPassfilterCutoff = 5000;
        err = AudioUnitSetParameter(_ioUnit,
                                    kHipassParam_CutoffFrequency,
                                    kAudioUnitScope_Global,
                                    0,
                                    highPassfilterCutoff,
                                    0);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to enable highpass filter: %hd", err);
        */
        // Start audio unit
        err = AUGraphStart(auGraph);
        NSAssert1(err == noErr, @"ERROR setUpSensorIO: failed to start AUGraph: %hd", err);

    }
    @catch (NSException *exception) {
        NSLog(@"Failed with exception: %@", exception);
    }
}


- (void) monitorSensors:  (BOOL) enable {
    if (enable){
        if (!self->auGraph) {
            // Start IO communication
            [self startCollecting];
        }
        
        // Check that audio route is correct
        [self checkAudioStatus];
        
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
}

/**
 *  Checks for flags set by audioInterruptionCallback and by manual isSensorConnected function to determine if the audio route has changed in a way that will disrupt the collection process.
 */
- (void) checkAudioStatus {
    
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

- (void) grabInput: (AudioBufferList*) bufferList {
    for (int j = 0 ; j < bufferList->mNumberBuffers ; j++) {
        AudioBuffer sourceBuffer = bufferList->mBuffers[j];
        SInt16 *buffer = (SInt16 *) bufferList->mBuffers[j].mData;
        
        for (int i = 0; i < (sourceBuffer.mDataByteSize / sizeof(sourceBuffer)); i++) {
            // Array of raw data points for printing to a file
            [self.rawInputData addObject:[NSNumber numberWithInt:buffer[i]]];
        }
    }

}

/**
 *  Process Input readinga and fills right channel output buffer with any response
 *
 *  @param bufferList sensorIO is list of buffers containing the input from the mic line
 */
- (void) processIO {
/*    for (int j = 0 ; j < bufferList->mNumberBuffers ; j++) {
        AudioBuffer sourceBuffer = bufferList->mBuffers[j];
        SInt16 *buffer = (SInt16 *) bufferList->mBuffers[j].mData;
        
        for (int i = 0; i < (sourceBuffer.mDataByteSize / sizeof(sourceBuffer)); i++) {
            SInt16 maxBufferPoint = 0;
            SInt16 minBufferPoint = 0;
            
            // DEBUG: Array of raw data points for printing to a file
            [self.rawInputData addObject:[NSNumber numberWithInt:buffer[i]]];
           
            // Find min and max points in current buffer
            for (int j = 0; j < SAMPLESPERCHECK; j++) {
                maxBufferPoint = max(buffer[i+j], maxBufferPoint);
                minBufferPoint = min(buffer[i+j], minBufferPoint);
            }
            
            // Associate current bit value based on min/max values and check if it's the start bit
            if ( (maxBufferPoint > HIGHMIN && minBufferPoint < LOWMIN) ) {
                self.curState = HIGHSTATE;
                // Only enters this statement for the rising edge of the start signal
                if (!self.startEdge) {
                    self.startEdge = true;
                    self.firstHalfPeriod = true;
                    self.halfPeriodCount = 0;
                }
            } else {
                self.curState = LOWSTATE;
            }
            
            // When start bit is set check for data
            if (self.startEdge) {
                // Increment and check if half period is finished
                self.halfPeriodCount++;
                if (self.halfPeriodCount == self.halfPeriodTC) {
                    // Reset half period count
                    self.halfPeriodCount = 0;
                    
                    // Check if this is the first pass after the start edge
                    if (self.firstHalfPeriod) {
                        if (self.curState == 1) self.doubleState = 1;
                        self.lastState = self.curState;
                        self.secondLastState = self.lastState;
                        self.firstHalfPeriod = false;
                    }
                    // Check for bit flip
                    else if (self.curState != self.lastState && self.doubleState != self.curState) {
                        [self.inputDataDecoded addObject:[NSNumber numberWithInt:self.curState]];
                        self.lastState = self.curState;
                        self.secondLastState = self.lastState;
                    }
                    // Check for non bit flip aka double state
                    else if (self.curState == self.lastState) {
                        self.doubleState = self.curState;
                        self.secondLastState = self.lastState;
                        self.lastState = self.curState;
                    }
                }
                
                // Reset input stream last three states are equivalent
                if (self.curState == self.lastState == self.secondLastState) {
                    self.startEdge = false;
                }
            }
        }
        
        // Fill output buffer with commands and set new output data flag

    }
  */
    
    // Stop sensor data collection
    [self monitorSensors: NO];
    
    for (int i = 0; i < [self.rawInputData count]; i+=SAMPLESPERCHECK) {
        int maxBufferPoint = 0;
        int minBufferPoint = 0;
        
        // Find min and max points in current buffer
        for (int j = 0; j < SAMPLESPERCHECK && i+j < [self.rawInputData count]; j++) {
            NSNumber *tmp = self.rawInputData[i+j];
            maxBufferPoint = max(tmp.intValue, maxBufferPoint);
            minBufferPoint = min(tmp.intValue, minBufferPoint);
        }
        
        // Associate current bit value based on min/max values and check if it's the start bit
        if ( (maxBufferPoint > HIGHMIN && minBufferPoint < LOWMIN) ) {
            self.curState = HIGHSTATE;
            // Only enters this statement for the rising edge of the start signal
            if (!self.startEdge) {
                self.startEdge = true;
                self.firstHalfPeriod = true;
                self.halfPeriodCount = 0;
            }
        } else {
            self.curState = LOWSTATE;
        }
        
        // When start bit is set check for data
        if (self.startEdge) {
            // Increment and check if half period is finished
            self.halfPeriodCount+=SAMPLESPERCHECK;
            if (self.halfPeriodCount >= self.halfPeriodTC) {
                // Reset half period count
                self.halfPeriodCount = 0;
                
                // Check if this is the first pass after the start edge
                if (self.firstHalfPeriod) {
                    if (self.curState == HIGHSTATE) self.doubleState = HIGHSTATE;
                    self.lastState = self.curState;
                    self.secondLastState = self.lastState;
                    self.firstHalfPeriod = false;
                }
                // Check for bit flip
                else if (self.curState != self.lastState && self.doubleState != self.curState) {
                    [self.inputDataDecoded addObject:[NSNumber numberWithInt:self.curState]];
                    self.lastState = self.curState;
                    self.secondLastState = self.lastState;
                }
                // Check for non bit flip aka double state
                else if (self.curState == self.lastState) {
                    self.doubleState = self.curState;
                    self.secondLastState = self.lastState;
                    self.lastState = self.curState;
                }
            }
            
            // Reset input stream last three states are equivalent
            if (self.curState == self.lastState == self.secondLastState) {
                self.startEdge = false;
            }
        }
    }

    
    /***************************************************************************
     **** DEBUG: Prints contents of input buffer to file. Doing this in     ****
     ****        will cut power out to micro down to 2.1 VDC.               ****
     ***************************************************************************/
    // Grabs Document directory path and file name
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSMutableString *docs_dir = [paths objectAtIndex:0];
    /**/
    // New file to add
    NSString *path = [NSString stringWithFormat:@"%@/HeadsetSensor_in_25Hz_15kHzOne_0xDEADBEEF_CRC_SE_LM_44kSR_i5s.txt",docs_dir];
    const char *file = [path UTF8String];
    /**/
    // Remove last File
    NSError *err;
    NSString *lastPath = [NSString stringWithFormat:@"%@/HeadsetSensor_in_25Hz_15kHzOne_0xDEADBEEF_CRCreg8_SE_LM_44kSR_i5s.txt",docs_dir];
    [[NSFileManager defaultManager] removeItemAtPath:lastPath error:&err];
    
    if (err != noErr) {
        NSLog(@"ERROR: %@- Failed to delete last file: %@", err, lastPath);
    }
    /**/
    // Open and write to new file
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
    /**/
    // Print the decoded input data
    NSLog(@"Data In decoded: %@", self.inputDataDecoded);
    /***************************************************************************
     **** DEBUG: Prints contents of input buffer to file. Doing this in     ****
     ****        will cut power out to micro down to 2.1 VDC.               ****
     ***************************************************************************/
}

/**
 *  Decodes input from micro and returns an NSMutableArray of the sensor readings.
 *
 *  @return An NSMutableArray containing the decoded sensor data.
 */
- (NSMutableArray*) collectSensorData {
    // Process raw intput buffer
    [self processIO];
    
    // Return collected result
    return self.sensorData;
}

@end
