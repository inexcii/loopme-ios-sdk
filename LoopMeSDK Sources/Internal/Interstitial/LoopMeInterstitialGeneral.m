//
//  LoopMeInterstitial.m
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 6/21/12.
//  Copyright (c) 2012 LoopMe. All rights reserved.
//

#import "LoopMeAdConfiguration.h"
#import "LoopMeDefinitions.h"
#import "LoopMeInterstitialGeneral.h"
#import "LoopMeAdManager.h"
#import "LoopMeTargeting.h"
#import "LoopMeGeoLocationProvider.h"
#import "LoopMeAdDisplayController.h"
#import "LoopMeInterstitialViewController.h"
#import "LoopMeError.h"
#import "LoopMeLogging.h"
#import "LoopMeGlobalSettings.h"
#import "LoopMeErrorEventSender.h"
#import "LoopMeAnalyticsProvider.h"

@interface LoopMeInterstitialGeneral ()
<
    LoopMeAdManagerDelegate,
    LoopMeAdDisplayControllerDelegate,
    LoopMeInterstitialViewControllerDelegate
>
@property (nonatomic, assign, getter = isLoading) BOOL loading;
@property (nonatomic, assign, getter = isReady) BOOL ready;
@property (nonatomic, strong) LoopMeAdConfiguration *adConfiguration;
@property (nonatomic, strong) LoopMeAdManager *adManager;
@property (nonatomic, strong) LoopMeAdDisplayController *adDisplayController;
@property (nonatomic, strong) LoopMeInterstitialViewController *adInterstitialViewController;
@property (nonatomic, strong) NSTimer *timeoutTimer;

@end

@implementation LoopMeInterstitialGeneral

#pragma mark - Life Cycle

- (void)dealloc {
    if (self.adInterstitialViewController.presentingViewController) {
        [self.adInterstitialViewController.presentingViewController dismissViewControllerAnimated:NO completion:nil];
    }
    [self unRegisterObserver];
    [_adManager invalidateTimers];
    [_adDisplayController stopHandlingRequests];
    _adDisplayController.delegate = nil;
}

- (instancetype)initWithAppKey:(NSString *)appKey
            delegate:(id<LoopMeInterstitialGeneralDelegate>)delegate {
    if (!appKey) {
        LoopMeLogError(@"AppKey cann't be nil");
        return nil;
    }
    
    if (SYSTEM_VERSION_LESS_THAN(@"9.0")) {
        LoopMeLogDebug(@"Block iOS versions less then 9.0");
        return nil;
    }
    
    if (self = [super init]) {
        _appKey = [appKey copy];
        _delegate = delegate;
        [self registerObserver];
        _adManager = [[LoopMeAdManager alloc] initWithDelegate:self];
        _adDisplayController = [[LoopMeAdDisplayController alloc] initWithDelegate:self];
        _adInterstitialViewController = [[LoopMeInterstitialViewController alloc] init];
        _adInterstitialViewController.delegate = self;
        LoopMeLogInfo(@"Interstitial is initialized with appKey %@", appKey);
        
        [LoopMeAnalyticsProvider sharedInstance];
    }
    return self;
}

- (void)setDoNotLoadVideoWithoutWiFi:(BOOL)doNotLoadVideoWithoutWiFi {
    [LoopMeGlobalSettings sharedInstance].doNotLoadVideoWithoutWiFi = doNotLoadVideoWithoutWiFi;
}

#pragma mark - Class Methods

+ (LoopMeInterstitialGeneral *)interstitialWithAppKey:(NSString *)appKey
                                      delegate:(id<LoopMeInterstitialGeneralDelegate>)delegate {
    return [[LoopMeInterstitialGeneral alloc] initWithAppKey:appKey delegate:delegate];
}

+ (NSMutableArray *)sharedInterstitials {
    static NSMutableArray *sharedInterstitials;
    
    @synchronized(self) {
        if (!sharedInterstitials) {
            sharedInterstitials = [NSMutableArray array];
        }
    }
    return sharedInterstitials;
}

+ (void)removeSharedInterstitial:(LoopMeInterstitialGeneral *)interstitial {
    if ([[[self class] sharedInterstitials] containsObject:interstitial]) {
        [interstitial dismissAnimated:NO];
        LoopMeLogInfo(@"Removing interstitial ad for appKey:%@", interstitial.appKey);
        [[[self class] sharedInterstitials] removeObject:interstitial];
    } else {
        LoopMeLogInfo(@"Interstitial ad for appKey:%@ not found", interstitial.appKey);
    }
}

#pragma mark - Private

- (void)unRegisterObserver {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)registerObserver {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)willResignActive:(NSNotification *)n {
    self.adDisplayController.visible = NO;
}

- (void)didBecomeActive:(NSNotification *)n {
    self.adDisplayController.visible = YES;
}

- (void)failedLoadingAdWithError:(NSError *)error {
    self.loading = NO;
    self.ready = NO;
    [self invalidateTimer];
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitial:didFailToLoadAdWithError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeInterstitial:self didFailToLoadAdWithError:error];
        });
    }
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

#pragma mark - Public Mehtods

- (void)setServerBaseURL:(NSURL *)URL {
    self.adManager.testServerBaseURL = URL;
}

- (void)loadAd {
    [self loadAdWithTargeting:nil];
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
    self.loading = YES;
    self.ready = NO;
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:300 target:self selector:@selector(timeOut) userInfo:nil repeats:NO];
    [self.adManager loadAdWithAppKey:self.appKey targeting:targeting integrationType:integrationType adSpotSize:self.containerView.bounds.size];
}

