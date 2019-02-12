#import "MoviePlayerViewController.h"

@interface MoviePlayerViewController ()
    
@end

@implementation MoviePlayerViewController



- (void)willEnterFullscreen:(NSNotification*)notification {
    NSLog(@"willEnterFullscreen");
    self.isFullScreen = YES;
    [self.moviePlayer.moviePlayer setFullscreen:NO animated:NO];
    [self.moviePlayer.moviePlayer setControlStyle:MPMovieControlStyleEmbedded];
}

- (void)enteredFullscreen:(NSNotification*)notification {
    NSLog(@"enteredFullscreen");
}

- (void)willExitFullscreen:(NSNotification*)notification {
    NSLog(@"willExitFullscreen");
    self.isFullScreen = NO;
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    
    if(orientation == 0) { //Default orientation
        //UI is in Default (Portrait) -- this is really a just a failsafe.
        [self.view addSubview:self.navBarZanichelli];
    } else if(orientation == UIInterfaceOrientationPortrait) {
        //Do something if the orientation is in Portrait
        [self.view addSubview:self.navBarZanichelli];
    } else if(orientation == UIInterfaceOrientationLandscapeLeft) {
        // Do something if Left
        [self.navBarZanichelli removeFromSuperview];
    } else if(orientation == UIInterfaceOrientationLandscapeRight) {
        //Do something if right
        [self.navBarZanichelli removeFromSuperview];
    }
    
//    if (toInterfaceOrientation == UIDeviceOrientationPortrait){
//        [self.view addSubview:self.navBarZanichelli];
//    } else {
//        [self.navBarZanichelli removeFromSuperview];
//    }
}

- (void)exitedFullscreen:(NSNotification*)notification {
    NSLog(@"exitedFullscreen");
    
    //[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)movieEventFullscreenHandler:(NSNotification*)notification {
    [self.moviePlayer.moviePlayer setFullscreen:NO animated:NO];
    [self.moviePlayer.moviePlayer setControlStyle:MPMovieControlStyleEmbedded];
}

- (void)playbackFinished:(NSNotification*)notification {
    NSNumber* reason = [[notification userInfo] objectForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    
    if (!self.isFullScreen){
        switch ([reason intValue]) {
            case MPMovieFinishReasonPlaybackEnded:
            [self dismissModalViewControllerAnimated:YES];
            break;
            case MPMovieFinishReasonPlaybackError:
            break;
            case MPMovieFinishReasonUserExited:
            [self dismissModalViewControllerAnimated:YES];
            break;
            default:
            break;
        }
    }
}

-(void)chiudiPlayer {
    //[self dismissModalViewControllerAnimated:YES];
}

-(void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerWillEnterFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerWillExitFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerDidEnterFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerDidExitFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterFullscreen:) name:MPMoviePlayerWillEnterFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willExitFullscreen:) name:MPMoviePlayerWillExitFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteredFullscreen:) name:MPMoviePlayerDidEnterFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(exitedFullscreen:) name:MPMoviePlayerDidExitFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    
    //Because we have to wait until controllers are shown
    //[self performSelector:@selector(hideFullscreenButton) withObject:self.moviePlayer afterDelay:0.5];
}
    
-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerWillEnterFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerWillExitFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerDidEnterFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerDidExitFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    
    //[[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"CHIUDO IL PLAYER");
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.moviePlayer = [[MPMoviePlayerViewController alloc] initWithContentURL:self.url];

    [self.moviePlayer.view setFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
    [self.view addSubview:self.moviePlayer.view];
    [self.view addSubview:self.navBarZanichelli];
    [self.moviePlayer.moviePlayer prepareToPlay];
    
    self.moviePlayer.moviePlayer.movieSourceType = MPMovieSourceTypeFile;
    self.moviePlayer.moviePlayer.controlStyle = MPMovieControlStyleEmbedded;
    self.moviePlayer.moviePlayer.scalingMode = MPMovieScalingModeAspectFit;
    self.moviePlayer.moviePlayer.repeatMode = MPMovieRepeatModeNone;
    
    [self.moviePlayer.moviePlayer play];
    //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chiudiPlayer) name:UIApplicationWillResignActiveNotification object:nil];
    self.isFullScreen = NO;
}

-(void) hideFullscreenButton{
    //Hide full screen mode button
    //[self hideFullscreenSubview:self.moviePlayer.view.subviews];
//    UIView *fsbutton = [[self.moviePlayer view] viewWithTag:512];
//    [fsbutton setHidden:YES];
    
//    if (self.isFullScreen){
//        self.isFullScreen = NO;
//        [self dismissModalViewControllerAnimated:NO];
//    }
    
}

-(void) hideFullscreenSubview:(NSArray*)arr{
    for(UIView *v in arr){
        if((v.tag==1001) || (v.tag==1000) || (v.tag==1002) || (v.tag==1006) || (v.tag==1004) || (v.tag==1005)){
            v.hidden=TRUE;
        }
        if([v.subviews count]>0) {
            NSLog(@"VISTA2 *****: %ld",(long)v.tag);
            [self hideFullscreenSubview:v.subviews];
        } else {
            NSLog(@"VISTA *****: %ld",(long)v.tag);
            if(v.tag==1001 ){
                v.hidden=TRUE;
            }
        }
            
    }
}



- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    NSLog(@"RUOTO IL PLAYER");
    
    if (toInterfaceOrientation == UIDeviceOrientationPortrait){
        [self.view addSubview:self.navBarZanichelli];
    } else {
        [self.navBarZanichelli removeFromSuperview];
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    NSLog(@"RUOTATO IL PLAYER: W:%f H:%f",self.view.frame.size.width,self.view.frame.size.height);
    
    
}


@end
