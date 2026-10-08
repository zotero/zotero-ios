//
//  DefaultAnnotationPageLabel.swift
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
}
