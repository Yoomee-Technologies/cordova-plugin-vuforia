/*===============================================================================
 Copyright (c) 2012-2014 Qualcomm Connected Experiences, Inc. All Rights Reserved.

 Vuforia is a trademark of QUALCOMM Incorporated, registered in the United States
 and other countries. Trademarks of QUALCOMM Incorporated are used with permission.
 ===============================================================================*/

#import <UIKit/UIKit.h>
#import "ImageTargetsEAGLView.h"
#import "ApplicationSession.h"
#import <Vuforia/DataSet.h>
#import <MediaPlayer/MediaPlayer.h>
#import "MoviePlayerViewController.h"
#import "LinkViewController.h"

@interface ImageTargetsViewController : UIViewController <ApplicationControl,UIWebViewDelegate>{
    CGRect viewFrame;
    ImageTargetsEAGLView* eaglView;
    Vuforia::DataSet*  dataSetCurrent;
    Vuforia::DataSet*  dataSetTargets;
    Vuforia::DataSet*  dataSetTargets2;
    UITapGestureRecognizer * tapGestureRecognizer;
    ApplicationSession * vapp;

    BOOL switchToTarmac;
    BOOL switchToStonesAndChips;
    BOOL extendedTrackingIsOn;
}

@property (retain) NSString *imageTargetFile;
@property (retain) NSString *imageTargetFile2;
@property (retain) NSArray *imageTargetNames;
@property (retain) NSString *overlayText;
@property (retain) NSDictionary *overlayOptions;
@property (retain) NSString *vuforiaLicenseKey;

@property (retain, nonatomic) NSString *book_id;
@property (retain, nonatomic) NSString *email;
@property (retain, nonatomic) NSString *prof_fullname;
@property (retain, nonatomic) NSString *prof_id;
@property (retain, nonatomic) NSString *extra;
@property (retain, nonatomic) NSString *path_documents;
@property (retain, nonatomic) NSString *markerid;
@property (retain, nonatomic) NSString *last_action;
@property (retain, nonatomic) NSString *tipo;
@property (retain, nonatomic) NSString *currtipo;

@property (retain, nonatomic) UIWebView *webView;
@property (retain, nonatomic) MoviePlayerViewController *playerController;
@property (retain, nonatomic) LinkViewController *linkController;
@property (retain, nonatomic) UIButton *backButton;
@property (retain, nonatomic) UIViewController* vc;


@property (nonatomic) bool delaying;

- (id)initWithOverlayOptions:(NSDictionary *)overlayOptions vuforiaLicenseKey:(NSString *)vuforiaLicenseKey;
- (bool) doStartTrackers;
- (bool) doStopTrackers;
- (bool) doUpdateTargets:(NSArray *)targets;
-(void) showHTML:(NSString*)url markerid:(NSString*)markerid;

@end
