//
//  LoopMeIdentityProvider.m
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 11/11/13.
//  Copyright (c) 2013 LoopMe. All rights reserved.
//

#import <AdSupport/AdSupport.h>
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

#import "NSString+Encryption.h"
#import "LoopMeIdentityProvider.h"
#import "LoopMeLogging.h"

@implementation LoopMeIdentityProvider

#pragma mark - Class Methods

+ (NSString *)advertisingTrackingDeviceIdentifier {
    NSString *identifier = nil;
    identifier = [ASIdentifierManager sharedManager].advertisingIdentifier.UUIDString;
    if (![ASIdentifierManager sharedManager].isAdvertisingTrackingEnabled) {
        identifier = @"00000000-0000-0000-0000-000000000000";
    }
    return [identifier uppercaseString];
}

+ (BOOL)advertisingTrackingEnabled {
    BOOL enabled = YES;

    if ([self deviceHasAdvertisingIdentifier]) {
        enabled = [[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled];
    }

    return enabled;
}

+ (BOOL)deviceHasAdvertisingIdentifier {
    return !!NSClassFromString(@"ASIdentifierManager");
}

+ (NSString *)deviceType {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return @"phone";
    } else if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return @"tablet";
    }
    
    return nil;
}

+ (NSString *)deviceModel {
    struct utsname systemInfo;
    uname(&systemInfo);
    
    NSString *currentModel = [NSString stringWithCString:systemInfo.machine
                                         encoding:NSUTF8StringEncoding];
    
    return currentModel;
}

+ (NSString *)phoneName {
    return [[[[UIDevice currentDevice] name] lm_AES128Encrypt] lm_stringByAddingPercentEncodingForRFC3986];
}

@end
