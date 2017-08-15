//
//  LoopMeAdConfiguration.h
//  LoopMe
//
//  Created by Dmitriy Lihachov on 07/11/13.
//  Copyright (c) 2013 LoopMe. All rights reserved.

#import <UIKit/UIKit.h>

typedef NS_ENUM (NSInteger, LoopMeAdOrientation) {
    LoopMeAdOrientationUndefined,
    LoopMeAdOrientationPortrait,
    LoopMeAdOrientationLandscape
};

typedef NS_ENUM (NSInteger, LoopMeAdFormat) {
    LoopMeAdFormatInterstitial,
    LoopMeAdFormatBanner
};

struct LoopMeMRAIDExpandProperties {
    int width;
    int height;
    BOOL useCustomClose;
};

extern const struct LoopMeTrackerNameStruct {
    __unsafe_unretained NSString *moat;
} LoopMeTrackerName;

@interface LoopMeAdConfiguration : NSObject

- (instancetype)initWithData:(NSData *)data;
- (BOOL)useTracking:(NSString *)trakerName;

@property (nonatomic, assign) BOOL allowOrientationChange;
@property (nonatomic, assign) LoopMeAdFormat format;
@property (nonatomic, assign) LoopMeAdOrientation orientation;
@property (nonatomic, assign) struct LoopMeMRAIDExpandProperties expandProperties;
@property (nonatomic, assign, getter=isMraid) BOOL mraid;
@property (nonatomic, strong) NSDictionary *adIdsForMOAT;
@property (nonatomic, assign) NSInteger expirationTime;
@property (nonatomic, strong) NSString *adResponseHTMLString;

@end
