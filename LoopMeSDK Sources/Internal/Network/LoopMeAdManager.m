//
//  LoopMeInterstitialManager.m
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 07/11/13.
//  Copyright (c) 2013 LoopMe. All rights reserved.
//

#import "LoopMeAdManager.h"
#import "LoopMeServerURLBuilder.h"
#import "LoopMeServerCommunicator.h"
#import "LoopMeAdConfiguration.h"
#import "LoopMeDefinitions.h"
#import "LoopMeInterstitialViewController.h"
#import "LoopMeAdDisplayController.h"
#import "LoopMeLogging.h"

@interface LoopMeAdManager ()
<
    LoopMeServerCommunicatorDelegate
>

@property (nonatomic, strong) LoopMeServerCommunicator *communicator;
@property (nonatomic, assign, readwrite, getter = isReady) BOOL ready;
@property (nonatomic, assign, readwrite, getter = isLoading) BOOL loading;
@property (nonatomic, strong) NSTimer *adExpirationTimer;

@end

@implementation LoopMeAdManager

#pragma mark - Life Cycle

- (void)dealloc {
    [_adExpirationTimer invalidate];
    _adExpirationTimer = nil;
    
    [_communicator cancel];    
}

- (instancetype)initWithDelegate:(id<LoopMeAdManagerDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _communicator = [[LoopMeServerCommunicator alloc] initWithDelegate:self];
    }
    return self;
}

#pragma mark - Private

- (void)loadAdWithURL:(NSURL *)URL {
    if (self.isLoading) {
        LoopMeLogInfo(@"Interstitial is already loading an ad. Wait for previous load to finish");
        return;
    }

    self.loading = YES;
    LoopMeLogInfo(@"Did start loading ad");
    LoopMeLogDebug(@"loads ad with URL %@", [URL absoluteString]);
    [self.communicator loadURL:URL];
}

- (void)scheduleAdExpirationIn:(NSTimeInterval)interval {
    self.adExpirationTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                            target:self
                                                          selector:@selector(adContentBecameExpired)
                                                          userInfo:nil
                                                           repeats:NO];
}

- (void)adContentBecameExpired {
    [self invalidateTimers];
    LoopMeLogDebug(@"Ad content is expired");
    if ([self.delegate respondsToSelector:@selector(adManagerDidExpireAd:)]) {
        [self.delegate adManagerDidExpireAd:self];
    }
}

#pragma mark - Public

- (void)loadAdWithAppKey:(NSString *)appKey targeting:(LoopMeTargeting *)targeting
         integrationType:(NSString *)integrationType adSpotSize:(CGSize)size {
    if (self.testServerBaseURL) {
        [self loadAdWithURL:[LoopMeServerURLBuilder URLWithAppKey:appKey
                                                        targeting:targeting
                                                          baseURL:self.testServerBaseURL integrationType:integrationType adSpotSize:size]];
    } else {
        [self loadAdWithURL:[LoopMeServerURLBuilder URLWithAppKey:appKey
                                                        targeting:targeting integrationType:integrationType adSpotSize:size]];
    }
}

- (void)invalidateTimers {
    [self.adExpirationTimer invalidate];
    self.adExpirationTimer = nil;
}

#pragma mark - LoopMeServerCommunicatorDelegate

- (void)serverCommunicator:(LoopMeServerCommunicator *)communicator didReceiveAdConfiguration:(LoopMeAdConfiguration *)adConfiguration {
    LoopMeLogDebug(@"Did receive ad configuration: %@", adConfiguration);
    
    if ([self.delegate respondsToSelector:@selector(adManager:didReceiveAdConfiguration:)]) {
        [self.delegate adManager:self didReceiveAdConfiguration:adConfiguration];
    }
    self.loading = NO;
    [self scheduleAdExpirationIn:adConfiguration.expirationTime];
}

- (void)serverCommunicator:(LoopMeServerCommunicator *)communicator didFailWithError:(NSError *)error {
    self.loading = NO;
    LoopMeLogDebug(@"Ad failed to load with error: %@", error);
    
    if ([self.delegate respondsToSelector:@selector(adManager:didFailToLoadAdWithError:)]) {
        [self.delegate adManager:self didFailToLoadAdWithError:error];
    }
}

@end
