//
//  CreatorSummaryFormatter.swift
//  Zotero
//
//  Created by Michal Rentka on 06/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreatorSummaryFormatter {
    static func summary(for creators: Results<RCreator>) -> String? {
        switch creators.count {
        case 0:
            return nil
        case 1:
            return creators.first?.summaryName ?? ""
        case 2:
            let sorted = creators.sorted(byKeyPath: "orderId")
            return "\(sorted.first?.summaryName ?? "") and \(sorted.last?.summaryName ?? "")"
        default:
            let first = creators.sorted(byKeyPath: "orderId").first?.summaryName ?? ""
            return "\(first) et al."
        }
    }
}
