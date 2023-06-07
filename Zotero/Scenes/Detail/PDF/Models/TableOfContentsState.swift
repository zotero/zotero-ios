//
//  TableOfContentsState.swift
//  Zotero
//
//  Created by Michal Rentka on 20.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

struct TableOfContentsState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt16

        let rawValue: UInt16

        static let snapshot = Changes(rawValue: 1 << 0)
    }

    struct Outline: Hashable {
        let id: UUID
        let title: String
        let page: UInt
        let isActive: Bool

        init(element: OutlineElement, isActive: Bool) {
            self.id = UUID()
            self.title = element.title ?? ""
            self.page = element.pageIndex
            self.isActive = isActive
        }
    }

    let document: Document

    var search: String
    var changes: Changes
    var outlineSnapshot: NSDiffableDataSourceSectionSnapshot<TableOfContentsViewController.Row>?

    init(document: Document) {
        self.document = document
        self.search = ""
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
