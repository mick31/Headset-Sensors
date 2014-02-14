//
//  ToneGenerator.m
//  Headset Sensors
//
//  Created by Mick on 2/3/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ToneGenerator.h"
#import <AudioToolbox/AudioToolbox.h>

OSStatus RenderTone (
    void *inRefcon,
    AudioUnitRenderActionFlags  *ioActionFlags,
    const AudioTimeStamp        *inTimeStamp,
    UInt32                      inBusNumber,
    UInt32                      inNumberFrames,
    AudioBufferList             *ioData) {
    // Set Tone parameters
    // Starting with a fixed amplitude. ***CHANGE LATER: Replace with Volume***
    const double amplitude = 0.5;
    
    ToneGenerator *tone = (ToneGenerator *) CFBridgingRelease(inRefcon);
    
    double theta = tone.theta;
    double theta_increment = 2.0 * M_PI * tone.frequency / tone.sampleRate;
    
    // One tone so only one buffer needed
    const int channel = 0;
    Float32 *buff = (Float32 *) ioData->mBuffers[channel].mData;
    
    // Create sample wave from tone info
    for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
        buff[frame] = sin(theta) * amplitude;
        
        theta += theta_increment;
        if (theta > 2.0 * M_PI) {
            theta -= 2.0 *M_PI;
        }
    }
    
    // Store new theta
    tone.theta = theta;
    
    /*************
     *** Debug ***
     *************/
    NSLog(@"RenderTone: Made it!");
    
    return noErr;
}


@implementation ToneGenerator

@synthesize powerTone = _powerTone;
@synthesize frequency = _frequency;
@synthesize sampleRate = _sampleRate;
@synthesize theta = _theta;

// Creates a tone unit
- (void)createToneUnit {
    // Configure the search parameters to find the default playback output unit
    // (aka kAudioUnitSubType_RemoteIO)
    AudioComponentDescription defaultOutputDesciption;
    defaultOutputDesciption.componentFlags = 0;
    defaultOutputDesciption.componentFlagsMask = 0;
    defaultOutputDesciption.componentType = kAudioUnitType_Output;
    defaultOutputDesciption.componentSubType = kAudioUnitSubType_RemoteIO;
    defaultOutputDesciption.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Get the default playback output unit
    AudioComponent defaultOutput = AudioComponentFindNext(NULL, &defaultOutputDesciption);
    NSAssert(defaultOutput, @"Can't find default output");
    
    // Create a new unit based on default output
    OSErr err = AudioComponentInstanceNew(defaultOutput, &_powerTone);
    NSAssert1(_powerTone, @"Error creating unit: %hd", err);
    
    // Send power tone to rendering function
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
    
    // Set format to 32 bit, single channel, floating point, linear PCM
    const int float_eq_four_bytes = 4;
    const int byte_eq_eight_bits = 8;
    AudioStreamBasicDescription streamFormat;
    streamFormat.mSampleRate = _sampleRate;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    streamFormat.mBytesPerPacket = float_eq_four_bytes;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerFrame = byte_eq_eight_bits;
    streamFormat.mChannelsPerFrame = 1;
    streamFormat.mBitsPerChannel = float_eq_four_bytes * byte_eq_eight_bits;
    err = AudioUnitSetProperty(_powerTone,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Input,
                               0,
                               &streamFormat,
                               sizeof(AudioStreamBasicDescription));
    NSAssert1(err == noErr, @"Error setting stream format: %hd", err);
    
    /*************
     *** Debug ***
     *************/
    NSLog(@"createTone: Made it!");
}

// Turns tone on and off
- (void) togglePowerOn: (BOOL)state {
    if ( state == NO) {
        // Stop power tone
        AudioOutputUnitStop(_powerTone);
        AudioUnitUninitialize(_powerTone);
        _powerTone = nil;
        
        // Debug
        NSLog(@"togglePowerOn: Off");
    } else {
        // Start power tone
        [self createToneUnit];
        
        // Initialize the audio unit
        OSErr err = AudioUnitInitialize(_powerTone);
        NSAssert1(err == noErr, @"Error initializing power tone: %hd", err);
        
        // Start playback
        err = AudioOutputUnitStart(_powerTone);
        NSAssert1(err == noErr, @"Error starting power tone: %hd", err);
        
        /*************
         *** Debug ***
         *************/
        NSLog(@"togglePowerOn: On");
    }
    /*************
     *** Debug ***
     *************/
    NSLog(@"togglePowerOn: Made It!");
}

@end
