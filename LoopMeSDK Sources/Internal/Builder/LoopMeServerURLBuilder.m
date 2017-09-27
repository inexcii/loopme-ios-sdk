//
//  LoopMeServerURLBuilder.m
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 07/11/13.
//  Copyright (c) 2013 LoopMe. All rights reserved.
//
#import <AdSupport/AdSupport.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/CaptiveNetwork.h>

#import "LoopMeDefinitions.h"
#import "LoopMeIdentityProvider.h"
#import "LoopMeReachability.h"
#import "LoopMeServerURLBuilder.h"
#import "LoopMeTargeting.h"
#import "LoopMeGeoLocationProvider.h"
#import "LoopMeLogging.h"
#import "NSData+LoopMeAES128.h"

NSString * const kLoopMeAPIURL = @"https://loopme.me/api/loopme/ads/v3";
NSString * const kLoopMeInterfaceOrientationPortrait = @"p";
NSString * const kLoopMeInterfaceOrientationLandscape = @"l";

@implementation LoopMeServerURLBuilder

#pragma mark - Class Methods

+ (NSURL *)URLWithAppKey:(NSString *)appKey
               targeting:(LoopMeTargeting *)targeting integrationType:(NSString *)integrationType adSpotSize:(CGSize)size {
    return [LoopMeServerURLBuilder URLWithAppKey:appKey targeting:targeting
                                         baseURL:[NSURL URLWithString:kLoopMeAPIURL] integrationType:integrationType adSpotSize:size];
}

+ (NSURL *)URLWithAppKey:(NSString *)appKey
               targeting:(LoopMeTargeting *)targeting baseURL:(NSURL *)baseURL
         integrationType:(NSString *)integrationType adSpotSize:(CGSize)size {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"ak"] = appKey;
    parameters[@"vt"] = [self parameterForUniqueIdentifier];
    parameters[@"av"] = [self parameterForApplicationVersion];
    parameters[@"or"] = [self parameterForOrientation];
    parameters[@"tz"] = [self parameterForTimeZone];
    parameters[@"lng"] = [self parameterForLanguage];
    parameters[@"cn"] = [self parameterForConnectionType];
    parameters[@"dnt"] = [self parameterForDNT];
    parameters[@"bundleid"] = [self parameterForBundleIdentifier];
    parameters[@"wn"] = [self parameterForWiFiName];
    parameters[@"sv"] = [NSString stringWithFormat:@"%@", LOOPME_SDK_VERSION];
    parameters[@"mr"] = @"0";
    parameters[@"plg"] = [self parameterForBatteryState];
    parameters[@"chl"] = [NSString stringWithFormat:@"%f", [UIDevice currentDevice].batteryLevel];
    parameters[@"v360"] = @"1";
    parameters[@"devicemodel"] = [LoopMeIdentityProvider deviceModel];
    parameters[@"pn"] = [LoopMeIdentityProvider phoneName];
    parameters[@"ww"] = [self parameterForScreenWidth];
    parameters[@"wh"] = [self parameterForScreenHeight];
    parameters[@"width"] = [NSString stringWithFormat:@"%1.0f", size.width];
    parameters[@"height"] = [NSString stringWithFormat:@"%1.0f", size.height];
    parameters[@"trackers"] = [self parameterForAvailableTrackers];
    
    NSString *deviceType = [LoopMeIdentityProvider deviceType];
    if (deviceType) {
        parameters[@"devicetype"] = deviceType;
    }
    
    parameters[@"it"] = integrationType;

    if (targeting) {
        if (targeting.keywordsParameter)
            parameters[@"keywords"] = targeting.keywordsParameter;
        if (targeting.yearOfBirth)
            parameters[@"yob"] = targeting.yearOfBirthParameter;
        if (targeting.genderParameter)
            parameters[@"gender"] = targeting.genderParameter;
    }
    
    if ([[LoopMeGeoLocationProvider sharedProvider] isLocationUpdateEnabled] && [[LoopMeGeoLocationProvider sharedProvider] isValidLocation]) {
        parameters[@"lat"] = [NSString stringWithFormat:@"%0.4f", (float)[LoopMeGeoLocationProvider sharedProvider].location.coordinate.latitude];
        parameters[@"lon"] = [NSString stringWithFormat:@"%0.4f", (float)[LoopMeGeoLocationProvider sharedProvider].location.coordinate.longitude];
    }
    
    NSString *parametersString = [self buildParameters:parameters];
    NSURL *URL = [NSURL URLWithString:parametersString relativeToURL:baseURL];
    return URL;
}

