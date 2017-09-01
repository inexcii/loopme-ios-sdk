//
//  LoopMeInterstitial.m
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 6/21/12.
//  Copyright (c) 2012 LoopMe. All rights reserved.
//

#import "LoopMeDefinitions.h"
#import "LoopMeInterstitial.h"
#import "LoopMeInterstitialGeneral.h"
#import "LoopMeTargeting.h"
#import "LoopMeGeoLocationProvider.h"
#import "LoopMeError.h"
#import "LoopMeLogging.h"
#import "LoopMeGlobalSettings.h"
#import "LoopMeErrorEventSender.h"
#import "LoopMeAnalyticsProvider.h"

static NSString * const kLoopMeIntegrationTypeNormal = @"normal";
static const NSTimeInterval kLoopMeTimeToReload = 900;

@interface LoopMeInterstitial ()
<
    LoopMeInterstitialGeneralDelegate
>

@property (nonatomic, assign, getter = isLoading) BOOL loading;
@property (nonatomic, assign, getter = isReady) BOOL ready;

@property (nonatomic) LoopMeInterstitialGeneral *interstitial1;
@property (nonatomic) LoopMeInterstitialGeneral *interstitial2;
@property (nonatomic) LoopMeTargeting *targeting;

@property (nonatomic, assign) NSInteger showCount;
@property (nonatomic, assign) NSInteger failCount;
@property (nonatomic, strong) NSTimer *timerToReload;

@end

@implementation LoopMeInterstitial

#pragma mark - Life Cycle

- (void)dealloc {
    self.interstitial1 = nil;
    self.interstitial2 = nil;
}

- (instancetype)initWithAppKey:(NSString *)appKey
                      delegate:(id<LoopMeInterstitialDelegate>)delegate {
    
    if (self = [super init]) {
        _interstitial1 = [LoopMeInterstitialGeneral interstitialWithAppKey:appKey delegate:self];
        _interstitial2 = [LoopMeInterstitialGeneral interstitialWithAppKey:appKey delegate:self];
        _delegate = delegate;
        _autoLoading = YES;
        _showCount = 0;
        _failCount = 0;
    }
    return self;
}

- (void)setDoNotLoadVideoWithoutWiFi:(BOOL)doNotLoadVideoWithoutWiFi {
    [LoopMeGlobalSettings sharedInstance].doNotLoadVideoWithoutWiFi = doNotLoadVideoWithoutWiFi;
}

- (void)setAutoLoading:(BOOL)autoLoading {
    _autoLoading = autoLoading;
    self.failCount = 0;
    self.showCount = 0;
}

#pragma mark - Class Methods

+ (LoopMeInterstitial *)interstitialWithAppKey:(NSString *)appKey
                                             delegate:(id<LoopMeInterstitialDelegate>)delegate {
    return [[LoopMeInterstitial alloc] initWithAppKey:appKey delegate:delegate];
}

#pragma mark - Private

- (void)reload {
    self.failCount = 0;
    [self.timerToReload invalidate];
    self.timerToReload = nil;
    [self loadAdWithTargeting:self.targeting integrationType:kLoopMeIntegrationTypeNormal];
}

#pragma mark - Public Mehtods

- (void)loadAd {
    [self loadAdWithTargeting:nil];
}

- (void)loadAdWithTargeting:(LoopMeTargeting *)targeting {
    self.targeting = targeting;
    [self loadAdWithTargeting:targeting integrationType:kLoopMeIntegrationTypeNormal];
}

- (void)loadAdWithTargeting:(LoopMeTargeting *)targeting integrationType:(NSString *)integrationType {
    if (self.failCount >= 5) {
        return;
    }
    [self.interstitial1 loadAdWithTargeting:targeting integrationType:integrationType];
    if (self.isAutoLoading) {
        [self.interstitial2 loadAdWithTargeting:targeting integrationType:integrationType];
    }
}

- (void)showFromViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (!self.isAutoLoading || self.showCount % 2 == 0) {
        [self.interstitial1 showFromViewController:viewController animated:animated];
    } else {
        [self.interstitial2 showFromViewController:viewController animated:animated];
    }
    self.showCount += 1;
}

