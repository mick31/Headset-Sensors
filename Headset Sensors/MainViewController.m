//
//  MainViewController.m
//  Headset Sensors
//
//  Created by Mick Bennett on 4/30/14.
//  Copyright (c) 2014 Mick. All rights reserved.
//

#import "MainViewController.h"
#import "ProcessViewController.h"

@interface MainViewController ()

@property (weak, nonatomic) IBOutlet UISwitch *sensorToggle;

@end

@implementation MainViewController

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
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)collectButtPushed:(id)sender {
    if (self.sensorToggle.on) {
        [self performSegueWithIdentifier:@"processDataSegue" sender:self];
    }
}

/**/
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([[segue identifier] isEqualToString:@"processDataSegue"]) {
        ProcessViewController *child = (ProcessViewController*)segue.destinationViewController;
        child.sensorIOToggle = self.sensorToggle.on;
    }

}
/**/


@end
