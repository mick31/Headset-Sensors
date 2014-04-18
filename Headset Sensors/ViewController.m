//
//  ViewController.m
//  Headset Sensors
//
//  Created by Mick on 1/24/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ViewController.h"
#import "GSFSensorIOController.h"

@interface ViewController ()

@property GSFSensorIOController *sensorIO;
@property NSTimer* oneSecondTimer;

@end

@implementation ViewController

- (void) viewDidLoad {
    [super viewDidLoad];
    self.sensorIO = [[GSFSensorIOController alloc] init];
}

- (IBAction)collectDataButton:(id)sender {
    if (self.monitorSensorSwitch.on) {
        [self.sensorIO monitorSensors:self.view :YES];
    } else {
        [self.sensorIO monitorSensors:self.view :NO];
    }
}

- (void) oneSecondCallback: (NSTimer*) timer {
    
}

@end
