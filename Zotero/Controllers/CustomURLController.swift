//
//  CustomURLController.swift
//  Zotero
//
//  Created by Michal Rentka on 30.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

enum CustomURLAction: String {
    case select = "select"
    case openPdf = "open-pdf"
}

final class CustomURLController {
    private let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(url: URL, coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "zotero", let action = components.host.flatMap({ CustomURLAction(rawValue: $0) }) else { return }

        switch action {
        case .select:
            self.select(path: components.path, coordinatorDelegate: coordinatorDelegate, animated: animated)

        case .openPdf:
            self.openPdf(path: components.path, queryItems: components.queryItems ?? [], coordinatorDelegate: coordinatorDelegate, animated: animated)
        }
    }

    private func select(path: String, coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        let parts = path.components(separatedBy: "/")

        guard parts.count > 2 else {
            DDLogError("CustomURLController: path invalid - \(path)")
            return
        }

        switch parts[1] {
        case "library":
            guard parts.count == 4, parts[2] == "items" else {
                DDLogError("CustomURLController: path invalid for user library - \(path)")
                return
            }
            self.showItemIfPossible(key: parts[3], libraryId: .custom(.myLibrary), coordinatorDelegate: coordinatorDelegate, animated: animated)

        case "groups":
            guard parts.count == 5, parts[3] == "items", let groupId = Int(parts[2]) else {
                DDLogError("CustomURLController: path invalid for group - \(path)")
                return
            }
            self.showItemIfPossible(key: parts[4], libraryId: .group(groupId), coordinatorDelegate: coordinatorDelegate, animated: animated)

        default: break
        }
    }

    private func showItemIfPossible(key: String, libraryId: LibraryIdentifier, coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        do {
            let library = try self.dbStorage.perform(request: ReadLibraryDbRequest(libraryId: libraryId), on: .main)
            let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: .main)

            var baseItem = item
            while let parent = baseItem.parent {
                baseItem = parent
            }

            coordinatorDelegate.showItem(key: baseItem.key, library: library, animated: animated)
        } catch let error {
            DDLogError("CustomURLConverter: library (\(libraryId)) or item (\(key)) not found - \(error)")
        }
    }

    private func openPdf(path: String, queryItems: [URLQueryItem], coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        let parts = path.components(separatedBy: "/")

        guard parts.count > 2 else {
            DDLogError("CustomURLController: path invalid - \(path)")
            return
        }

        switch parts[1] {
        case "library":
            guard parts.count == 4, parts[2] == "items", let queryItem = queryItems.first, queryItem.name == "page", let page = queryItem.value.flatMap(Int.init) else {
                DDLogError("CustomURLController: path invalid for user library - \(path)")
                return
            }
            self.openPdfIfPossible(on: page, key: parts[3], libraryId: .custom(.myLibrary), coordinatorDelegate: coordinatorDelegate, animated: animated)

        case "groups":
            guard parts.count == 5, parts[3] == "items", let groupId = Int(parts[2]), let queryItem = queryItems.first, queryItem.name == "page", let page = queryItem.value.flatMap(Int.init) else {
                DDLogError("CustomURLController: path invalid for group - \(path)")
                return
            }
            self.openPdfIfPossible(on: page, key: parts[4], libraryId: .group(groupId), coordinatorDelegate: coordinatorDelegate, animated: animated)

        default:
            guard parts.count == 3 else {
                DDLogError("CustomURLController: path invalid for ZotFile format - \(path)")
                return
            }
            let libraryParts = parts[1].components(separatedBy: "_")
            guard let page = Int(parts[2]) else {
                DDLogError("CustomURLController: page missing in ZotFile format - \(path)")
                return
            }
        }
    }

    private func openPdfIfPossible(on page: Int, key: String, libraryId: LibraryIdentifier, coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        do {
            let library = try self.dbStorage.perform(request: ReadLibraryDbRequest(libraryId: libraryId), on: .main)
            let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: .main)

            guard item.rawType == ItemTypes.attachment else {
                DDLogInfo("CustomURLConverter: trying to open item type \(item.rawType) instead of pdf")
                return
            }

            let contentType = AttachmentCreator.contentType(for: item) ?? ""
            guard contentType == "application/pdf" else {
                DDLogInfo("CustomURLConverter: trying to open attachment \(contentType) instead of pdf")
                return
            }

            coordinatorDelegate.openPdf(on: page, key: key, parentKey: item.parent?.key, libraryId: libraryId, animated: true)
        } catch let error {
            DDLogError("CustomURLConverter: library (\(libraryId)) or item (\(key)) not found - \(error)")
        }
    }
}
