//
//  NSDecimalNumber+Rounding.m
//  Zotero
//
//  Created by Miltiadis Vasilakis on 11/9/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

#import "NSDecimalNumber+Rounding.h"

@implementation NSDecimalNumber (Rounding)

+ (NSDecimal)roundedDecimal:(NSDecimal)decimal toPlaces:(NSInteger)places mode:(NSRoundingMode)mode {
    NSDecimal result = decimal;
    NSDecimalRound(&result, &decimal, places, mode);
    return result;
}

@end
