//
//  Nativevideo.m
//  LoopMeSDK
//
//  Created by Kogda Bogdan on 2/13/15.
//  Copyright (c) 2012 LoopMe. All rights reserved.
//

#import "LoopMeAdView.h"
#import "LoopMeAdManager.h"
#import "LoopMeAdDisplayController.h"
#import "LoopMeAdConfiguration.h"
#import "LoopMeDefinitions.h"
#import "LoopMeError.h"
#import "LoopMeLogging.h"
#import "LoopMeMinimizedAdView.h"
#import "LoopMeMaximizedViewController.h"
#import "LoopMeGlobalSettings.h"
#import "LoopMeErrorEventSender.h"
#import "LoopMeAnalyticsProvider.h"

@interface LoopMeAdView ()
<
    LoopMeAdManagerDelegate,
    LoopMeAdDisplayControllerDelegate,
    LoopMeMinimizedAdViewDelegate,
    LoopMeMaximizedViewControllerDelegate
>
@property (nonatomic, strong) LoopMeAdManager *adManager;
@property (nonatomic, strong) LoopMeAdDisplayController *adDisplayController;
@property (nonatomic, strong) LoopMeMinimizedAdView *minimizedView;
@property (nonatomic, strong) LoopMeMaximizedViewController *maximizedController;
@property (nonatomic, strong) NSString *appKey;
@property (nonatomic, assign, getter = isLoading) BOOL loading;
@property (nonatomic, assign, getter = isReady) BOOL ready;
@property (nonatomic, assign, getter = isMinimized) BOOL minimized;
@property (nonatomic, assign, getter = isNeedsToBeDisplayedWhenReady) BOOL needsToBeDisplayedWhenReady;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, strong) LoopMeAdConfiguration *adConfiguration;

/*
 * Update webView "visible" state is required on JS first time when ad appears on the screen,
 * further, we're ommiting sending "webView" states to JS but managing video ad. playback in-SDK
 */
@property (nonatomic, assign, getter = isVisibilityUpdated) BOOL visibilityUpdated;
@end

@implementation LoopMeAdView

#pragma mark - Initialization

- (void)dealloc {
    [self unRegisterObservers];
    [_minimizedView removeFromSuperview];
    [_maximizedController hide];
    [_adDisplayController stopHandlingRequests];
}

- (instancetype)initWithAppKey:(NSString *)appKey
                         frame:(CGRect)frame
                    scrollView:(UIScrollView *)scrollView
                      delegate:(id<LoopMeAdViewDelegate>)delegate {
    self = [super init];
    if (self) {
        
        if (SYSTEM_VERSION_LESS_THAN(@"9.0")) {
            LoopMeLogDebug(@"Block iOS versions less then 9.0");
            return nil;
        }
        
        _appKey = appKey;
        _delegate = delegate;
        _adManager = [[LoopMeAdManager alloc] initWithDelegate:self];
        _adDisplayController = [[LoopMeAdDisplayController alloc] initWithDelegate:self];
        _maximizedController = [[LoopMeMaximizedViewController alloc] initWithDelegate:self];
        _scrollView = scrollView;
        self.frame = frame;
        self.backgroundColor = [UIColor blackColor];
        [self registerObservers];
        LoopMeLogInfo(@"Ad view initialized with appKey: %@", appKey);
        
        [LoopMeAnalyticsProvider sharedInstance];
    }
    return self;
}

- (void)setMinimizedModeEnabled:(BOOL)minimizedModeEnabled {
    if (_minimizedModeEnabled != minimizedModeEnabled) {
        _minimizedModeEnabled = minimizedModeEnabled;
        if (_minimizedModeEnabled) {
            _minimizedView = [[LoopMeMinimizedAdView alloc] initWithDelegate:self];
            _minimizedView.backgroundColor = [UIColor blackColor];
            _minimizedView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
            [[UIApplication sharedApplication].keyWindow addSubview:_minimizedView];
        } else {
            [self removeMinimizedView];
        }
    }
}

- (void)setDoNotLoadVideoWithoutWiFi:(BOOL)doNotLoadVideoWithoutWiFi {
    [LoopMeGlobalSettings sharedInstance].doNotLoadVideoWithoutWiFi = doNotLoadVideoWithoutWiFi;
}

- (void)expand {
    BOOL isMaximized = [self.maximizedController presentingViewController] != nil;
    if (!isMaximized) {
        if (self.adConfiguration.isMraid) {
            [self.adDisplayController setExpandProperties:self.adConfiguration];
            [self.adDisplayController setOrientationProperties:nil];
        }
        [self.maximizedController show];
        [self.adDisplayController moveView:NO];
        [self.adDisplayController expandReporting];
    }
}

