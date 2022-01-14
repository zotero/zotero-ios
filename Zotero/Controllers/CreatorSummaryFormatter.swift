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
    static func summary(for allCreators: List<RCreator>) -> String? {
        let primary = allCreators.filter("primary = true")
        if !primary.isEmpty {
            return self.summary(for: primary)
        }

        let editors = allCreators.filter("rawType = %@", CreatorTypes.editor)
        if !editors.isEmpty {
            return self.summary(for: editors)
        }

        let contributors = allCreators.filter("rawType = %@", CreatorTypes.contributor)
        if !contributors.isEmpty {
            return self.summary(for: contributors)
        }

        return nil
    }

    private static func summary(for creators: Results<RCreator>) -> String? {
        switch creators.count {
        case 0:
            return nil
        case 1:
            return creators.first?.summaryName
        case 2:
            let sorted = creators.sorted(byKeyPath: "orderId")
            return L10n.Items.CreatorSummary.and(sorted.first!.summaryName, sorted.last!.summaryName)
        default:
            let sorted = creators.sorted(byKeyPath: "orderId")
            return L10n.Items.CreatorSummary.etal(sorted.first!.summaryName)
        }
    }
}
