
/*===============================================================================
 Copyright (c) 2012-2014 Qualcomm Connected Experiences, Inc. All Rights Reserved.
 
 Vuforia is a trademark of QUALCOMM Incorporated, registered in the United States
 and other countries. Trademarks of QUALCOMM Incorporated are used with permission.
 ===============================================================================*/
#import "AppDelegate.h"
#import "ViewController.h"
#import "GLResourceHandler.h"

#import <UIKit/UIKit.h>
#import "ImageTargetsViewController.h"
#import <Vuforia/Vuforia.h>
#import <Vuforia/TrackerManager.h>
#import <Vuforia/ObjectTracker.h>
#import <Vuforia/Trackable.h>
#import <Vuforia/TrackableResult.h>
#import <Vuforia/DataSet.h>
#import <Vuforia/CameraDevice.h>
#import <Vuforia/Vuforia_iOS.h>
#import <MediaPlayer/MediaPlayer.h>
#import "MoviePlayerViewController.h"

#import <Vuforia/VuMarkTemplate.h>
#import <Vuforia/VuMarkTarget.h>
#import <Vuforia/VuMarkTargetResult.h>

@interface ImageTargetsViewController ()

@property (assign, nonatomic) id<GLResourceHandler> glResourceHandler;


@end

#define isIOS11_1() ([[UIDevice currentDevice].systemVersion doubleValue]== 11.1)

@implementation ImageTargetsViewController

- (id)initWithOverlayOptions:(NSDictionary *)overlayOptions vuforiaLicenseKey:(NSString *)vuforiaLicenseKey
{
    NSLog(@"Vuforia Plugin :: INIT IMAGE TARGETS VIEW CONTROLLER");
    NSLog(@"Vuforia Plugin :: OVERLAY: %@", overlayOptions);
    NSLog(@"Vuforia Plugin :: LICENSE: %@", vuforiaLicenseKey);
    
    self.overlayOptions = overlayOptions;
    self.vuforiaLicenseKey = vuforiaLicenseKey;
    
    self = [self initWithNibName:nil bundle:nil];
    
    self.delaying = false;
    
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        NSLog(@"Vuoria Plugin :: vuforiaLicenseKey: %@", self.vuforiaLicenseKey);
        vapp = [[ApplicationSession alloc] initWithDelegate:self vuforiaLicenseKey:self.vuforiaLicenseKey];
        
        // Custom initialization
        self.title = @"Image Targets";
        
        // get whether the user opted to show the device icon
        
        // Create the EAGLView with the screen dimensions
        CGRect screenBounds = [[UIScreen mainScreen] bounds];
        viewFrame = screenBounds;
        
        // If this device has a retina display, scale the view bounds that will
        // be passed to Vuforia; this allows it to calculate the size and position of
        // the viewport correctly when rendering the video background
        if (YES == vapp.isRetinaDisplay) {
            viewFrame.size.width *= 2.0;
            viewFrame.size.height *= 2.0;
        }
        
        dataSetCurrent = nil;
        extendedTrackingIsOn = NO;
        
        // a single tap will trigger a single autofocus operation
        tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(autofocus:)];
        
        // we use the iOS notification to pause/resume the AR when the application goes (or come back from) background
        [[NSNotificationCenter defaultCenter]
         removeObserver:self
         name:UIApplicationWillResignActiveNotification
         object:nil];
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(pauseAR)
         name:UIApplicationWillResignActiveNotification
         object:nil];
        [[NSNotificationCenter defaultCenter]
         removeObserver:self
         name:UIApplicationDidBecomeActiveNotification
         object:nil];
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(resumeAR)
         name:UIApplicationDidBecomeActiveNotification
         object:nil];
        [self loadOverlay];
    }
    return self;
}

+ (UIColor *)colorFromHexString:(NSString *)hexString {
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

-(void) loadOverlay {
    if(!vapp.cameraIsStarted){
        [self performSelector:@selector(loadOverlay) withObject:nil afterDelay:0.1];
    }else{
        
        // set up the overlay back bar
        
        bool showDevicesIcon = [[self.overlayOptions objectForKey:@"showDevicesIcon"] integerValue];
        
        UIView *vuforiaBarView=[[UIView alloc]initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 75)];
        vuforiaBarView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5f];
        vuforiaBarView.tag = 8;
        [self.view addSubview:vuforiaBarView];
        
        // set up the close button
        UIImage * buttonImage = [UIImage imageNamed:@"close-button.png"];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [button addTarget:self action:@selector(buttonPressed) forControlEvents:UIControlEventTouchUpInside];
        [button setTitle:@"" forState:UIControlStateNormal];
        [button setBackgroundImage:buttonImage forState:UIControlStateNormal];
        button.frame = CGRectMake([[UIScreen mainScreen] bounds].size.width - 65, (vuforiaBarView.frame.size.height / 2.0) - 30, 60, 60);
        button.tag = 10;
        [vuforiaBarView addSubview:button];
        
        // if the device logo is set by the user
        if(showDevicesIcon) {
            UIImage *image = [UIImage imageNamed:@"iOSDevices.png"];
            UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
            imageView.frame = CGRectMake(10, (vuforiaBarView.frame.size.height / 2.0) - 25, 50, 50);
            imageView.tag = 11;
            [vuforiaBarView addSubview:imageView];
        }
        
        // set up the detail label
        UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 10, vuforiaBarView.frame.size.width / 2 - button.frame.size.width, 60)];
        [detailLabel setTextColor:[UIColor colorWithRed:0.74 green:0.74 blue:0.74 alpha:1.0]];
        [detailLabel setBackgroundColor:[UIColor clearColor]];
        [detailLabel setFont:[UIFont fontWithName: @"Trebuchet MS" size: 15.0f]];
        
        // get and set the overlay text (if passed by user). if the text is empty, make the back bar transparent
        NSString *overlayText = [self.overlayOptions objectForKey:@"overlayText"];
        
        [detailLabel setText: overlayText];
        detailLabel.lineBreakMode = NSLineBreakByWordWrapping;
        detailLabel.numberOfLines = 0;
        detailLabel.tag = 9;
        [detailLabel sizeToFit];
        if([overlayText length] == 0) {
            vuforiaBarView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0f];
        }
        
        // if the device icon is to be shown, adapt the text to fit.
        CGRect detailFrame = detailLabel.frame;
        if(showDevicesIcon) {
            detailFrame = CGRectMake(70, 10, [[UIScreen mainScreen] bounds].size.width - 130, detailLabel.frame.size.height);
        }
        else {
            detailFrame = CGRectMake(20, 10, [[UIScreen mainScreen] bounds].size.width - 130, detailLabel.frame.size.height);
        }
        detailLabel.frame = detailFrame;
        [detailLabel sizeToFit];
        [vuforiaBarView addSubview:detailLabel];
        
        if(detailLabel.frame.size.height > button.frame.size.height) {
            CGRect vuforiaFrame = vuforiaBarView.frame;
            vuforiaFrame.size.height = detailLabel.frame.size.height + 25;
            vuforiaBarView.frame = vuforiaFrame;
            
            CGRect buttonFrame = button.frame;
            buttonFrame.origin.y = detailLabel.frame.size.height / 3.0;
            button.frame = buttonFrame;
            
            if(showDevicesIcon) {
                UIImageView *imageView = (UIImageView *)[eaglView viewWithTag:11];
                CGRect imageFrame = imageView.frame;
                imageFrame.origin.y = detailLabel.frame.size.height / 3.0;
                imageView.frame = imageFrame;
            }
        }
        
        //MIRCO: MODIFICA PER NON VISUALIZZARE LA BARRA CON IL PULSANTE DI CHIUSURA E IL TESTO
        vuforiaBarView.frame = CGRectNull;
        
        
        //AGGIUNGO BARRA DI NAVIGAZIONE ZANICHELLI
        UIView *navBarView=[[UIView alloc]initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 64)];
        navBarView.backgroundColor = [self getUIColorObjectFromHexString:@"E30000" alpha:1.0];
        navBarView.tag = 8;
        [self.view addSubview:navBarView];
        UIImageView* testataImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo-zanichelli.png"]];
        testataImageView.center = CGPointMake(self.view.bounds.size.width/2, 64/2);
        [navBarView addSubview:testataImageView];
        self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.backButton setImage:[UIImage imageNamed:@"back.png"] forState:UIControlStateNormal];
        [self.backButton addTarget:self
                            action:@selector(goBack:)
                  forControlEvents:UIControlEventTouchUpInside];
        [self.backButton setTitle:@"" forState:UIControlStateNormal];
        self.backButton.frame = CGRectMake(16.0, 16.0, 32.0, 32.0);
        [navBarView addSubview:self.backButton];
        
    }
}