- (void)dismissAnimated:(BOOL)animated {
    [self.interstitial1 dismissAnimated:animated];
    if (self.isAutoLoading) {
        [self.interstitial2 dismissAnimated:animated];
    }
}

- (BOOL)isReady {
    return self.interstitial1.isReady || self.interstitial2.isReady;
}

#pragma mark - LoopMeInterstitialDelegate

- (void)loopMeInterstitialDidAppear:(LoopMeInterstitialGeneral *)interstitial {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidAppear:)]) {
        [self.delegate loopMeInterstitialDidAppear:self];
    }
}

- (void)loopMeInterstitialDidExpire:(LoopMeInterstitialGeneral *)interstitial {
    
    if (self.autoLoading) {
        [interstitial loadAdWithTargeting:self.targeting integrationType:kLoopMeIntegrationTypeNormal];
    }
    
    if (!self.autoLoading || !self.isReady) {
        if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidExpire:)]) {
            [self.delegate loopMeInterstitialDidExpire:self];
        }
    }
}

- (void)loopMeInterstitialDidLoadAd:(LoopMeInterstitialGeneral *)interstitial {
    self.failCount = 0;
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidLoadAd:)]) {
        [self.delegate loopMeInterstitialDidLoadAd:self];
    }
}

- (void)loopMeInterstitialWillAppear:(LoopMeInterstitialGeneral *)interstitial {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialWillAppear:)]) {
        [self.delegate loopMeInterstitialWillAppear:self];
    }
}

- (void)loopMeInterstitialDidDisappear:(LoopMeInterstitialGeneral *)interstitial {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidDisappear:)]) {
        [self.delegate loopMeInterstitialDidDisappear:self];
    }
    
    if (self.autoLoading && self.failCount < 5) {
        [interstitial loadAdWithTargeting:self.targeting integrationType:kLoopMeIntegrationTypeNormal];
    
        if (self.isReady) {
            if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidLoadAd:)]) {
                [self.delegate loopMeInterstitialDidLoadAd:self];
            }
        }
    }
}

- (void)loopMeInterstitialDidReceiveTap:(LoopMeInterstitialGeneral *)interstitial {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialDidReceiveTap:)]) {
        [self.delegate loopMeInterstitialDidReceiveTap:self];
    }
}

- (void)loopMeInterstitialWillDisappear:(LoopMeInterstitialGeneral *)interstitial {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialWillDisappear:)]) {
        [self.delegate loopMeInterstitialWillDisappear:self];
    }
}

- (void)loopMeInterstitialVideoDidReachEnd:(LoopMeInterstitialGeneral *)interstitial {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialVideoDidReachEnd:)]) {
        [self.delegate loopMeInterstitialVideoDidReachEnd:self];
    }
}

- (void)loopMeInterstitialWillLeaveApplication:(LoopMeInterstitialGeneral *)interstitial {
    if ([self.delegate respondsToSelector:@selector(loopMeInterstitialWillLeaveApplication:)]) {
        [self.delegate loopMeInterstitialWillLeaveApplication:self];
    }
}

- (void)loopMeInterstitial:(LoopMeInterstitialGeneral *)interstitial didFailToLoadAdWithError:(NSError *)error {
    
    if (self.autoLoading) {
    
        if (self.timerToReload.isValid) {
            return;
        }
        
        if (self.failCount >= 5) {
            self.timerToReload = [NSTimer scheduledTimerWithTimeInterval:kLoopMeTimeToReload target:self selector:@selector(reload) userInfo:nil repeats:NO];
            if ([self.delegate respondsToSelector:@selector(loopMeInterstitial:didFailToLoadAdWithError:)]) {
                [self.delegate loopMeInterstitial:self didFailToLoadAdWithError:error];
            }
            return;
        }
        
        self.failCount += 1;
        [interstitial loadAdWithTargeting:self.targeting integrationType:kLoopMeIntegrationTypeNormal];
    } else {
        if (!self.isReady) {
            if ([self.delegate respondsToSelector:@selector(loopMeInterstitial:didFailToLoadAdWithError:)]) {
                [self.delegate loopMeInterstitial:self didFailToLoadAdWithError:error];
            }
        }
    }
}


@end
