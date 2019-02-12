#import "LinkViewController.h"

@interface LinkViewController ()
    
@end

@implementation LinkViewController

-(void)chiudiPlayer {
    //[self dismissModalViewControllerAnimated:YES];
}

-(void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    //Because we have to wait until controllers are shown
    //[self performSelector:@selector(hideFullscreenButton) withObject:self.moviePlayer afterDelay:0.5];
}
    
-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    //[[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"CHIUDO IL PLAYER");
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 64, self.view.frame.size.width, self.view.frame.size.height-64)];

    [self.view addSubview:self.webView];
    [self.view addSubview:self.navBarZanichelli];
    self.webView.delegate = self;
    [self.webView loadRequest:self.url];
    
    //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chiudiPlayer) name:UIApplicationWillResignActiveNotification object:nil];
}

//- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
//    NSLog(@"RUOTATO IL PLAYER: W:%f H:%f",self.view.frame.size.width,self.view.frame.size.height);
//}

- (NSUInteger)supportedInterfaceOrientations
{
   return UIInterfaceOrientationMaskPortrait + UIInterfaceOrientationMaskPortraitUpsideDown;
}

@end