- (UIColor *)getUIColorObjectFromHexString:(NSString *)hexStr alpha:(CGFloat)alpha
{
    // Convert hex string to an integer
    unsigned int hexint = [self intFromHexString:hexStr];
    
    // Create color object, specifying alpha as well
    UIColor *color =
    [UIColor colorWithRed:((CGFloat) ((hexint & 0xFF0000) >> 16))/255
                    green:((CGFloat) ((hexint & 0xFF00) >> 8))/255
                     blue:((CGFloat) (hexint & 0xFF))/255
                    alpha:alpha];
    
    return color;
}

- (unsigned int)intFromHexString:(NSString *)hexStr
{
    unsigned int hexInt = 0;
    
    // Create scanner
    NSScanner *scanner = [NSScanner scannerWithString:hexStr];
    
    // Tell scanner to skip the # character
    [scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"#"]];
    
    // Scan hex value
    [scanner scanHexInt:&hexInt];
    
    return hexInt;
}

-(void)buttonPressed {
    [self stopVuforia];
    NSLog(@"Vuforia Plugin :: button pressed!!!");
    NSDictionary* userInfo = @{@"status": @{@"manuallyClosed": @true, @"message": @"User manually closed the plugin."}};
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CloseRequest" object:self userInfo:userInfo];
}


- (void) pauseAR {
    NSError * error = nil;
    
    //[self.navigationController popToRootViewControllerAnimated:YES];
    
    if (![vapp pauseAR:&error]) {
        NSLog(@"Error pausing AR:%@", [error description]);
    }
    
    [self dismissViewControllerAnimated:NO completion:nil];
    NSDictionary* userInfo = @{@"status": @{@"manuallyClosed": @true, @"message": @"User manually closed the plugin."}};
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CloseRequest" object:self userInfo:userInfo];
}

- (void) resumeAR {
    //    NSError * error = nil;
    //    if(! [vapp resumeAR:&error]) {
    //        NSLog(@"Error resuming AR:%@", [error description]);
    //    }
    //    // on resume, we reset the flash and the associated menu item
    //    Vuforia::CameraDevice::getInstance().setFlashTorchMode(false);
    
    [self buttonPressed];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [tapGestureRecognizer release];
    
    [vapp release];
    [eaglView release];
    
    [super dealloc];
}

- (void)loadView
{
    // Create the EAGLView
    eaglView = [[ImageTargetsEAGLView alloc] initWithFrame:viewFrame appSession:vapp];
    [self setView:eaglView];
    self.glResourceHandler = eaglView;
    
    // show loading animation while AR is being initialized
    [self showLoadingAnimation];
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    [vapp initAR:Vuforia::GL_20 ARViewBoundsSize:viewFrame.size orientation:orientation];
    
    [self performSelector:@selector(test) withObject:nil afterDelay:.5];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Do any additional setup after loading the view.
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.view addGestureRecognizer:tapGestureRecognizer];
    
    NSLog(@"self.navigationController.navigationBarHidden: %s", self.navigationController.navigationBarHidden ? "Yes" : "No");
    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (self.playerController.isFullScreen){
        //[self dismissViewControllerAnimated:NO completion:nil];
        self.playerController.isFullScreen = NO;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    
    //[self stopVuforia];
    
    // Be a good OpenGL ES citizen: now that Vuforia is paused and the render
    // thread is not executing, inform the root view controller that the
    // EAGLView should finish any OpenGL ES commands
    [eaglView finishOpenGLESCommands];
    [eaglView freeOpenGLESResources];
    
    self.glResourceHandler = nil;
    
    [super viewWillDisappear:animated];
}

- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  Inform the EAGLView
    [eaglView finishOpenGLESCommands];
}


- (void)freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Inform the EAGLView
    [eaglView freeOpenGLESResources];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - loading animation

- (void) showLoadingAnimation {
    CGRect mainBounds = [[UIScreen mainScreen] bounds];
    CGRect indicatorBounds = CGRectMake(mainBounds.size.width / 2 - 12,
                                        mainBounds.size.height / 2 - 12, 24, 24);
    UIActivityIndicatorView *loadingIndicator = [[[UIActivityIndicatorView alloc]
                                                  initWithFrame:indicatorBounds]autorelease];
    
    loadingIndicator.tag  = 1;
    loadingIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    [eaglView addSubview:loadingIndicator];
    [loadingIndicator startAnimating];
}

