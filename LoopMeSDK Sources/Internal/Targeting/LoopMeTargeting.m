//
//  LoopMeTargeting.m
//  LoopMeSDK
//
//  Created by Bohdan Korda on 10/14/14.
//  Copyright (c) 2014 LoopMe. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>

#import "LoopMeTargeting.h"

@implementation LoopMeTargeting

#pragma mark - Initialiation

- (instancetype)init {
    return [self initWithKeywords:nil yearOfBirth:nil gender:LoopMeGenderUnknown];
}

- (instancetype)initWithGender:(LoopMeGender)gender {
    return [self initWithKeywords:nil yearOfBirth:nil gender:gender];
}

- (instancetype)initWithKeywords:(NSString *)keywords {
    return [self initWithKeywords:keywords yearOfBirth:nil gender:LoopMeGenderUnknown];
}

- (instancetype)initWithYearOfBirth:(NSNumber *)yearOfBirth {
    return [self initWithKeywords:nil yearOfBirth:yearOfBirth gender:LoopMeGenderUnknown];
}

- (instancetype)initWithKeywords:(NSString *)keywords
           yearOfBirth:(NSNumber *)yob
                gender:(LoopMeGender)gender {
    self = [super init];
    if (self) {
        _keywords = keywords;
        _yearOfBirth = yob;
        _gender = gender;
    }
    return self;
}

#pragma mark - Parameters

- (NSString *)genderParameter {
    NSString *resultGenderParametr;
    switch (self.gender) {
        case LoopMeGenderMale:
            resultGenderParametr = @"M";
            break;
        case LoopMeGenderFemale:
            resultGenderParametr = @"F";
            break;
        default:
            break;
    }
    return resultGenderParametr;
}

- (NSString *)yearOfBirthParameter {
    return [self.yearOfBirth stringValue];
}

- (NSString *)keywordsParameter {
    NSString *trimmedKeywords = [self.keywords stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceCharacterSet]];
    
    return (trimmedKeywords.length > 0) ? trimmedKeywords : nil;
}

@end