#pragma mark - Class Methods

+ (LoopMeAdView *)adViewWithAppKey:(NSString *)appKey
                             frame:(CGRect)frame
                        scrollView:(UIScrollView *)scrollView
                          delegate:(id<LoopMeAdViewDelegate>)delegate {
    return [[self alloc] initWithAppKey:appKey frame:frame scrollView:scrollView delegate:delegate];
}

+ (LoopMeAdView *)adViewWithAppKey:(NSString *)appKey
                             frame:(CGRect)frame
                          delegate:(id<LoopMeAdViewDelegate>)delegate {
    return [LoopMeAdView adViewWithAppKey:appKey frame:frame scrollView:nil delegate:delegate];
}

#pragma mark - LifeCycle

- (void)willMoveToSuperview:(UIView *)newSuperview {
    [super willMoveToSuperview:newSuperview];
    if (!newSuperview) {
        [self closeAd];
        
        if ([self.delegate respondsToSelector:@selector(loopMeAdViewWillDisappear:)]) {
            [self.delegate loopMeAdViewWillDisappear:self];
        }
    } else {
        if (!self.isReady) {
            [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeCustom errorMessage:@"Banner added to view, but wasn't ready to be displayed" appkey:self.appKey];
            self.needsToBeDisplayedWhenReady = YES;
        }
        
        if ([self.delegate respondsToSelector:@selector(loopMeAdViewWillAppear:)]) {
            [self.delegate loopMeAdViewWillAppear:self];
        }
    }
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    
    if (self.superview && self.isReady)
        [self performSelector:@selector(displayAd) withObject:nil afterDelay:0.0];
}

#pragma mark - Observering

- (void)unRegisterObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)registerObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceOrientationDidChange:)
                                                 name:UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];

    
}

- (void)didBecomeActive:(NSNotification *)notification {
    if (self.superview) {
        self.visibilityUpdated = NO;
        [self updateVisibility];
    }
}

#pragma mark - Public

- (void)setServerBaseURL:(NSURL *)URL {
    self.adManager.testServerBaseURL = URL;
}

- (void)loadAd {
    [self loadAdWithTargeting:nil integrationType:@"normal"];
}

- (void)loadAdWithTargeting:(LoopMeTargeting *)targeting {
    [self loadAdWithTargeting:targeting integrationType:@"normal"];
}

- (void)loadAdWithTargeting:(LoopMeTargeting *)targeting integrationType:(NSString *)integrationType {
    if (self.isLoading) {
        LoopMeLogInfo(@"Wait for previous loading ad process finish");
        return;
    }
    if (self.isReady) {
        LoopMeLogInfo(@"Ad already loaded and ready to be displayed");
        return;
    }
    self.ready = NO;
    self.loading = YES;
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:300 target:self selector:@selector(timeOut) userInfo:nil repeats:NO];
    [self.adManager loadAdWithAppKey:self.appKey targeting:targeting integrationType:integrationType adSpotSize:self.containerView.bounds.size];
}

- (void)setAdVisible:(BOOL)visible {
    if (self.isReady) {

        self.adDisplayController.forceHidden = !visible;
        self.adDisplayController.visible = visible;
        
        if (self.isMinimizedModeEnabled && self.scrollView) {
            if (!visible) {
                [self toOriginalSize];
            } else {
                [self updateAdVisibilityInScrollView];
            }
        }
    }
}

/*
 * Don't set visible/hidden state during scrolling, causes issues on iOS 8.0 and up
 */
- (void)updateAdVisibilityInScrollView {
    if (!self.superview) {
        return;
    }
    
    if ([self.maximizedController isBeingPresented]) {
        self.adDisplayController.visibleNoJS = YES;
        return;
    }
    
    if (self.adDisplayController.destinationIsPresented) {
        return;
    }

    CGRect relativeToScrollViewAdRect = [self convertRect:self.bounds toView:self.scrollView];
    CGRect visibleScrollViewRect = CGRectMake(self.scrollView.contentOffset.x, self.scrollView.contentOffset.y, self.scrollView.bounds.size.width, self.scrollView.bounds.size.height);
    
    if (![self isRect:relativeToScrollViewAdRect outOfRect:visibleScrollViewRect]) {
        if (self.isMinimizedModeEnabled && self.minimizedView.superview) {
            [self updateAdVisibilityWhenScroll];
            [self minimize];
        }
    } else {
        [self toOriginalSize];
    }
    
    if (self.isMinimized) {
        return;
    }
    
    if ([self moreThenHalfOfRect:relativeToScrollViewAdRect visibleInRect:visibleScrollViewRect]) {
        [self updateAdVisibilityWhenScroll];
    } else {
        self.adDisplayController.visibleNoJS = NO;
    }
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
    [self.minimizedView rotateToInterfaceOrientation:[UIApplication sharedApplication].statusBarOrientation animated:YES];
    [self.minimizedView adjustFrame];
}