-(void) positionLoadingAnimation {
    
}

- (void) hideLoadingAnimation {
    UIActivityIndicatorView *loadingIndicator = (UIActivityIndicatorView *)[eaglView viewWithTag:1];
    [loadingIndicator removeFromSuperview];
}


#pragma mark - ApplicationControl

- (bool) doInitTrackers {
    // Initialize the image or marker tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    
    // Image Tracker...
    Vuforia::Tracker* trackerBase = trackerManager.initTracker(Vuforia::ObjectTracker::getClassType());
    if (trackerBase == NULL)
    {
        NSLog(@"Failed to initialize ObjectTracker.");
        return false;
    }
    NSLog(@"Successfully initialized ObjectTracker.");
    return true;
}

- (bool) doLoadTrackersData {
    NSLog(@"Vuforia Plugin :: imageTargetFile = %@", self.imageTargetFile);
    dataSetTargets = [self loadObjectTrackerDataSet2:self.imageTargetFile];
    if (dataSetTargets == NULL) {
        NSLog(@"Failed to load datasets");
        return NO;
    }
    if (! [self activateDataSet:dataSetTargets]) {
        NSLog(@"Failed to activate dataset");
        return NO;
    }
    
    if ((self.imageTargetFile2.length > 0) && (self.tipo = @"misto")){
        dataSetTargets2 = [self loadObjectTrackerDataSet2:self.imageTargetFile2];
        if (dataSetTargets2 == NULL) {
            NSLog(@"Failed to load datasets");
            return NO;
        }
        if (! [self activateDataSet:dataSetTargets2]) {
            NSLog(@"Failed to activate dataset");
            return NO;
        }
    }
    
    return YES;
}

- (bool) doStartTrackers {
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::Tracker* tracker = trackerManager.getTracker(Vuforia::ObjectTracker::getClassType());
    if(tracker == 0) {
        return NO;
    }
    
    tracker->start();
    return YES;
}

// callback: the AR initialization is done
- (void) onInitARDone:(NSError *)initError {
    [self hideLoadingAnimation];
    
    if (initError == nil) {
        
        NSError * error = nil;
        [vapp startAR:Vuforia::CameraDevice::CAMERA_DIRECTION_BACK error:&error];
        
        // by default, we try to set the continuous auto focus mode
    } else {
        NSLog(@"Error initializing AR:%@", [initError description]);
        dispatch_async( dispatch_get_main_queue(), ^{
            
            //            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
            //                                                            message:[initError localizedDescription]
            //                                                           delegate:self
            //                                                  cancelButtonTitle:@"OK"
            //                                                  otherButtonTitles:nil];
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Errore di connessione"
                                                            message:@"Impossibile accedere ai contenuti.\nTi consigliamo di riprovare più tardi."
                                                           delegate:self
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
            [alert release];
        });
    }
}

#pragma mark - UIAlertViewDelegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kMenuDismissViewController" object:nil];
}

//    Update function called while camera is tracking images
- (void) onVuforiaUpdate: (Vuforia::State *) state {
    NSDictionary* userInfo;
    int indexVuMarkToDisplay = -1;
    
    for (int i = 0; i < state->getNumTrackableResults(); ++i) {
        
        const Vuforia::TrackableResult* result = state->getTrackableResult(i);
        const Vuforia::Trackable& trackable = result->getTrackable();
        
        if (result->isOfType(Vuforia::VuMarkTargetResult::getClassType())){
            //VUMARK
            self.currtipo = @"vumark";
            //this boolean teels if the current vumark is the 'main' one,
            //i.e either the closest one to the camera center or the closest one
            bool isMainVumark = ((indexVuMarkToDisplay < 0) || (indexVuMarkToDisplay == i));
            
            if (isMainVumark) {
                const Vuforia::VuMarkTargetResult* vmtResult = static_cast< const Vuforia::VuMarkTargetResult*>(result);
                const Vuforia::VuMarkTarget& vmtar = vmtResult->getTrackable();
                const Vuforia::VuMarkTemplate& vmtmp = vmtar.getTemplate();
                const Vuforia::InstanceId& instanceId = vmtar.getInstanceId();
                NSString * vumarkIdValue = [self convertInstanceIdToString:instanceId];
                NSLog(@"Vuforia Plugin :: VuMark*** %@",vumarkIdValue);
                
                userInfo = @{@"status": @{@"imageFound": @true, @"message": @"Image Found."}, @"result": @{@"imageName": vumarkIdValue}};
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    NSLog(@"Vuforia Plugin :: messaged dispatched!!!");
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"ImageMatched" object:self userInfo:userInfo];
                });
            }
            
        } else {
            self.currtipo = @"imagetargets";
            //MARKER IMAGE
            if(![self.imageTargetNames isEqual:[NSNull null]])
            {
                //do something if object is not equals to [NSNull null]
                for(NSString *imageName in self.imageTargetNames) {
                    //    Check if matched target is matched
                    if (!strcmp(trackable.getName(), imageName.UTF8String))
                    {
                        [self doStopTrackers];
                        NSLog(@"Vuforia Plugin :: image found!!!");
                        if ([self.tipo isEqualToString:@"vumark"]){
                            userInfo = @{@"status": @{@"imageFound": @true, @"message": @"Image Found."}, @"result": @{@"imageName": [NSString stringWithFormat:@"%d",trackable.getId()]}};
                        } else {
                            userInfo = @{@"status": @{@"imageFound": @true, @"message": @"Image Found."}, @"result": @{@"imageName": imageName}};
                        }
                        
                        //[self performSelectorOnMainThread:@selector(showHTML:)withObject:nil waitUntilDone:YES];
                        
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            NSLog(@"Vuforia Plugin :: messaged dispatched!!!");
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"ImageMatched" object:self userInfo:userInfo];
                        });
                    }
                }
            } else {
                //MIRCO: TOLGO LO STOP DEL TRACKING
                //[self doStopTrackers];
                NSLog(@"Vuforia Plugin :: image found!!!");
                NSDictionary* userInfo = @{@"status": @{@"imageFound": @true, @"message": @"Image Found."}, @"result": @{@"imageName": [NSString stringWithFormat:@"%d" , trackable.getId()]}};
                
                if ([self.tipo isEqualToString:@"vumark"]){
                    userInfo = @{@"status": @{@"imageFound": @true, @"message": @"Image Found."}, @"result": @{@"imageName":[NSString stringWithFormat:@"%d",trackable.getId()]}};
                } else {
                    userInfo = @{@"status": @{@"imageFound": @true, @"message": @"Image Found."}, @"result": @{@"imageName": [NSString stringWithFormat:@"%s" , trackable.getName()]}};
                }
                
                //[self performSelectorOnMainThread:@selector(showHTML:)withObject:nil waitUntilDone:YES];
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    NSLog(@"Vuforia Plugin :: messaged dispatched!!!");
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"ImageMatched" object:self userInfo:userInfo];
                });
            }
        }
    }
}

