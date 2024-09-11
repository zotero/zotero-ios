//
//  NSDecimalNumber+Rounding.h
//  Zotero
//
//  Created by Miltiadis Vasilakis on 11/9/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSDecimalNumber (Rounding)

+ (NSDecimal)roundedDecimal:(NSDecimal)decimal toPlaces:(NSInteger)places mode:(NSRoundingMode)mode;

@end