- (void)showFromViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (!self.isReady) {
        LoopMeLogInfo(@"Ad isn't ready to be displayed");
        [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeCustom errorMessage:@"Ad isn't ready to be displayed" appkey:self.appKey];
        return;
    }
    
    if (self.adInterstitialViewController.presentingViewController) {
        LoopMeLogInfo(@"Ad has already displayed");
        [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeCustom errorMessage:@"Ad has already displayed" appkey:self.appKey];
        return;
    }

    LoopMeLogDebug(@"Interstitial ad will appear");
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialWillAppear:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeInterstitialWillAppear:self];
        });
    }
    [self.adManager invalidateTimers];
    [self.adInterstitialViewController setOrientation:self.adConfiguration.orientation];
    [self.adInterstitialViewController setAllowOrientationChange:self.adConfiguration.allowOrientationChange];
    [self.adDisplayController displayAd];
    self.adDisplayController.visible = YES;
    
    [viewController presentViewController:self.adInterstitialViewController animated:animated completion:^{
        [self.adDisplayController layoutSubviews];
        LoopMeLogDebug(@"Interstitial ad did appear");
        
        if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidAppear:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                 [self.delegate loopMeInterstitialDidAppear:self];
            });
        }
    }];
}

- (void)dismissAnimated:(BOOL)animated {
    if (!self.adInterstitialViewController.presentingViewController) {
        return;
    }
    self.ready = NO;
    LoopMeLogDebug(@"Interstitial ad will disappear");
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialWillDisappear:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeInterstitialWillDisappear:self];
        });
    }
    
    [self.adDisplayController closeAd];

    [self.adInterstitialViewController.presentingViewController dismissViewControllerAnimated:animated completion:^{
        LoopMeLogDebug(@"Interstitial ad did disappear");
        if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidDisappear:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate loopMeInterstitialDidDisappear:self];
            });
        }
    }];
}

#pragma mark - LoopMeAdManagerDelegate

- (void)adManager:(LoopMeAdManager *)manager didReceiveAdConfiguration:(LoopMeAdConfiguration *)adConfiguration {
    if (!adConfiguration) {
        NSString *errorMessage = @"Could not process ad: interstitial format expected.";
        LoopMeLogDebug(errorMessage);
        NSError *error = [LoopMeError errorForStatusCode:LoopMeErrorCodeIncorrectFormat];
        [self failedLoadingAdWithError:error];
        return;
    }
    self.adConfiguration = adConfiguration;
    
    [[LoopMeGlobalSettings sharedInstance].adIds setObject:adConfiguration.adIdsForMOAT forKey:self.appKey];
    
    if ([LoopMeGlobalSettings sharedInstance].liveDebugEnabled ) {
        [LoopMeGlobalSettings sharedInstance].appKeyForLiveDebug = self.appKey;
    }
    [self.adDisplayController loadConfiguration:self.adConfiguration];
}

- (void)adManager:(LoopMeAdManager *)manager didFailToLoadAdWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self failedLoadingAdWithError:error];
    });
}

- (void)adManagerDidExpireAd:(LoopMeAdManager *)manager {
    self.ready = NO;
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidExpire:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeInterstitialDidExpire:self];
        });
    }
}

#pragma mark - LoopMeInterstitialViewControllerDelegate

- (void)viewWillTransitionToSize:(CGSize)size {
    [self.adDisplayController layoutSubviewsToFrame:CGRectMake(0, 0, size.width, size.height)];
    [self.adDisplayController resizeTo:size];
}

#pragma mark - LoopMeAdDisplayControllerDelegate

- (UIViewController *)viewControllerForPresentation {
    return self.adInterstitialViewController;
}

- (UIView *)containerView {
    return self.adInterstitialViewController.view;
}

- (void)adDisplayControllerDidFinishLoadingAd:(LoopMeAdDisplayController *)adDisplayController {
    self.loading = NO;
    self.ready = YES;
    [self invalidateTimer];
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidLoadAd:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeInterstitialDidLoadAd:self];
        });
    }
}

- (void)adDisplayController:(LoopMeAdDisplayController *)adDisplayController didFailToLoadAdWithError:(NSError *)error {
    [self failedLoadingAdWithError:error];
}

- (void)adDisplayControllerDidReceiveTap:(LoopMeAdDisplayController *)adDisplayController {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidReceiveTap:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeInterstitialDidReceiveTap:self];
        });
    }
}

- (void)adDisplayControllerWillLeaveApplication:(LoopMeAdDisplayController *)adDisplayController {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialWillLeaveApplication:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeInterstitialWillLeaveApplication:self];
        });
    }
}

- (void)adDisplayControllerVideoDidReachEnd:(LoopMeAdDisplayController *)adDisplayController {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialVideoDidReachEnd:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loopMeInterstitialVideoDidReachEnd:self];
        });
    }
}

- (void)adDisplayControllerWillExpandAd:(LoopMeAdDisplayController *)adDisplayController {
    
}

- (void)adDisplayControllerShouldCloseAd:(LoopMeAdDisplayController *)adDisplayController {
    [self dismissAnimated:NO];
}

- (void)adDisplayControllerDidDismissModal:(LoopMeAdDisplayController *)adDisplayController {
    self.adDisplayController.visible = YES;
}

- (void)adDisplayControllerWillCollapse:(LoopMeAdDisplayController *)adDisplayController {
    
}

@end
