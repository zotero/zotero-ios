//
//  DefaultPageLabel.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 29/4/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift
import CocoaLumberjackSwift

enum DefaultAnnotationPageLabel: Equatable {
    case commonPageOffset(offset: Int)
    case labelPerPage(labelsByPage: [Int: String])

    func label(for page: Int) -> String? {
        switch self {
        case .commonPageOffset(let offset):
            return "\(page + offset)"

        case .labelPerPage(let labelsByPage):
            return labelsByPage[page] ?? "\(page + 1)"
        }
    }

    static func read(attachmentKey: String, libraryId: LibraryIdentifier, dbStorage: DbStorage, queue: DispatchQueue) -> Self {
        do {
            return try dbStorage.perform(request: ReadDefaultAnnotationPageLabelDbRequest(attachmentKey: attachmentKey, libraryId: libraryId), on: queue)
        } catch {
            DDLogError("DefaultAnnotationPageLabel: failed to read default annotation page label - \(error)")
            return .commonPageOffset(offset: 1)
        }
    }

    static func from(databaseAnnotations: Results<RItem>) -> Self {
        var uniquePageLabelsCountByPage: [Int: [String: Int]] = [:]
        for item in databaseAnnotations {
            guard let annotation = PDFDatabaseAnnotation(item: item), let page = annotation._page, let pageLabel = annotation._pageLabel, !pageLabel.isEmpty, pageLabel != "-" else { continue }
            var uniquePageLabelsCount = uniquePageLabelsCountByPage[page, default: [:]]
            uniquePageLabelsCount[pageLabel, default: 0] += 1
            uniquePageLabelsCountByPage[page] = uniquePageLabelsCount
        }
        var defaultPageLabelByPage: [Int: String] = [:]
        for (page, uniquePageLabelsCount) in uniquePageLabelsCountByPage {
            if let maxCount = uniquePageLabelsCount.values.max(), let defaultPageLabel = uniquePageLabelsCount.filter({ $0.value == maxCount }).keys.sorted().first {
                defaultPageLabelByPage[page] = defaultPageLabel
            }
        }
        let uniquePageOffsets = Set(defaultPageLabelByPage.map({ (page, pageLabel) in Int(pageLabel).flatMap({ $0 - page }) }))
        if uniquePageOffsets.count == 1, let uniquePageOffset = uniquePageOffsets.first, let commonPageOffset = uniquePageOffset {
            return .commonPageOffset(offset: commonPageOffset)
        }
        if !defaultPageLabelByPage.isEmpty {
            return .labelPerPage(labelsByPage: defaultPageLabelByPage)
        }
        return .commonPageOffset(offset: 1)
    }
}
