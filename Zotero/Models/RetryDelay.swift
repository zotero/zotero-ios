//
//  RetryDelay.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 14/5/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum RetryDelay {
    case constant(TimeInterval)
    case progressive(initial: TimeInterval = 2.5, multiplier: Double = 2, maxDelay: TimeInterval = 3600)

    func seconds(for attempt: Int) -> TimeInterval {
        switch self {
        case .constant(let time):
            return time

        case .progressive(let initial, let multiplier, let maxDelay):
            let delay = attempt == 1 ? initial : (initial * pow(multiplier, Double(attempt - 1)))
            return min(maxDelay, delay)
        }
    }

    static let maxAttemptsCount: Int = 10
}