- (NSString *) getInstanceIdType:(const Vuforia::InstanceId&) instanceId
{
    switch(instanceId.getDataType()) {
        case Vuforia::InstanceId::BYTES:
            return @"Bytes";
        case Vuforia::InstanceId::STRING:
            return @"String";
        case Vuforia::InstanceId::NUMERIC:
            return @"Numeric";
        default:
            return @"Unknown";
    }
}

- (NSString *) convertInstanceIdForBytes:(const Vuforia::InstanceId&) instanceId
{
    const size_t MAXLEN = 100;
    char buf[MAXLEN];
    const char * src = instanceId.getBuffer();
    size_t len = instanceId.getLength();
    
    static const char* hexTable = "0123456789abcdef";
    
    if (len * 2 + 1 > MAXLEN) {
        len = (MAXLEN - 1) / 2;
    }
    
    // Go in reverse so the string is readable left-to-right.
    size_t bufIdx = 0;
    for (int i = (int)(len - 1); i >= 0; i--)
    {
        char upper = hexTable[(src[i] >> 4) & 0xf];
        char lower = hexTable[(src[i] & 0xf)];
        buf[bufIdx++] = upper;
        buf[bufIdx++] = lower;
    }
    
    // null terminate the string.
    buf[bufIdx] = 0;
    
    return [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
}

- (NSString *) convertInstanceIdForString:(const Vuforia::InstanceId&) instanceId
{
    const char * src = instanceId.getBuffer();
    return [NSString stringWithUTF8String:src];
}

- (NSString *) convertInstanceIdForNumeric:(const Vuforia::InstanceId&) instanceId
{
    unsigned long long value = instanceId.getNumericValue();
    return[NSString stringWithFormat:@"%ld", value];
}

- (NSString *) convertInstanceIdToString:(const Vuforia::InstanceId&) instanceId {
    switch(instanceId.getDataType()) {
        case Vuforia::InstanceId::BYTES:
            return [self convertInstanceIdForBytes:instanceId];
        case Vuforia::InstanceId::STRING:
            return [self convertInstanceIdForString:instanceId];
        case Vuforia::InstanceId::NUMERIC:
            return [self convertInstanceIdForNumeric:instanceId];
        default:
            return @"Unknown";
    }
}

-(void) showHTML:(NSString*) url markerid:(NSString *)markerid {
    //MIRCO: PER AGGIORNARE I CONTENUTI SE CAMBIA IL MARKER O IL LIBRO
    if (self.webView != nil){
        [self.webView removeFromSuperview];
    }
    
    self.webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 64, eaglView.frame.size.width, eaglView.frame.size.height-64)];
    self.markerid = markerid;
    
    NSURL *urlString = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:@"www/contents"]];
    [self.webView loadRequest:[NSURLRequest requestWithURL:urlString]];
    
    //[webView loadHTMLString:urlString  baseURL:nil];
    [self.webView setBackgroundColor:[UIColor clearColor]];
    [self.webView setOpaque:NO];
    self.webView.delegate = self;
    
    UITapGestureRecognizer * doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(chiudiWebView)];
    [doubleTap setNumberOfTapsRequired:2];
    [self.webView setUserInteractionEnabled:YES];
    [self.webView addGestureRecognizer:doubleTap];
    
    self.webView.scalesPageToFit = YES;
    
    [eaglView addSubview:self.webView];
}

- (void) webViewDidFinishLoad:(UIWebView *)webView
{
    if ([[webView stringByEvaluatingJavaScriptFromString:@"document.readyState"] isEqualToString:@"complete"]) {
        // UIWebView object has fully loaded.
        if ([self.prof_id isEqualToString:@""]){
            self.prof_id = @"null";
        }
        
        NSString* jsFunctionName = @"";
        if ([self.last_action isEqualToString:@"d"]){
            //MIRCO: CHIAMO METODO JS DA NATIVO
            jsFunctionName = @"createButtonListDoc('";
            jsFunctionName = [jsFunctionName stringByAppendingString:self.email];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.book_id];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.markerid];
            //VUMARK
            jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.prof_id];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"',false,'"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.path_documents];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        } else {
            jsFunctionName = @"createButtonList('";
            jsFunctionName = [jsFunctionName stringByAppendingString:self.email];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.book_id];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.markerid];
            //VUMARK
            jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.prof_id];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"',false,'"];
            jsFunctionName = [jsFunctionName stringByAppendingString:self.path_documents];
            jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        }
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        //[self.webView stringByEvaluatingJavaScriptFromString:@"createButtonList();"];
        
        //TODO: GESTIRE LA CHIUSURA DEL PDF
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}


// Load the image tracker data set
- (Vuforia::DataSet *)loadObjectTrackerDataSet:(NSString*)dataFile
{
    NSLog(@"loadObjectTrackerDataSet (%@)", dataFile);
    Vuforia::DataSet * dataSet = NULL;
    
    // Get the Vuforia tracker manager image tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (NULL == objectTracker) {
        NSLog(@"ERROR: failed to get the ObjectTracker from the tracker manager");
        return NULL;
    } else {
        dataSet = objectTracker->createDataSet();
        
        if (NULL != dataSet) {
            NSLog(@"INFO: successfully loaded data set");
            
            //Determine the storage type.
            Vuforia::STORAGE_TYPE storageType;
            if([dataFile hasPrefix:@"file://"]) {
                dataFile = [dataFile stringByReplacingOccurrencesOfString:@"file://" withString:@""];
                storageType = Vuforia::STORAGE_ABSOLUTE;
                NSLog(@"Reading the absolute path to target file : %@", dataFile);
                
            }else{
                NSLog(@"Reading the path to target file %@ from resources folder", dataFile);
                storageType = Vuforia::STORAGE_APPRESOURCE;
            }
            
            // Load the data set from the app's resources location
            if (!dataSet->load([dataFile cStringUsingEncoding:NSASCIIStringEncoding], storageType)) {
                NSLog(@"ERROR: failed to load data set");
                objectTracker->destroyDataSet(dataSet);
                dataSet = NULL;
            }
        }
        else {
            NSLog(@"ERROR: failed to create data set");
        }
    }
    
    return dataSet;
}

