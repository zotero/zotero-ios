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
    static let documentWorker = FeatureGates(rawValue: 1 << 1)
    static let downloadFilesAtSync = FeatureGates(rawValue: 1 << 2)
    static let speech = FeatureGates(rawValue: 1 << 3)

    static var enabled: FeatureGates {
        var gates: FeatureGates = [.speech]

#if FEATURE_GATE_ALL
        gates.insert(.multipleOpenItems)
        gates.insert(.documentWorker)
        gates.insert(.downloadFilesAtSync)
        gates.insert(.speech)
#else
#if FEATURE_GATE_DOCUMENT_WORKER
        gates.insert(.documentWorker)
#endif

#if FEATURE_GATE_MULTIPLE_OPEN_ITEMS
        gates.insert(.multipleOpenItems)
#endif

#if FEATURE_GATE_DOWNLOAD_FILES_AT_SYNC
        gates.insert(.downloadFilesAtSync)
#endif

#if FEATURE_GATE_SPEECH
        gates.insert(.speech)
        gates.insert(.documentWorker)
#endif
#endif

        return gates
    }
}
