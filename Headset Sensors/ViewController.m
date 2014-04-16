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

@end

@implementation ViewController

- (void) viewDidLoad {
    [super viewDidLoad];
    self.sensorIO = [[GSFSensorIOController alloc] init];
}

- (IBAction)collectDataButton:(id)sender {
    if (self.monitorSensorSwitch.on) {
        [self.sensorIO monitorSensors:YES];
    } else {
        [self.sensorIO monitorSensors:NO];
    }
}
@end