#pragma mark - Private

- (void)willResignActive:(NSNotification *)n {
    self.adDisplayController.visible = NO;
    if ([self.maximizedController isBeingPresented]) {
        [self removeMaximizedView];
    }
}

- (void)minimize {
    if (!self.isMinimized && self.adDisplayController.isVisible) {
        self.minimized = YES;
        [self.minimizedView show];
        [self.adDisplayController moveView:YES];
    }
}

- (void)toOriginalSize {
    if (self.isMinimized) {
        self.minimized = NO;
        [self.minimizedView hide];
        [self.adDisplayController moveView:NO];
    }
}

- (void)removeMinimizedView {
    [self.minimizedView removeFromSuperview];
    self.minimizedView = nil;
}

- (void)removeMaximizedView {
    [self.maximizedController hide];
    [self.adDisplayController moveView:NO];
    [self.adDisplayController collapseReporting];
}

- (BOOL)moreThenHalfOfRect:(CGRect)rect visibleInRect:(CGRect)visibleRect {
    return (CGRectContainsPoint(visibleRect, CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect))));
}

- (BOOL)isRect:(CGRect)rect outOfRect:(CGRect)visibleRect {
    return CGRectIntersectsRect(rect, visibleRect);
}

- (void)failedLoadingAdWithError:(NSError *)error {
    self.loading = NO;
    self.ready = NO;
    [self invalidateTimer];
    if ([self.delegate respondsToSelector:@selector(loopMeAdView:didFailToLoadAdWithError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeAdView:self didFailToLoadAdWithError:error];
        });
    }
}

- (void)updateVisibility {
    if (!self.scrollView) {
        self.adDisplayController.visible = YES;
    } else {
        [self updateAdVisibilityInScrollView];
    }
}

- (void)updateAdVisibilityWhenScroll {
    if (!self.isVisibilityUpdated) {
        self.adDisplayController.visible = YES;
        self.visibilityUpdated = YES;
    } else {
        self.adDisplayController.visibleNoJS = YES;
    }
}

- (void)closeAd {
    [self.minimizedView removeFromSuperview];
    [self.maximizedController hide];
    [self.adDisplayController closeAd];
    self.ready = NO;
    self.loading = NO;
}

- (void)displayAd {
    [self.adDisplayController displayAd];
    [self.adManager invalidateTimers];
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        return;
    }
    [self updateVisibility];
}

- (BOOL)isMaximizedControllerIsPresented {
    return self.maximizedController.isViewLoaded && self.maximizedController.view.window;
}

- (void)timeOut {
    [self.adDisplayController stopHandlingRequests];
    [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeServer errorMessage:@"Time out" appkey:self.appKey];
    [self failedLoadingAdWithError:[LoopMeError errorForStatusCode:LoopMeErrorCodeHTMLRequestTimeOut]];
}

- (void)invalidateTimer {
    [self.timeoutTimer invalidate];
    self.timeoutTimer = nil;
}

#pragma mark - LoopMeAdManagerDelegate

- (void)adManager:(LoopMeAdManager *)manager didReceiveAdConfiguration:(LoopMeAdConfiguration *)adConfiguration {
    if (!adConfiguration) {
        NSString *errorMessage = @"Could not process ad: interstitial format expected.";
        LoopMeLogDebug(errorMessage);
        [self failedLoadingAdWithError:[LoopMeError errorForStatusCode:LoopMeErrorCodeIncorrectFormat]];
        return;
    }
    self.adConfiguration = adConfiguration;
    [[LoopMeGlobalSettings sharedInstance].adIds setObject:adConfiguration.adIdsForMOAT forKey:self.appKey];
    [self.adDisplayController loadConfiguration:self.adConfiguration];
}

- (void)adManager:(LoopMeAdManager *)manager didFailToLoadAdWithError:(NSError *)error {
    self.ready = NO;
    self.loading = NO;
    [self failedLoadingAdWithError:error];
}

- (void)adManagerDidExpireAd:(LoopMeAdManager *)manager {
    self.ready = NO;
    if ([self.delegate respondsToSelector:@selector(loopMeAdViewDidExpire:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeAdViewDidExpire:self];
        });
    }
}

#pragma mark - LoopMeMinimizedAdViewDelegate

- (void)minimizedAdViewShouldRemove:(LoopMeMinimizedAdView *)minimizedAdView {
    [self toOriginalSize];
    [self.minimizedView removeFromSuperview];
    self.minimizedView = nil;
    [self updateAdVisibilityInScrollView];
}