- (Vuforia::DataSet *)loadObjectTrackerDataSet2:(NSString*)dataFile
{
    NSLog(@"loadObjectTrackerDataSet (%@)", dataFile);
    Vuforia::DataSet * dataSet = NULL;
    
    // Get the Vuforia tracker manager image tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (NULL == objectTracker) {
        NSLog(@"ERROR: failed to get the ObjectTracker from the tracker manager");
        return NULL;
    } else {
        dataSet = objectTracker->createDataSet();
        
        if (NULL != dataSet) {
            NSLog(@"INFO: successfully loaded data set");
            //NSArray  *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSArray       *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
            NSString  *documentsDirectory = [paths objectAtIndex:0];
            documentsDirectory = [documentsDirectory stringByAppendingString:@"/NoCloud"];
            // Load the data set from the app's resources location
            if (!dataSet->load([[NSString stringWithFormat:@"%@/%@", documentsDirectory,dataFile] cStringUsingEncoding:NSASCIIStringEncoding], Vuforia::STORAGE_ABSOLUTE)) {
                NSLog(@"ERROR: failed to load data set");
                objectTracker->destroyDataSet(dataSet);
                dataSet = NULL;
            }
        }
        else {
            NSLog(@"ERROR: failed to create data set");
        }
    }
    return dataSet;
}


- (bool) doStopTrackers {
    // Stop the tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::Tracker* tracker = trackerManager.getTracker(Vuforia::ObjectTracker::getClassType());
    
    if (NULL != tracker) {
        tracker->stop();
        NSLog(@"INFO: successfully stopped tracker");
        return YES;
    }
    else {
        NSLog(@"ERROR: failed to get the tracker from the tracker manager");
        return NO;
    }
}

- (bool) doUnloadTrackersData {
    [self deactivateDataSet: dataSetCurrent];
    dataSetCurrent = nil;
    
    // Get the image tracker:
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (!objectTracker->destroyDataSet(dataSetTargets))
    {
        NSLog(@"Failed to destroy data set.");
    }
    NSLog(@"datasets destroyed");
    
    // Destroy the data sets:
    if ((self.imageTargetFile2.length > 0) && (self.tipo = @"misto")){
        if (!objectTracker->destroyDataSet(dataSetTargets2))
        {
            NSLog(@"Failed to destroy data set.");
        }
        NSLog(@"datasets2 destroyed");
    }
    
    return YES;
}

- (BOOL)activateDataSet:(Vuforia::DataSet *)theDataSet
{
    // if we've previously recorded an activation, deactivate it
    // MIRCO 09012018  - QUESTO NON SERVE PIU' (MISTO)
    //    if (dataSetCurrent != nil)
    //    {
    //        [self deactivateDataSet:dataSetCurrent];
    //    }
    BOOL success = NO;
    
    // Get the image tracker:
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (objectTracker == NULL) {
        NSLog(@"Failed to load tracking data set because the ObjectTracker has not been initialized.");
    }
    else
    {
        // Activate the data set:
        if (!objectTracker->activateDataSet(theDataSet))
        {
            NSLog(@"Failed to activate data set.");
        }
        else
        {
            NSLog(@"Successfully activated data set.");
            dataSetCurrent = theDataSet;
            success = YES;
        }
    }
    
    // we set the off target tracking mode to the current state
    if (success) {
        [self setExtendedTrackingForDataSet:dataSetCurrent start:extendedTrackingIsOn];
    }
    
    return success;
}

- (BOOL)deactivateDataSet:(Vuforia::DataSet *)theDataSet
{
    if ((dataSetCurrent == nil) || (theDataSet != dataSetCurrent))
    {
        NSLog(@"Invalid request to deactivate data set.");
        return NO;
    }
    
    BOOL success = NO;
    
    // we deactivate the enhanced tracking
    [self setExtendedTrackingForDataSet:theDataSet start:NO];
    
    // Get the image tracker:
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (objectTracker == NULL)
    {
        NSLog(@"Failed to unload tracking data set because the ObjectTracker has not been initialized.");
    }
    else
    {
        // Activate the data set:
        if (!objectTracker->deactivateDataSet(theDataSet))
        {
            NSLog(@"Failed to deactivate data set.");
        }
        else
        {
            success = YES;
        }
    }
    
    dataSetCurrent = nil;
    
    return success;
}

- (BOOL) setExtendedTrackingForDataSet:(Vuforia::DataSet *)theDataSet start:(BOOL) start {
    BOOL result = YES;
    for (int tIdx = 0; tIdx < theDataSet->getNumTrackables(); tIdx++) {
        Vuforia::Trackable* trackable = theDataSet->getTrackable(tIdx);
        if (start) {
            if (!trackable->startExtendedTracking())
            {
                NSLog(@"Failed to start extended tracking on: %s", trackable->getName());
                result = false;
            }
        } else {
            if (!trackable->stopExtendedTracking())
            {
                NSLog(@"Failed to stop extended tracking on: %s", trackable->getName());
                result = false;
            }
        }
    }
    return result;
}

- (bool) doDeinitTrackers {
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    trackerManager.deinitTracker(Vuforia::ObjectTracker::getClassType());
    return YES;
}

- (void)autofocus:(UITapGestureRecognizer *)sender
{
    //RIMOSSA PER EVITARE CHE PASSI AL FOCUS MANUALE
    //[self performSelector:@selector(cameraPerformAutoFocus) withObject:nil afterDelay:.4];
}

