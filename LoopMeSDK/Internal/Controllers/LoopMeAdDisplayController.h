//
//  LoopMeAdDisplayController.h
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 8/21/12.
//  Copyright (c) 2013 LoopMe. All rights reserved.
//

#import <UIKit/UIKit.h>

@class LoopMeJSClient;
@class LoopMeAdConfiguration;
@class LoopMeAdWebView;
@class LoopMeDestinationDisplayController;

@protocol LoopMeAdDisplayControllerDelegate;

@interface LoopMeAdDisplayController : NSObject

@property (nonatomic, weak) id<LoopMeAdDisplayControllerDelegate> delegate;
@property (nonatomic, assign, getter=isVisible) BOOL visible;
@property (nonatomic, assign, getter=isVisibleNoJS) BOOL visibleNoJS;
@property (nonatomic, assign) BOOL forceHidden;

- (instancetype)initWithDelegate:(id<LoopMeAdDisplayControllerDelegate>)delegate;
- (void)loadConfiguration:(LoopMeAdConfiguration *)configuration;
- (void)displayAd;
- (void)closeAd;
- (void)layoutSubviews;
- (void)stopHandlingRequests;
- (void)continueHandlingRequests;
- (void)moveView;

- (void)expandReporting;
- (void)collapseReporting;

@end

@protocol LoopMeAdDisplayControllerDelegate <NSObject>

- (void)adDisplayControllerDidReceiveTap:(LoopMeAdDisplayController *)adDisplayController;
- (void)adDisplayControllerDidFinishLoadingAd:(LoopMeAdDisplayController *)adDisplayController;
- (void)adDisplayController:(LoopMeAdDisplayController *)adDisplayController didFailToLoadAdWithError:(NSError *)error;
- (void)adDisplayControllerWillLeaveApplication:(LoopMeAdDisplayController *)adDisplayController;
- (void)adDisplayControllerShouldCloseAd:(LoopMeAdDisplayController *)adDisplayController;
- (void)adDisplayControllerVideoDidReachEnd:(LoopMeAdDisplayController *)adDisplayController;
- (void)adDisplayControllerDidDismissModal:(LoopMeAdDisplayController *)adDisplayController;
- (void)adDisplayControllerWillExpandAd:(LoopMeAdDisplayController *)adDisplayController;
- (void)adDisplayControllerWillCollapse:(LoopMeAdDisplayController *)adDisplayController;
- (UIViewController *)viewControllerForPresentation;
- (UIView *)containerView;

@end
