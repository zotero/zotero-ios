//
//  ItemsFilter.swift
//  Zotero
//
//  Created by Michal Rentka on 13.04.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemsFilter: Equatable {
    case downloadedFiles
    case tags(Set<String>)

    var tags: Set<String>? {
        switch self {
        case .tags(let tags):
            return tags

        case .downloadedFiles:
            return nil
        }
    }

    var isDownloadedFilesFilter: Bool {
        switch self {
        case .tags:
            return false

        case .downloadedFiles:
            return true
        }
    }

    static func == (lhs: ItemsFilter, rhs: ItemsFilter) -> Bool {
        switch (lhs, rhs) {
        case (.downloadedFiles, .downloadedFiles):
            return true

        case (.tags(let lTags), .tags(let rTags)):
            return lTags == rTags

        default:
            return false
        }
    }
}
