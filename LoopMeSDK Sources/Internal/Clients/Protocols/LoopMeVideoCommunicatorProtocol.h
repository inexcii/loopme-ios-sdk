//
//  LoopMeJSVideoTransporProtocol.h
//  LoopMeSDK
//
//  Created by Dmitriy on 10/28/14.
//
//

#ifndef LoopMeSDK_LoopMeVideoCommunicatorProtocol_h
#define LoopMeSDK_LoopMeVideoCommunicatorProtocol_h

@protocol LoopMeVideoCommunicatorProtocol <NSObject>

- (void)loadWithURL:(NSURL *)URL;
- (void)playFromTime:(double)time;
- (void)setMute:(BOOL)mute;
- (void)pauseOnTime:(double)time;
- (void)setGravity:(NSString *)gravity;

- (void)play;
- (void)pause;

@end

#endif
