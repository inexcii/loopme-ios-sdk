//
//  LoopMeServerURLBuilder.h
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 07/11/13.
//  Copyright (c) 2013 LoopMe. All rights reserved.
//

#import <CoreGraphics/CoreGraphics.h>
@class LoopMeTargeting;

@interface LoopMeServerURLBuilder : NSObject

+ (NSURL *)URLWithAppKey:(NSString *)appKey targeting:(LoopMeTargeting *)targeting
         integrationType:(NSString *)integrationType adSpotSize:(CGSize)size;
+ (NSURL *)URLWithAppKey:(NSString *)appKey targeting:(LoopMeTargeting *)targeting
                 baseURL:(NSURL *)baseURL integrationType:(NSString *)integrationType adSpotSize:(CGSize)size;

+ (NSString *)packageIDs;

+ (NSString *)parameterForBundleIdentifier;
+ (NSString *)parameterForUniqueIdentifier;

@end
