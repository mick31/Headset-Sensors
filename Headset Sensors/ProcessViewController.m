//
//  ProcessViewController.m
//  Headset Sensors
//
//  Created by Mick Bennett on 4/30/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "ProcessViewController.h"
#import "GSFSensorIOController.h"

@interface ProcessViewController ()

@property GSFSensorIOController *sensorIO;
@property (weak, nonatomic) IBOutlet UILabel *decodedDataLabel;

@end

@implementation ProcessViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    if (self.sensorIOToggle) {
        self.sensorIO = [[GSFSensorIOController alloc] initWithView:self.view];
        [self.sensorIO monitorSensors:YES];
    }
}

- (void) viewWillDisappear:(BOOL)animated {
    // Stop monitoring process and free sensorIO
    [self.sensorIO monitorSensors:NO];
}

- (IBAction)processButtPush:(id)sender {
    NSMutableArray *data = [[NSMutableArray alloc]init];
    // Grab collected sensor data
    data = self.sensorIO.collectSensorData;
    
    // Display data
    if ([data count] != 0) {
        self.decodedDataLabel.text = [NSString stringWithFormat:@"%@ %@ %@", data[0], data[1], data[2]];
    } else {
        self.decodedDataLabel.text = [NSString stringWithFormat:@"No Data"];
    }
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
