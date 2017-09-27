//
//  LoopMeAdConfiguration.m
//  LoopMe
//
//  Created by Dmitriy Lihachov on 07/11/13.
//  Copyright (c) 2013 LoopMe. All rights reserved.

#import "LoopMeGlobalSettings.h"
#import "LoopMeAdConfiguration.h"
#import "LoopMeLogging.h"
#import "LoopMeGlobalSettings.h"
#import "NSString+Encryption.h"
#import "LoopMeDefinitions.h"

const int kLoopMeExpireTimeIntervalMinimum = 600;

// Events
const struct LoopMeTrackerNameStruct LoopMeTrackerName = {
    .moat = @"moat"
};

@interface LoopMeAdConfiguration ()

@property (nonatomic) NSArray *measurePartners;

@end

@implementation LoopMeAdConfiguration

#pragma mark - Life Cycle

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        NSError *error = nil;
        NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data
                                                                           options:kNilOptions
                                                                             error:&error];
        if (error) {
            LoopMeLogError(@"Failed to parse ad response, error: %@", error);
            return nil;
        }
        
        _adResponseHTMLString = responseDictionary[@"script"];
        [self mapAdConfigurationFromDictionary:responseDictionary];
    }
    return self;
}

- (NSDictionary *)adIdsForMOAT {
    if (!_adIdsForMOAT) {
        NSScanner *scanner = [NSScanner scannerWithString:_adResponseHTMLString];
        NSString *lmCampaignsString;
        while ([scanner isAtEnd] == NO) {
            [scanner scanUpToString:@"<script>" intoString:NULL] ;
            [scanner scanUpToString:@"</script>" intoString:&lmCampaignsString];
            lmCampaignsString = [lmCampaignsString stringByReplacingOccurrencesOfString:@"<script>" withString:@""];
            if ([lmCampaignsString rangeOfString:@"lmCampaigns"].length > 0) {
                break;
            }
        }
        
        NSRange rangeOfBrace = [lmCampaignsString rangeOfString:@"{"];
        lmCampaignsString = [lmCampaignsString substringFromIndex:rangeOfBrace.location];

        NSDictionary *jsonMacroses = [NSJSONSerialization JSONObjectWithData:[lmCampaignsString dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:nil];
        jsonMacroses = [jsonMacroses objectForKey:@"macros"];
        
        _adIdsForMOAT = [NSDictionary dictionaryWithObjectsAndKeys:[[jsonMacroses objectForKey:kLoopMeAdvertiser] stringByRemovingPercentEncoding], @"level1", [[jsonMacroses objectForKey:kLoopMeCampaign] stringByRemovingPercentEncoding], @"level2", [[jsonMacroses objectForKey:kLoopMeLineItem] stringByRemovingPercentEncoding], @"level3", [[jsonMacroses objectForKey:kLoopMeCreative] stringByRemovingPercentEncoding], @"level4", [[jsonMacroses objectForKey:kLoopMeAPP] stringByRemovingPercentEncoding], @"slicer1", @"", @"slicer2",  nil];
        
    }
    return _adIdsForMOAT;
}

#pragma mark - Private

- (void)mapAdConfigurationFromDictionary:(NSDictionary *)dictionary {
    NSDictionary *settings = dictionary[@"settings"];
    
    if ([settings[@"format"] isEqualToString:@"banner"]) {
        _format = LoopMeAdFormatBanner;
    } else if ([settings[@"format"] isEqualToString:@"interstitial"]) {
        _format = LoopMeAdFormatInterstitial;
    }
    
    self.mraid = [[settings objectForKey:@"mraid"] boolValue];
    
    [[LoopMeGlobalSettings sharedInstance] setPreload25:[[settings objectForKey:@"preload25"] boolValue]];
    self.v360 = [[settings objectForKey:@"v360"] boolValue];
    
    _expirationTime = [settings[@"ad_expiry_time"] integerValue];
    if (_expirationTime < kLoopMeExpireTimeIntervalMinimum) {
        _expirationTime = kLoopMeExpireTimeIntervalMinimum;
    }
    
    if ([settings objectForKey:@"debug"]) {
        [LoopMeGlobalSettings sharedInstance].liveDebugEnabled = [settings[@"debug"] boolValue];
    }
    
    BOOL autoLoading = YES;
    if ([settings objectForKey:@"autoloading"]) {
        autoLoading = [[settings objectForKey:@"autoloading"] boolValue];
    }
    [[NSUserDefaults standardUserDefaults] setBool:autoLoading forKey:LOOPME_USERDEFAULTS_KEY_AUTOLOADING];
    
    self.measurePartners = [settings objectForKey:@"measure_partners"];
    
    if ([settings[@"orientation"] isEqualToString:@"landscape"]) {
        _orientation = LoopMeAdOrientationLandscape;
    } else if ([settings[@"orientation"] isEqualToString:@"portrait"]) {
        _orientation = LoopMeAdOrientationPortrait;
    } else {
        _orientation = LoopMeAdOrientationUndefined;
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Ad format: %@, orientation: %@, expires in: %ld seconds",
                   (self.format == LoopMeAdFormatBanner) ? @"banner" : @"interstitial",
                   (self.orientation == LoopMeAdOrientationPortrait) ? @"portrait" : @"landscape",
                   (long)self.expirationTime];

}

- (BOOL)useTracking:(NSString *)trakerName {
    return [self.measurePartners containsObject:trakerName];
}

- (BOOL)isAutoLoading {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"autoloading"];
}

@end
