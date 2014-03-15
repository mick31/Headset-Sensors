//
//  AudioIOController.m
//  Headset Sensors
//
//  Created by Mick Bennett on 3/14/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "AudioIOController.h"
#import <AudioToolbox/AudioToolbox.h>

#define kOutputBus 0
#define kInputBus 1

AudioIOController* iosAudio;

void checkStatus(int status){
	if (status) {
		printf("Status not 0! %d\n", status);
        //		exit(1);
	}
}

/**
 This callback is called when new audio data from the microphone is
 available.
 */
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
	
    status = AudioUnitRender([audioIO inputAudioUnit],
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &bufferList);
	checkStatus(status);
	
    // Now, we have the samples we just read sitting in buffers in bufferList
	// Process the new data
	[audioIO processInputAudio:&bufferList];
	
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
    
	// This is a mono tone generator so we only need the first buffer
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


@implementation AudioIOController

- (id) init {
	self = [super init];
	
	OSStatus status;
	
	// Describe audio component
	AudioComponentDescription desc;
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	
	// Get component
	AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
	
	// Get audio units
	status = AudioComponentInstanceNew(inputComponent, &_powerOutAudioUnit);
	checkStatus(status);
	
	// Enable IO for recording
	UInt32 flag = 1;
	status = AudioUnitSetProperty([audioIO inputAudioUnit],
								  kAudioOutputUnitProperty_EnableIO,
								  kAudioUnitScope_Input,
								  kInputBus,
								  &flag,
								  sizeof(flag));
	checkStatus(status);
	
	// Enable IO for playback
	status = AudioUnitSetProperty([audioIO powerOutAudioUnit],
								  kAudioOutputUnitProperty_EnableIO,
								  kAudioUnitScope_Output,
								  kOutputBus,
								  &flag,
								  sizeof(flag));
	checkStatus(status);
	
	// Describe input format
	AudioStreamBasicDescription audioInFormat;
	audioInFormat.mSampleRate			= 44100.00;
	audioInFormat.mFormatID			= kAudioFormatLinearPCM;
	audioInFormat.mFormatFlags		= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	audioInFormat.mFramesPerPacket	= 1;
	audioInFormat.mChannelsPerFrame	= 1;
	audioInFormat.mBitsPerChannel		= 16;
	audioInFormat.mBytesPerPacket		= 2;
	audioInFormat.mBytesPerFrame		= 2;
	
    // Describe output format
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
    
	// Apply formats
	status = AudioUnitSetProperty([audioIO inputAudioUnit],
								  kAudioUnitProperty_StreamFormat,
								  kAudioUnitScope_Output,
								  kInputBus,
								  &audioInFormat,
								  sizeof(audioInFormat));
	checkStatus(status);
    
	status = AudioUnitSetProperty([audioIO powerOutAudioUnit],
								  kAudioUnitProperty_StreamFormat,
								  kAudioUnitScope_Input,
								  kOutputBus,
								  &streamFormat,
								  sizeof(streamFormat));
	checkStatus(status);
	
	
	// Set input callback
	AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProc = recordingCallback;
	callbackStruct.inputProcRefCon = (__bridge void *)(self);
	status = AudioUnitSetProperty([audioIO inputAudioUnit],
								  kAudioOutputUnitProperty_SetInputCallback,
								  kAudioUnitScope_Global,
								  kInputBus,
								  &callbackStruct,
								  sizeof(callbackStruct));
	checkStatus(status);
	
	// Set output callback
	callbackStruct.inputProc = playbackCallback;
	callbackStruct.inputProcRefCon = (__bridge void *)(self);
	status = AudioUnitSetProperty([audioIO powerOutAudioUnit],
								  kAudioUnitProperty_SetRenderCallback,
								  kAudioUnitScope_Global,
								  kOutputBus,
								  &callbackStruct,
								  sizeof(callbackStruct));
	checkStatus(status);
	
		
	// Allocate our own buffers (1 channel, 16 bits per sample, thus 16 bits per frame, thus 2 bytes per frame).
	// Practice learns the buffers used contain 512 frames, if this changes it will be fixed in processAudio.
	_micBuffer.mNumberChannels = 1;
	_micBuffer.mDataByteSize = 512 * 2;
	_micBuffer.mData = malloc( 512 * 2 );
	
	// Initialise
	status = AudioUnitInitialize([audioIO inputAudioUnit]);
	checkStatus(status);
    
    status = AudioUnitInitialize([audioIO powerOutAudioUnit]);
	checkStatus(status);
    
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
    
    // Add audio route change listner
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListener:) name:AVAudioSessionRouteChangeNotification object:nil];
	
	return self;
}

- (void)togglePower:(BOOL)powerOn {
	if (!powerOn) {
        // Set Master Volume to 50%
        self.volumeSlider.value = 0.5f;
        
		// Stop and release power tone
        AudioOutputUnitStop([self.powerOutAudioUnit]);
		AudioUnitUninitialize(self.powerOutAudioUnit);
		AudioComponentInstanceDispose(self.powerOutAudioUnit);
		self.powerOutAudioUnit = nil;
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


- (void)processInputAudio: (AudioBufferList*) bufferlist {
    
}



@end