- (void)cameraPerformAutoFocus
{
    Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_TRIGGERAUTO);
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    bool showDevicesIcon = [[self.overlayOptions objectForKey:@"showDevicesIcon"] integerValue];
    
    // Code here will execute before the rotation begins.
    // Equivalent to placing it in the deprecated method -[willRotateToInterfaceOrientation:duration:]
    
    //    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    //        if(!self.delaying){
    //            //[self stopVuforia];
    //            [vapp pauseAR:nil];
    //
    //            [self showLoadingAnimation];
    //        }
    //    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    //        if(!self.delaying) {
    //            self.delaying = true;
    //
    //
    //        }
    //
    //        CGRect mainBounds = [[UIScreen mainScreen] bounds];
    //
    //        UIView *vuforiaBarView = (UIView *)[eaglView viewWithTag:8];
    //
    //        UIButton *closeButton = (UIButton *)[eaglView viewWithTag:10];
    //        UIActivityIndicatorView *loadingIndicator = (UIActivityIndicatorView *)[eaglView viewWithTag:1];
    //
    //        UILabel *detailLabel = (UILabel *)[eaglView viewWithTag:9];
    //        UIActivityIndicatorView *labelLoadingIndicator = (UIActivityIndicatorView *)[eaglView viewWithTag:1];
    //
    //        [UIView animateWithDuration:0.33 animations:^{
    //
    //            // handle close button location
    //            CGRect closeRect = closeButton.frame;
    //            closeRect.origin.x = [[UIScreen mainScreen] bounds].size.width - 65;
    //            closeButton.frame = closeRect;
    //
    //            // if the device icon is to be shown, adapt the text to fit.
    //            CGRect detailFrame = detailLabel.frame;
    //            if(showDevicesIcon) {
    //                detailFrame = CGRectMake(70, 10, [[UIScreen mainScreen] bounds].size.width - 130, detailLabel.frame.size.height);
    //            }
    //            else {
    //                detailFrame = CGRectMake(20, 10, [[UIScreen mainScreen] bounds].size.width - 130, detailLabel.frame.size.height);
    //            }
    //            detailLabel.frame = detailFrame;
    //            [detailLabel sizeToFit];
    //            [vuforiaBarView addSubview:detailLabel];
    //
    //            CGRect vuforiaFrame = vuforiaBarView.frame;
    //            vuforiaFrame.size.height = detailLabel.frame.size.height + 25;
    //            vuforiaBarView.frame = vuforiaFrame;
    //
    //            if(detailLabel.frame.size.height > closeButton.frame.size.height) {
    //                CGRect buttonFrame = closeButton.frame;
    //                buttonFrame.origin.y = detailLabel.frame.size.height / 3.0;
    //                closeButton.frame = buttonFrame;
    //            }
    //            else {
    //                // handle close button location
    //                CGRect closeRect = closeButton.frame;
    //                closeRect.origin.y = 5;
    //                closeButton.frame = closeRect;
    //
    //                // handle case where text is short
    //                vuforiaFrame.size.height = 75;
    //                vuforiaBarView.frame = vuforiaFrame;
    //            }
    //
    //            // handle showDevicesIcon if it exists
    //            if(showDevicesIcon) {
    //                UIImageView *imageView = (UIImageView *)[eaglView viewWithTag:11];
    //                CGRect imageFrame = imageView.frame;
    //                imageFrame.origin.y = detailLabel.frame.size.height / 3.0;
    //                imageView.frame = imageFrame;
    //            }
    //        }];
    //
    //
    //    }];
}

- (void)stopVuforia
{
    //[vapp pauseAR:nil];
    
    [vapp stopAR:nil];
    // Be a good OpenGL ES citizen: now that Vuforia is paused and the render
    // thread is not executing, inform the root view controller that the
    // EAGLView should finish any OpenGL ES commands
    [eaglView finishOpenGLESCommands];
    [eaglView freeOpenGLESResources];
    
    self.glResourceHandler = nil;
    
}

-(void)startVuforia
{
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    
    // Frames from the camera are always landscape, no matter what the
    // orientation of the device.  Tell Vuforia to rotate the video background (and
    // the projection matrix it provides to us for rendering our augmentation)
    // by the proper angle in order to match the EAGLView orientation
    if (orientation == UIInterfaceOrientationPortrait)
    {
        Vuforia::setRotation(Vuforia::ROTATE_IOS_90);
    }
    else if (orientation == UIInterfaceOrientationPortraitUpsideDown)
    {
        Vuforia::setRotation(Vuforia::ROTATE_IOS_270);
    }
    else if (orientation == UIInterfaceOrientationLandscapeLeft)
    {
        Vuforia::setRotation(Vuforia::ROTATE_IOS_180);
    }
    else if (orientation == UIInterfaceOrientationLandscapeRight)
    {
        Vuforia::setRotation(1);
    }
    
    
    // initialize the AR session
    //[vapp initAR:Vuforia::GL_20 ARViewBoundsSize:viewFrame.size orientation:orientation];
    [vapp resumeAR:nil];
    
    [self performSelector:@selector(test) withObject:nil afterDelay:.5];
}

- (BOOL)shouldAutorotate {
    return [[self presentingViewController] shouldAutorotate];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return [[self presentingViewController] supportedInterfaceOrientations];
}

//- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
//{
//    return [[self presentingViewController] preferredInterfaceOrientationForPresentation];
//}