- (void)minimizedDidReceiveTap:(LoopMeMinimizedAdView *)minimizedAdView {
    CGRect relativeToScrollViewAdRect = [self convertRect:self.bounds toView:self.scrollView];
    [self.scrollView scrollRectToVisible:relativeToScrollViewAdRect animated:YES];
}

#pragma mark - LoopMeMaximizedAdViewDelegate

- (void)maximizedAdViewDidPresent:(LoopMeMaximizedViewController *)maximizedViewController {
    [self.adDisplayController layoutSubviews];
    [self setAdVisible:YES];
}

- (void)maximizedViewControllerShouldRemove:(LoopMeMaximizedViewController *)maximizedViewController {
    [self.adDisplayController moveView:NO];
}

- (void)maximizedControllerWillTransitionToSize:(CGSize)size {
    [self.adDisplayController resizeTo:size];
}

#pragma mark - LoopMeAdDisplayControllerDelegate

- (UIView *)containerView {
    BOOL isMaximized = [self.maximizedController presentingViewController] != nil;
    
    if (self.isMinimized) {
        return self.minimizedView;
    } else if (isMaximized) {
        return self.maximizedController.view;
    } else {
        return self;
    }
}

- (UIViewController *)viewControllerForPresentation {
    if ([self.maximizedController presentingViewController]) {
        return self.maximizedController;
    }
    
    return self.delegate.viewControllerForPresentation;
}

- (void)adDisplayControllerDidFinishLoadingAd:(LoopMeAdDisplayController *)adDisplayController {
    self.loading = NO;
    self.ready = YES;
    if (self.isNeedsToBeDisplayedWhenReady) {
        self.needsToBeDisplayedWhenReady = NO;
        [self displayAd];
    }
    
    [self invalidateTimer];
    if ([self.delegate respondsToSelector:@selector(loopMeAdViewDidLoadAd:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeAdViewDidLoadAd:self];
        });
    }
}

- (void)adDisplayController:(LoopMeAdDisplayController *)adDisplayController didFailToLoadAdWithError:(NSError *)error {
    [self failedLoadingAdWithError:error];
}

- (void)adDisplayControllerDidReceiveTap:(LoopMeAdDisplayController *)adDisplayController {
    if ([self isMaximizedControllerIsPresented] && !self.adConfiguration.isMraid) {
        [self removeMaximizedView];
    }
    if ([self.delegate respondsToSelector:@selector(loopMeAdViewDidReceiveTap:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeAdViewDidReceiveTap:self];
        });
    }
}

- (void)adDisplayControllerWillLeaveApplication:(LoopMeAdDisplayController *)adDisplayController {
    if ([self.delegate respondsToSelector:@selector(loopMeAdViewWillLeaveApplication:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeAdViewWillLeaveApplication:self];
        });
    }
}

- (void)adDisplayControllerVideoDidReachEnd:(LoopMeAdDisplayController *)adDisplayController {
    [self performSelector:@selector(removeMinimizedView) withObject:nil afterDelay:1.0];
    
    if ([self.maximizedController isBeingPresented]) {
        [self performSelector:@selector(removeMaximizedView) withObject:nil afterDelay:1.0];
    }
    
    if ([self.delegate respondsToSelector:@selector(loopMeAdViewVideoDidReachEnd:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeAdViewVideoDidReachEnd:self];
        });
    }
}

- (void)adDisplayControllerDidDismissModal:(LoopMeAdDisplayController *)adDisplayController {
    self.visibilityUpdated = NO;
    [self updateVisibility];
}

- (void)adDisplayControllerShouldCloseAd:(LoopMeAdDisplayController *)adDisplayController {
    if (self.adConfiguration.isMraid && [self.maximizedController presentingViewController]) {
        [self removeMaximizedView];
        return;
    }
    [self removeFromSuperview];
}

- (void)adDisplayControllerWillExpandAd:(LoopMeAdDisplayController *)adDisplayController {
    [self expand];
}

- (void)adDisplayControllerWillCollapse:(LoopMeAdDisplayController *)adDisplayController {
    [self removeMaximizedView];
}

- (void)adDisplayControllerAllowOrientationChange:(BOOL)allowOrientationChange orientation:(NSInteger)orientation {
    [self.maximizedController setAllowOrientationChange:allowOrientationChange];
    [self.maximizedController setOrientation:orientation];
    [self.maximizedController forceChangeOrientation];
}

- (void)adDisplayController:(LoopMeAdDisplayController *)adDisplayController willResizeAd:(CGSize)size {
    float x = self.frame.origin.x;
    float y = self.frame.origin.y;
    
    CGRect newFrame = CGRectMake(x, y, size.width, size.height);
    self.frame = newFrame;
}

@end
