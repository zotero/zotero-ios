//
//  BaseItemsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 23.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

class BaseItemsActionHandler: BackgroundDbProcessingActionHandler {
    unowned let dbStorage: DbStorage
    let backgroundQueue: DispatchQueue
    private let quotationExpression: NSRegularExpression?

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.backgroundQueue = DispatchQueue(label: "org.zotero.BaseItemsActionHandler.backgroundProcessing", qos: .userInitiated)

        do {
            quotationExpression = try NSRegularExpression(pattern: #"("[^"]+"?)"#)
        } catch let error {
            DDLogError("BaseItemsActionHandler: can't create quotation expression - \(error)")
            quotationExpression = nil
        }
    }

    // MARK: - Filtering

    func add(filter: ItemsFilter, to filters: [ItemsFilter]) -> [ItemsFilter] {
        guard !filters.contains(filter) else { return filters }

        let modificationIndex = filters.firstIndex(where: { existing in
            switch (existing, filter) {
            // Update array inside existing `tags` filter
            case (.tags, .tags):
                return true

            default:
                return false
            }
        })

        var newFilters = filters
        if let index = modificationIndex {
            newFilters[index] = filter
        } else {
            newFilters.append(filter)
        }
        return newFilters
    }

    func remove(filter: ItemsFilter, from filters: [ItemsFilter]) -> [ItemsFilter] {
        guard let index = filters.firstIndex(of: filter) else { return filters }
        var newFilters = filters
        newFilters.remove(at: index)
        return newFilters
    }

    // MARK: - Search

    func createComponents(from searchTerm: String) -> [String] {
        guard let expression = quotationExpression else { return [searchTerm] }

        let normalizedSearchTerm = searchTerm.replacingOccurrences(of: #"“"#, with: "\"")
                                             .replacingOccurrences(of: #"”"#, with: "\"")

        let matches = expression.matches(in: normalizedSearchTerm, options: [], range: NSRange(normalizedSearchTerm.startIndex..., in: normalizedSearchTerm))

        guard !matches.isEmpty else {
            return separateComponents(from: normalizedSearchTerm)
        }

        var components: [String] = []
        var previousMatchEnd = normalizedSearchTerm.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: normalizedSearchTerm) else { continue }

            if matchRange.lowerBound > previousMatchEnd {
                let precedingComponents = separateComponents(from: String(normalizedSearchTerm[previousMatchEnd..<matchRange.lowerBound]))
                components.append(contentsOf: precedingComponents)
            }

            // Strip the opening quote, and the closing quote if present
            var innerStart = normalizedSearchTerm.index(after: matchRange.lowerBound)
            let innerEnd = normalizedSearchTerm[normalizedSearchTerm.index(before: matchRange.upperBound)] == "\"" ? normalizedSearchTerm.index(before: matchRange.upperBound) : matchRange.upperBound
            if innerStart > innerEnd { innerStart = innerEnd }
            components.append(String(normalizedSearchTerm[innerStart..<innerEnd]))

            previousMatchEnd = matchRange.upperBound
        }

        if previousMatchEnd < normalizedSearchTerm.endIndex {
            let lastComponents = separateComponents(from: String(normalizedSearchTerm[previousMatchEnd..<normalizedSearchTerm.endIndex]))
            components.append(contentsOf: lastComponents)
        }

        return components

        func separateComponents(from string: String) -> [String] {
            return string.components(separatedBy: " ").filter({ !$0.isEmpty })
        }
    }

    // MARK: - Drag & Drop

    func tagItem(key: String, libraryId: LibraryIdentifier, with names: Set<String>) {
        let request = AddTagsToItemDbRequest(key: key, libraryId: libraryId, tagNames: names)
        perform(request: request) { error in
            guard let error = error else { return }
            // TODO: - show error
            DDLogError("BaseItemsActionHandler: can't add tags - \(error)")
        }
    }
}
