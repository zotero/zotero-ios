//
//  FeatureGates.swift
//  Zotero
//
//  Created by Michal Rentka on 10.03.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct FeatureGates: OptionSet {
    typealias RawValue = Int8

    let rawValue: Int8

    static let multipleOpenItems = FeatureGates(rawValue: 1 << 0)
    static let pdfWorker = FeatureGates(rawValue: 1 << 1)
    static let htmlEpubReader = FeatureGates(rawValue: 1 << 2)
    static let downloadFilesAtSync = FeatureGates(rawValue: 1 << 3)

    static let enabled: FeatureGates = [.htmlEpubReader, .pdfWorker]
}
