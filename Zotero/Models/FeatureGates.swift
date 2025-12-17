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
    static let speech = FeatureGates(rawValue: 1 << 4)

    static var enabled: FeatureGates {
        var gates: FeatureGates = [.speech]

#if FEATURE_GATE_ALL
        gates.insert(.multipleOpenItems)
        gates.insert(.htmlEpubReader)
        gates.insert(.pdfWorker)
        gates.insert(.downloadFilesAtSync)
        gates.insert(.speech)
#else
#if FEATURE_GATE_HTML_EPUB_READER
        gates.insert(.htmlEpubReader)
#endif

#if FEATURE_GATE_PDF_WORKER
        gates.insert(.pdfWorker)
#endif

#if FEATURE_GATE_MULTIPLE_OPEN_ITEMS
        gates.insert(.multipleOpenItems)
#endif

#if FEATURE_GATE_DOWNLOAD_FILES_AT_SYNC
        gates.insert(.downloadFilesAtSync)
#endif

#if FEATURE_GATE_SPEECH
        gates.insert(.speech)
        gates.insert(.pdfWorker)
#endif
#endif

        return gates
    }
}
