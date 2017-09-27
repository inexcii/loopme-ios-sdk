//
//  NSURL+LoopMeAdditions.m
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 11/11/13.
//  Copyright (c) 2013 LoopMe. All rights reserved.
//

#import "NSURL+LoopMeAdditions.h"
#import "NSString+Encryption.h"

@implementation NSURL (LoopMeAdditions)

- (NSDictionary *)lm_toDictionary {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSArray *elements = [self.query componentsSeparatedByString:@"&"];
    for (NSString *element in elements) {
        NSArray *keyVal = [element componentsSeparatedByString:@"="];
        if (keyVal.count >= 2) {
            NSString *key = keyVal[0];
            NSString *value = keyVal[1];
            dictionary[key] = [value lm_stringByRemovingPercentEncoding];
        }
    }
    return dictionary;
}

@end
