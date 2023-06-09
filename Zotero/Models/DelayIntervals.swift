//
//  DelayIntervals.swift
//  Zotero
//
//  Created by Michal Rentka on 11/06/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DelayIntervals {
    static let sync: [Double] = createSyncIntervals()
    static let retry: [Int] = [0, 10000, 20000, 40000, 60000, 120000, 240000, 300000]

    private static func createSyncIntervals() -> [Double] {
        let hourIntervals = [0.5, 1, 4, 16, 16, 16, 16, 16, 16, 16, 64]
        return hourIntervals.map({ $0 * 60 * 60 })
    }
}
