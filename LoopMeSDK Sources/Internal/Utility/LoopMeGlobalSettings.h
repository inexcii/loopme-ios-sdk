//
//  LoopMeGlobalSettings.h
//  LoopMeSDK
//
//  Created by Kogda Bogdan on 6/16/15.
//
//

#import <Foundation/Foundation.h>

static const NSString *kLoopMeAdvertiser = @"ADVERTISER";
static const NSString *kLoopMeCampaign = @"CAMP_NAME";
static const NSString *kLoopMeLineItem = @"LI_NAME";
static const NSString *kLoopMeCreative = @"CREATIVEID";
static const NSString *kLoopMeAPP = @"APP_NAME";
static const NSString *kLoopMePlacement = @"PLACEMENT";

@interface LoopMeGlobalSettings : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, assign, getter = isDoNotLoadVideoWithoutWiFi) BOOL doNotLoadVideoWithoutWiFi;
@property (nonatomic, assign, getter = isLiveDebugEnabled) BOOL liveDebugEnabled;
@property (nonatomic, assign, getter = isPreload25Enabled) BOOL preload25;
@property (nonatomic, strong) NSString *appKeyForLiveDebug;
@property (nonatomic, strong) NSMutableDictionary *adIds;

@end
