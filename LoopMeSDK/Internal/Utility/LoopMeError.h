//
//  LoopMeError.h
//  LoopMeSDK
//
//  Created by Kogda Bogdan on 2/18/15.
//
//

#import <Foundation/Foundation.h>

#define kLoopMeErrorDomain @"loopme.me"

@interface LoopMeError : NSObject

+ (NSError *)errorForStatusCode:(NSInteger)statusCode;

@end

typedef NS_ENUM(NSUInteger, LoopMeErrorCode) {
    LoopMeErrorCodeIncorrectResponse = -10,
    LoopMeErrorCodeIncorrectFormat = -11,
    LoopMeErrorCodeSpecificHost = -12,
    LoopMeErrorCodeHTMLRequestTimeOut = -13,
    LoopMeErrorCodeURLResolve = -20,
    LoopMeErrorCodeWrirtingToDisk = -21
};