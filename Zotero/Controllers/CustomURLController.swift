//
//  CustomURLController.swift
//  Zotero
//
//  Created by Michal Rentka on 30.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

enum CustomURLAction: String {
    case select = "select"
    case openPdf = "open-pdf"
}

final class CustomURLController {
    enum Kind {
        case itemDetail(key: String, library: Library, preselectedChildKey: String?)
        case pdfReader(attachment: Attachment, library: Library, page: Int, parentKey: String?, isAvailable: Bool)
    }

    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage

    init(dbStorage: DbStorage, fileStorage: FileStorage) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
    }

    func process(url: URL) -> Kind? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "zotero", let action = components.host.flatMap({ CustomURLAction(rawValue: $0) }) else { return nil }

        switch action {
        case .select:
            return self.select(path: components.path)

        case .openPdf:
            return self.openPdf(path: components.path, queryItems: components.queryItems ?? [])
        }
    }

    private func select(path: String) -> Kind? {
        let parts = path.components(separatedBy: "/")

        guard parts.count > 2 else {
            DDLogError("CustomURLController: path invalid - \(path)")
            return nil
        }

        switch parts[1] {
        case "library":
            guard parts.count == 4, parts[2] == "items" else {
                DDLogError("CustomURLController: path invalid for user library - \(path)")
                return nil
            }
            return self.loadSelectKind(key: parts[3], libraryId: .custom(.myLibrary))

        case "groups":
            guard parts.count == 5, parts[3] == "items", let groupId = Int(parts[2]) else {
                DDLogError("CustomURLController: path invalid for group - \(path)")
                return nil
            }
            return self.loadSelectKind(key: parts[4], libraryId: .group(groupId))

        default:
            DDLogError("CustomURLController: incorrect library part - \(parts[1])")
            return nil
        }
    }

    private func loadSelectKind(key: String, libraryId: LibraryIdentifier) -> Kind? {
        do {
            let library = try self.dbStorage.perform(request: ReadLibraryDbRequest(libraryId: libraryId), on: .main)
            let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: .main)
            return .itemDetail(key: (item.parent?.key ?? item.key), library: library, preselectedChildKey: item.key)
        } catch let error {
            DDLogError("CustomURLConverter: library (\(libraryId)) or item (\(key)) not found - \(error)")
            return nil
        }
    }

    private func openPdf(path: String, queryItems: [URLQueryItem]) -> Kind? {
        let parts = path.components(separatedBy: "/")

        guard parts.count > 2 else {
            DDLogError("CustomURLController: path invalid - \(path)")
            return nil
        }

        switch parts[1] {
        case "library":
            guard parts.count == 4, parts[2] == "items", let queryItem = queryItems.first, queryItem.name == "page", let page = queryItem.value.flatMap(Int.init) else {
                DDLogError("CustomURLController: path invalid for user library - \(path)")
                return nil
            }
            return self.loadPdfKind(on: page, key: parts[3], libraryId: .custom(.myLibrary))

        case "groups":
            guard parts.count == 5, parts[3] == "items", let groupId = Int(parts[2]), let queryItem = queryItems.first, queryItem.name == "page", let page = queryItem.value.flatMap(Int.init) else {
                DDLogError("CustomURLController: path invalid for group - \(path)")
                return nil
            }
            return self.loadPdfKind(on: page, key: parts[4], libraryId: .group(groupId))

        default:
            guard parts.count == 3 else {
                DDLogError("CustomURLController: path invalid for ZotFile format - \(path)")
                return nil
            }
            let zotfileParts = parts[1].components(separatedBy: "_")
            guard zotfileParts.count == 2, let groupId = Int(zotfileParts[0]) else {
                DDLogError("CustomURLController: wrong library format in ZotFile format - \(path)")
                return nil
            }
            guard let page = Int(parts[2]) else {
                DDLogError("CustomURLController: page missing in ZotFile format - \(path)")
                return nil
            }

            let libraryId: LibraryIdentifier = groupId == 0 ? .custom(.myLibrary) : .group(groupId)
            return self.loadPdfKind(on: page, key: zotfileParts[1], libraryId: libraryId)
        }
    }

    private func loadPdfKind(on page: Int, key: String, libraryId: LibraryIdentifier) -> Kind? {
        do {
            let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: .main)

            guard let attachment = AttachmentCreator.attachment(for: item, fileStorage: self.fileStorage, urlDetector: nil) else {
                DDLogInfo("CustomURLConverter: trying to open incorrect item - \(item.rawType)")
                return nil
            }

            guard case .file(_, let contentType, let location, _) = attachment.type, contentType == "application/pdf" else {
                DDLogInfo("CustomURLConverter: trying to open \(attachment.type) instead of pdf")
                return nil
            }

            let library = try self.dbStorage.perform(request: ReadLibraryDbRequest(libraryId: libraryId), on: .main)
            let parentKey = item.parent?.key

            switch location {
            case .local:
                return .pdfReader(attachment: attachment, library: library, page: page, parentKey: parentKey, isAvailable: true)

            case .remote, .localAndChangedRemotely:
                return .pdfReader(attachment: attachment, library: library, page: page, parentKey: parentKey, isAvailable: false)

            case .remoteMissing:
                DDLogInfo("CustomURLConverter: attachment \(attachment.key) missing remotely")
                return nil
            }
        } catch let error {
            DDLogError("CustomURLConverter: library (\(libraryId)) or item (\(key)) not found - \(error)")
            return nil
        }
    }
}
