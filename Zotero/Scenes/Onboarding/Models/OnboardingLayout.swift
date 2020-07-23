//
//  OnboardingLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 20/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum OnboardingLayout {
    case big
    case medium
    case small

    static func from(size: CGSize) -> Self {
        let size = min(size.width, size.height)
        if size >= 834 {
            return .big
        } else if size >= 768 {
            return .medium
        }
        return .small
    }
}
