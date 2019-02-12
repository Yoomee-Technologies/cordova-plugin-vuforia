//
//  MoviePlayerViewController.h
//  zanichelliVSApp
//
//  Created by Gianluca Minciarelli on 23/01/17.
//
//

@interface LinkViewController : UIViewController <UIWebViewDelegate>{
    
}

@property (retain, nonatomic) UIWebView *webView;
@property (retain, nonatomic) NSURLRequest *url;
@property (retain, nonatomic) UIView *navBarZanichelli;
@property BOOL isFullScreen;
@end