+ (NSString *)packageIDs {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"vt"] = [LoopMeIdentityProvider advertisingTrackingDeviceIdentifier];
    parameters[@"av"] = [self parameterForApplicationVersion];
    parameters[@"or"] = [self parameterForOrientation];
    parameters[@"tz"] = [self parameterForTimeZone];
    parameters[@"lng"] = [self parameterForLanguage];
    parameters[@"cn"] = [self parameterForConnectionType];
    parameters[@"dnt"] = [self parameterForDNT];
    parameters[@"bundleid"] = [self parameterForBundleIdentifier];
    parameters[@"wn"] = [self parameterForWiFiName];
    parameters[@"sv"] = [NSString stringWithFormat:@"%@", LOOPME_SDK_VERSION];
    parameters[@"mr"] = @"0";
    parameters[@"plg"] = [self parameterForBatteryState];
    parameters[@"chl"] = [NSString stringWithFormat:@"%f", [UIDevice currentDevice].batteryLevel];

    if ([[LoopMeGeoLocationProvider sharedProvider] isLocationUpdateEnabled] && [[LoopMeGeoLocationProvider sharedProvider] isValidLocation]) {
        parameters[@"lat"] = [NSString stringWithFormat:@"%0.4f", (float)[LoopMeGeoLocationProvider sharedProvider].location.coordinate.latitude];
        parameters[@"lon"] = [NSString stringWithFormat:@"%0.4f", (float)[LoopMeGeoLocationProvider sharedProvider].location.coordinate.longitude];
    }
    
    NSMutableString *parametersString = [[NSMutableString alloc] init];
    [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [parametersString appendFormat:@"%@=%@&", key, value];
    }];
    parametersString = [[parametersString substringToIndex:[parametersString length]-1] mutableCopy];

    NSData *plain = [parametersString dataUsingEncoding:NSUTF8StringEncoding];

    NSData *cipher = [plain lm_AES128Encrypt];
    return [cipher base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
}

+ (NSString *)parameterForUniqueIdentifier {
    return [LoopMeIdentityProvider advertisingTrackingDeviceIdentifier];
}

+ (NSString *)parameterForLanguage {
    return [NSLocale preferredLanguages][0];
}

+ (NSString *)parameterForOrientation {
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    return UIInterfaceOrientationIsPortrait(orientation) ?
                    kLoopMeInterfaceOrientationPortrait :
                    kLoopMeInterfaceOrientationLandscape;
}

+ (NSString *)parameterForTimeZone {
    static NSDateFormatter *formatter;
    @synchronized(self) {
        if (!formatter) {
            formatter = [[NSDateFormatter alloc] init];
        }
    }
    [formatter setDateFormat:@"Z"];
    NSDate *today = [NSDate date];
    return [formatter stringFromDate:today];
}

+ (NSString *)parameterForConnectionType {
    return [NSString stringWithFormat:@"%lu", (long)[[LoopMeReachability reachabilityForLocalWiFi] connectionType]];
}

+ (NSString *)parameterForApplicationVersion {
    return [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
}

+ (NSString *)parameterForDNT {
    return ([LoopMeIdentityProvider advertisingTrackingEnabled] ? @"0" : @"1");
}

+ (NSString *)parameterForWiFiName {
    return [self fetchSSIDInfo][@"SSID"];
}

+ (NSString *)parameterForBundleIdentifier {
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    return bundleIdentifier ? [self escapeString:bundleIdentifier] : @"";
}

+ (NSString *)parameterForBatteryState {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    UIDeviceBatteryState currentState = [[UIDevice currentDevice] batteryState];
    if (currentState != UIDeviceBatteryStateUnknown) {
        if (currentState == UIDeviceBatteryStateUnplugged) {
            return @"NCHRG";
        } else {
            return @"CHRG";
        }
    }
    return @"UNKNOWN";
}

+ (NSString *)parameterForScreenWidth {
    return [NSString stringWithFormat:@"%1.0f", [[UIScreen mainScreen] bounds].size.width];
}

+ (NSString *)parameterForScreenHeight {
    return [NSString stringWithFormat:@"%1.0f", [[UIScreen mainScreen] bounds].size.height];
}

+ (NSString *)parameterForAvailableTrackers {
    return @"[moat]";
}

+ (NSString *)buildParameters:(NSMutableDictionary *)parameters {
    NSMutableString *parametersString = [[NSMutableString alloc] init];
    [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [parametersString appendFormat:@"%@=%@&", [self escapeString:key], [self escapeString:value]];
    }];
    return  [@"?" stringByAppendingString:[parametersString substringToIndex:[parametersString length]-1]];
}

+ (NSString *)escapeString:(NSString*)string {
    CFStringRef urlString = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                    (CFStringRef)string,
                                                                    NULL,
                                                                    (CFStringRef)@"!*'\"();:@&=+$,/?%#[]% ",
                                                                    kCFStringEncodingUTF8 );
    return (__bridge_transfer NSString *)urlString;
}

+ (NSDictionary *)fetchSSIDInfo {
    NSArray *interfaceNames = CFBridgingRelease(CNCopySupportedInterfaces());
    LoopMeLogDebug(@"%s: Supported interfaces: %@", __func__, interfaceNames);
    
    NSDictionary *SSIDInfo;
    for (NSString *interfaceName in interfaceNames) {
        SSIDInfo = CFBridgingRelease(
                                     CNCopyCurrentNetworkInfo((__bridge CFStringRef)interfaceName));
        LoopMeLogDebug(@"%s: %@ => %@", __func__, interfaceName, SSIDInfo);
        
        BOOL isNotEmpty = (SSIDInfo.count > 0);
        if (isNotEmpty) {
            break;
        }
    }
    return SSIDInfo;
}

@end
