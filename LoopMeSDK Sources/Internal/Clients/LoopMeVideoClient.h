//
//  LoopMeVideoClient.h
//  LoopMeSDK
//
//  Created by Kogda Bogdan on 10/20/14.
//
//

#import "LoopMeVideoCommunicatorProtocol.h"

@class LoopMe360ViewController;
@class LoopMeVideoClient;
@class AVPlayerLayer;

@protocol LoopMeJSCommunicatorProtocol;
@protocol LoopMeVideoClientDelegate;

extern const struct LoopMeVideoStateStruct
{
    __unsafe_unretained NSString *ready;
    __unsafe_unretained NSString *completed;
    __unsafe_unretained NSString *playing;
    __unsafe_unretained NSString *paused;
    __unsafe_unretained NSString *broken;
} LoopMeVideoState;

@interface LoopMeVideoClient : NSObject
<
    LoopMeVideoCommunicatorProtocol
>
@property (nonatomic, weak) UIViewController *viewController;

- (instancetype)initWithDelegate:(id<LoopMeVideoClientDelegate>)delegate;
- (void)playVideo:(NSURL *)URL;
- (LoopMe360ViewController *)viewController360;
- (void)adjustViewToFrame:(CGRect)frame;
- (void)cancel;
- (void)willAppear;
- (void)moveView;

@end

@protocol LoopMeVideoClientDelegate <NSObject>

- (id<LoopMeJSCommunicatorProtocol>)JSCommunicator;
- (void)videoClient:(LoopMeVideoClient *)client setupView:(UIView *)view;
- (void)videoClientDidReachEnd:(LoopMeVideoClient *)client;
- (void)videoClient:(LoopMeVideoClient *)client didFailToLoadVideoWithError:(NSError *)error;
- (void)videoClientDidBecomeActive:(LoopMeVideoClient *)client;
- (UIViewController *)viewControllerForPresentation;
- (NSString *)appKey;
- (BOOL)useMoatTracking;
- (BOOL)isVideo360;

@end
