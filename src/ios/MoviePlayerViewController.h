//
//  MoviePlayerViewController.h
//  zanichelliVSApp
//
//  Created by Gianluca Minciarelli on 23/01/17.
//
//

#import <MediaPlayer/MediaPlayer.h>

@interface MoviePlayerViewController : UIViewController {
    
}

@property (retain, nonatomic) MPMoviePlayerViewController *moviePlayer;
@property (retain, nonatomic) NSURL *url;
@property (retain, nonatomic) UIView *navBarZanichelli;
@property BOOL isFullScreen;
@end