-(void)test
{
    self.delaying = false;
    
    [self hideLoadingAnimation];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

-(bool) doUpdateTargets:(NSArray *)targets {
    self.imageTargetNames = targets;
    
    return TRUE;
}

-(UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationPortrait; }

//WEBVIEW DELEGATE
//QUESTO METODO VIENE RICHIAMATO QUANDO VIENE AZIONATO UN PULSANTE SULLA PARTE CORDOVA
- (BOOL)webView:(UIWebView *)webView
shouldStartLoadWithRequest:(NSURLRequest *)request
 navigationType:(UIWebViewNavigationType)navigationType {
    
    // these need to match the values defined in your JavaScript
    NSString *myAppScheme = @"zanichelliios";
    NSString *myActionType = @"showContent";
    
    if (![request.URL.scheme isEqualToString:@"gap"]){
        NSLog(@"SCHEMA: %@",request.URL.scheme);
        NSLog(@"HOST: %@",request.URL.host);
        
    }
    
    // ignore legit webview requests so they load normally
    if (![request.URL.scheme isEqualToString:myAppScheme]) {
        return YES;
    }
    
    // get the action from the path
    NSString *actionType = request.URL.host;
    // deserialize the request JSON
    NSString *jsonDictString = [request.URL.fragment stringByReplacingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
    NSError *jsonError;
    NSData *objectData = [jsonDictString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:objectData
                                                         options:NSJSONReadingMutableContainers
                                                           error:&jsonError];
    
    self.last_action = [json objectForKey:@"type"];;
    // look at the actionType and do whatever you want here
    if ([actionType isEqualToString:@"showContent"]) {
        // do something in response to your javascript action
        // if you used an action parameters dict, deserialize and inspect it here
        NSString* markerid = [json objectForKey:@"marker_id"];
        NSString* type = [json objectForKey:@"type"];
        NSString* prof_id = [json objectForKey:@"prof_id"];
        prof_id = @"null";
        NSString* book_id = [json objectForKey:@"book_id"];
        NSString* UUID_identifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        
        NSString* jsFunctionName = @"createContentList('";
        jsFunctionName = [jsFunctionName stringByAppendingString:book_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:markerid];
        //VUMARK
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:type];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:prof_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:UUID_identifier];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
    } else if (([actionType isEqualToString:@"apriVideo"]) || ([actionType isEqualToString:@"apriAudio"])) {
        // apriVideo(marker_id, url,  id)
        NSString* markerid = [json objectForKey:@"marker_id"];
        //NSString* url = [json objectForKey:@"url"];
        NSString* id = [json objectForKey:@"id"];
        //[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
        
        NSURL *url = [NSURL URLWithString:[[json objectForKey:@"url"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        //NSURL *url = [NSURL URLWithString:@"http://clips.vorwaerts-gmbh.de/VfE_html5.mp4"];
        self.playerController = [[MoviePlayerViewController alloc] initWithNibName:nil bundle:nil];
        self.playerController.url = url;
        [self.playerController.moviePlayer initWithContentsOfURL:url];
        
        //AGGIUNGO BARRA DI NAVIGAZIONE ZANICHELLI
        UIView *navBarView=[[UIView alloc]initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 64)];
        navBarView.backgroundColor = [self getUIColorObjectFromHexString:@"E30000" alpha:1.0];
        navBarView.tag = 8;
        UIImageView* testataImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo-zanichelli"]];
        testataImageView.center = CGPointMake(self.view.bounds.size.width/2, 64/2);
        [navBarView addSubview:testataImageView];
        self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.backButton setImage:[UIImage imageNamed:@"back.png"] forState:UIControlStateNormal];
        [self.backButton addTarget:self
                            action:@selector(closeVideo:)
                  forControlEvents:UIControlEventTouchUpInside];
        [self.backButton setTitle:@"" forState:UIControlStateNormal];
        self.backButton.frame = CGRectMake(16.0, 16.0, 32.0, 32.0);
        [navBarView addSubview:self.backButton];
        self.playerController.navBarZanichelli =navBarView;
        
        //        [[NSNotificationCenter defaultCenter]
        //         removeObserver:self
        //         name:UIApplicationWillResignActiveNotification
        //         object:nil];
        //        [[NSNotificationCenter defaultCenter]
        //         removeObserver:self
        //         name:UIApplicationDidBecomeActiveNotification
        //         object:nil];
        
        [self presentViewController:self.playerController animated:YES completion:nil];
        [self.playerController.moviePlayer.moviePlayer play];
        
        
        
        //} else if ([actionType isEqualToString:@"apriAudio"]) {
        //MISSILE HA VOLUTO CHE LO TOGLIESSI
        // apriAudio(marker_id, url,  id)
        
    } else if ([actionType isEqualToString:@"apriLink"]) {
        // apriLink(marker_id, url,  id)
        //[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[[json objectForKey:@"url"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
        
        self.linkController = [[LinkViewController alloc] initWithNibName:nil bundle:nil];
        self.linkController.url = [NSURLRequest requestWithURL:[NSURL URLWithString:[json objectForKey:@"url"]]];
        
        //AGGIUNGO BARRA DI NAVIGAZIONE ZANICHELLI
        UIView *navBarView=[[UIView alloc]initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 64)];
        navBarView.backgroundColor = [self getUIColorObjectFromHexString:@"E30000" alpha:1.0];
        navBarView.tag = 8;
        UIImageView* testataImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo-zanichelli"]];
        testataImageView.center = CGPointMake(self.view.bounds.size.width/2, 64/2);
        [navBarView addSubview:testataImageView];
        self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.backButton setImage:[UIImage imageNamed:@"back.png"] forState:UIControlStateNormal];
        [self.backButton addTarget:self
                            action:@selector(closeVideo:)
                  forControlEvents:UIControlEventTouchUpInside];
        [self.backButton setTitle:@"" forState:UIControlStateNormal];
        self.backButton.frame = CGRectMake(16.0, 16.0, 32.0, 32.0);
        [navBarView addSubview:self.backButton];
        self.linkController.navBarZanichelli =navBarView;
        [self presentViewController:self.linkController animated:YES completion:nil];
    }else if ([actionType isEqualToString:@"apriGeogebra"]) {
//        NSString* docurl = [json objectForKey:@"url"];
//        self.last_action = @"geo";
//
//        //MIRCO: CHIAMO METODO JS DA NATIVO
//        NSString* jsFunctionName = @"apriGeogebra2('";
//        jsFunctionName = [jsFunctionName stringByAppendingString:docurl];
//        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
//
//        //Execute javascript method or pure javascript if needed
//        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        NSURL* myURL = [NSURL URLWithString:[json objectForKey:@"url"]];
        [[UIApplication sharedApplication] openURL:myURL
                                           options:@{UIApplicationOpenURLOptionUniversalLinksOnly: @YES}
                                 completionHandler:^(BOOL success){
                                     if(!success) {
                                         // present in app web view, the app is not installed
                                         self.linkController = [[LinkViewController alloc] initWithNibName:nil bundle:nil];
                                         self.linkController.url = [NSURLRequest requestWithURL:[NSURL URLWithString:[json objectForKey:@"url"]]];
                                         
                                         //AGGIUNGO BARRA DI NAVIGAZIONE ZANICHELLI
                                         UIView *navBarView=[[UIView alloc]initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 64)];
                                         navBarView.backgroundColor = [self getUIColorObjectFromHexString:@"E30000" alpha:1.0];
                                         navBarView.tag = 8;
                                         UIImageView* testataImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo-zanichelli"]];
                                         testataImageView.center = CGPointMake(self.view.bounds.size.width/2, 64/2);
                                         [navBarView addSubview:testataImageView];
                                         self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
                                         [self.backButton setImage:[UIImage imageNamed:@"back.png"] forState:UIControlStateNormal];
                                         [self.backButton addTarget:self
                                                             action:@selector(closeVideo:)
                                                   forControlEvents:UIControlEventTouchUpInside];
                                         [self.backButton setTitle:@"" forState:UIControlStateNormal];
                                         self.backButton.frame = CGRectMake(16.0, 16.0, 32.0, 32.0);
                                         [navBarView addSubview:self.backButton];
                                         self.linkController.navBarZanichelli =navBarView;
                                         [self presentViewController:self.linkController animated:YES completion:nil];
                                     }
                                 }];
    } else if ([actionType isEqualToString:@"apriDoc"]) {
        // apriDoc(marker_id, docUrl,  id)
        NSLog(@"Apro documento: %@",[[@" http://zanichelli.yoomee.it/imgup/documenti/" stringByAppendingString:[json objectForKey:@"docUrl"]] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
        //[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[[@"http://zanichelli.yoomee.it/imgup/documenti/" stringByAppendingString:[json objectForKey:@"docUrl"]] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
        NSLog(@"Apro documento: %@",[[json objectForKey:@"docUrl"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[[json objectForKey:@"docUrl"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
        
    } else if ([actionType isEqualToString:@"apriDoc2"]) {
        NSString* docurl = [json objectForKey:@"docurl"];
        self.last_action = @"pdf";
        
        //MIRCO: CHIAMO METODO JS DA NATIVO
        NSString* jsFunctionName = @"apriDoc2('";
        jsFunctionName = [jsFunctionName stringByAppendingString:docurl];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        
    } else if ([actionType isEqualToString:@"closeWebview"]) {
        // closeWebview(marker_id)
        NSString* markerid = [json objectForKey:@"marker_id"];
        
        //MIRCO: CHIAMO METODO JS DA NATIVO
        NSString* jsFunctionName = @"createButtonList('";
        jsFunctionName = [jsFunctionName stringByAppendingString:self.email];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.book_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:markerid];
        //VUMARK
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','null'"];
        //jsFunctionName = [jsFunctionName stringByAppendingString:self.prof_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@",false,'"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.path_documents];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
    }
    
    // make sure to return NO so that your webview doesn't try to load your made-up URL
    return NO;
}

//CHIUDO IL PLAYER VIDEO
- (void)closeVideo:(id)sender {
    [self.playerController.moviePlayer.moviePlayer stop];
    UIWindow *window = [(AppDelegate *)[[UIApplication sharedApplication] delegate] window];
    NSLog(@"Numero controllers:%lu",[self.navigationController.viewControllers count]);
    NSLog(@"Numero controllers 2:%lu",[[[window rootViewController] navigationController].viewControllers count]);
    if (self.playerController.isFullScreen){
        [self dismissViewControllerAnimated:NO completion:nil];
        //} else if (self.linkController != nil){
    } else if (self.linkController.isViewLoaded && self.linkController.view.window){
        //viewController.isViewLoaded && viewController.view.window
        [self dismissViewControllerAnimated:NO completion:nil];
    } else {
        //[self dismissViewControllerAnimated:NO completion:nil];
        
        if (isIOS11_1()) {
            NSLog(@"newest");
        } else if (@available(iOS 11.4, *)) {
            NSLog(@"newest");
        } else {
            NSLog(@"not newest");
            [self dismissViewControllerAnimated:NO completion:nil];
        }
    }
    //[self dismissViewControllerAnimated:YES completion:nil];
}

//ASSOCIATA AL PULSANTE BACK
- (void)goBack:(id)sender {
    //[[NSNotificationCenter defaultCenter] removeObserver:self name:@"ImageMatched" object:nil];
    //[[NSNotificationCenter defaultCenter] removeObserver:self name:@"CloseRequest" object:nil];
    if ((![self.last_action isEqualToString:@"pdf"])&&(![self.last_action isEqualToString:@"i"])&&((![self.last_action isEqualToString:@"d"]))&&((![self.last_action isEqualToString:@"g"]))&&((![self.last_action isEqualToString:@"l"]))&&((![self.last_action isEqualToString:@"v"]))&&((![self.last_action isEqualToString:@"a"]))&&((![self.last_action isEqualToString:@"geo"]))){
        //NON E' UNA GALLERY
        [self buttonPressed];
    } else if ([self.last_action isEqualToString:@"i"]) {
        //GALLERY
        //MIRCO: CHIAMO METODO JS DA NATIVO
        NSString* jsFunctionName = @"createButtonList('";
        jsFunctionName = [jsFunctionName stringByAppendingString:self.email];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.book_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.markerid];
        //VUMARK
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.prof_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"',false,'"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.path_documents];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        self.last_action = @"";
    } else if ([self.last_action isEqualToString:@"d"]){
        //PDF
        //MIRCO: CHIAMO METODO JS DA NATIVO
        NSString* jsFunctionName = @"createButtonList('";
        jsFunctionName = [jsFunctionName stringByAppendingString:self.email];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.book_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.markerid];
        //VUMARK
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.prof_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"',false,'"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.path_documents];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        self.last_action = @"";
        
    } else if ([self.last_action isEqualToString:@"g"]){
        //PDF
        //MIRCO: CHIAMO METODO JS DA NATIVO
        NSString* jsFunctionName = @"createButtonList('";
        jsFunctionName = [jsFunctionName stringByAppendingString:self.email];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.book_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.markerid];
        //VUMARK
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.prof_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"',false,'"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.path_documents];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        self.last_action = @"";
        
    }else if ([self.last_action isEqualToString:@"pdf"]){
        //PDF
        //MIRCO: CHIAMO METODO JS DA NATIVO
        self.last_action = @"d";
        NSString* UUID_identifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        
        NSString* jsFunctionName = @"window.history.back();";
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        
        jsFunctionName = @"createContentList('";
        jsFunctionName = [jsFunctionName stringByAppendingString:self.book_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.markerid];
        //VUMARK
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.last_action];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.prof_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:UUID_identifier];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        
    }  else if ([self.last_action isEqualToString:@"geo"]){
        //GEOGEBRA
        //MIRCO: CHIAMO METODO JS DA NATIVO
        self.last_action = @"g";
        NSString* UUID_identifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        NSString* jsFunctionName = @"window.history.back();";
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
        
        jsFunctionName = @"createContentList('";
        jsFunctionName = [jsFunctionName stringByAppendingString:self.book_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.markerid];
        //VUMARK
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.currtipo];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.last_action];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:self.prof_id];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"','"];
        jsFunctionName = [jsFunctionName stringByAppendingString:UUID_identifier];
        jsFunctionName = [jsFunctionName stringByAppendingString:@"');"];
        
        //Execute javascript method or pure javascript if needed
        [self.webView stringByEvaluatingJavaScriptFromString:jsFunctionName];
    } else {
        [self buttonPressed];
    }
    
}

@end

