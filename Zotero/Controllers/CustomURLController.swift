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

final class CustomURLController {
    enum CustomURLAction: String {
        case select = "select"
        case openItem = "open-pdf"
    }

    enum Kind {
        case itemDetail(key: String, libraryId: LibraryIdentifier, preselectedChildKey: String?)
        case itemReader(presentation: ItemPresentation, attachment: Attachment, isAvailable: Bool)
    }

    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage

    init(dbStorage: DbStorage, fileStorage: FileStorage) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
    }

    func process(url: URL) -> Kind? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "zotero",
              let action = components.host.flatMap({ CustomURLAction(rawValue: $0) })
        else { return nil }

        switch action {
        case .select:
            return select(path: components.path)

        case .openItem:
            return openItem(path: components.path, queryItems: components.queryItems ?? [])
        }

        func select(path: String) -> Kind? {
            guard let (key, libraryId, _, _) = extractProperties(from: path, and: []) else { return nil }
            return loadSelectKind(key: key, libraryId: libraryId)

            func loadSelectKind(key: String, libraryId: LibraryIdentifier) -> Kind? {
                do {
                    let item = try dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: .main)
                    return .itemDetail(key: (item.parent?.key ?? item.key), libraryId: libraryId, preselectedChildKey: item.key)
                } catch let error {
                    DDLogError("CustomURLConverter: library (\(libraryId)) or item (\(key)) not found - \(error)")
                    return nil
                }
            }
        }

        func openItem(path: String, queryItems: [URLQueryItem]) -> Kind? {
            guard let (key, libraryId, page, annotation) = extractProperties(from: path, and: queryItems, extractPageAndAnnotation: true, allowZotFileFormat: true) else { return nil }
            return loadItemReaderKind(on: page, annotation: annotation, key: key, libraryId: libraryId)

            func loadItemReaderKind(on page: Int?, annotation: String?, key: String, libraryId: LibraryIdentifier) -> Kind? {
                var library: Library?
                var item: RItem?
                do {
                    try dbStorage.perform(on: .main) { coordinator in
                        library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))
                        item = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
                    }
                } catch let error {
                    DDLogError("CustomURLConverter: library (\(libraryId)) or item (\(key)) not found - \(error)")
                    return nil
                }
                guard let library, let item else { return nil }
                guard let attachment = AttachmentCreator.attachment(for: item, fileStorage: fileStorage, urlDetector: nil) else {
                    DDLogInfo("CustomURLConverter: trying to open incorrect item - \(item.rawType)")
                    return nil
                }
                guard case .file(let filename, let contentType, let location, _, _) = attachment.type else {
                    DDLogInfo("CustomURLConverter: trying to open invalid attachment type \(attachment.type)")
                    return nil
                }
                let parentKey = item.parent?.key
                let file = Files.attachmentFile(in: libraryId, key: attachment.key, filename: filename, contentType: contentType)
                let url = file.createUrl()
                var presentation: ItemPresentation?
                switch contentType {
                case "application/pdf":
                    presentation = .pdf(library: library, key: key, parentKey: parentKey, url: url, page: page, preselectedAnnotationKey: annotation, previewRects: nil)

                case "text/html":
                    if FeatureGates.enabled.contains(.htmlEpubReader) {
                        presentation = .html(library: library, key: key, parentKey: parentKey, url: url, preselectedAnnotationKey: annotation)
                    }

                case "application/epub+zip":
                    if FeatureGates.enabled.contains(.htmlEpubReader) {
                        presentation = .epub(library: library, key: key, parentKey: parentKey, url: url, preselectedAnnotationKey: annotation)
                    }

                default:
                    break
                }
                guard let presentation else {
                    DDLogInfo("CustomURLConverter: trying to open invalid content type \(contentType)")
                    return nil
                }
                switch location {
                case .local:
                    return .itemReader(presentation: presentation, attachment: attachment, isAvailable: true)

                case .remote, .localAndChangedRemotely:
                    return .itemReader(presentation: presentation, attachment: attachment, isAvailable: false)

                case .remoteMissing:
                    DDLogInfo("CustomURLConverter: attachment \(attachment.key) missing remotely")
                    return nil
                }
            }
        }

        func extractProperties(
            from path: String,
            and queryItems: [URLQueryItem],
            extractPageAndAnnotation: Bool = false,
            allowZotFileFormat: Bool = false
        ) -> (String, LibraryIdentifier, Int?, String?)? {
            let parts = path.components(separatedBy: "/")
            guard parts.count > 2 else {
                DDLogError("CustomURLController: path invalid - \(path)")
                return nil
            }

            let key: String
            let libraryId: LibraryIdentifier
            var page = queryItems.first(where: { $0.name == "page" }).flatMap({ $0.value }).flatMap(Int.init)
            var annotation = queryItems.first(where: { $0.name == "annotation" })?.value

            switch (parts[1], allowZotFileFormat) {
            case ("library", _):
                guard parts.count == 4, parts[2] == "items" else {
                    DDLogError("CustomURLController: path invalid for user library - \(path)")
                    return nil
                }
                key = parts[3]
                libraryId = .custom(.myLibrary)

            case ("groups", _):
                guard parts.count == 5, parts[3] == "items", let groupId = Int(parts[2]) else {
                    DDLogError("CustomURLController: path invalid for group - \(path)")
                    return nil
                }
                key = parts[4]
                libraryId = .group(groupId)

            case (_, true):
                guard parts.count == 3 else {
                    DDLogError("CustomURLController: path invalid for ZotFile format - \(path)")
                    return nil
                }
                let zotfileParts = parts[1].components(separatedBy: "_")
                guard zotfileParts.count == 2, let groupId = Int(zotfileParts[0]) else {
                    DDLogError("CustomURLController: wrong library format in ZotFile format - \(path)")
                    return nil
                }
                key = zotfileParts[1]
                libraryId = groupId == 0 ? .custom(.myLibrary) : .group(groupId)
                page = Int(parts[2])
                annotation = nil

            case (_, false):
                DDLogError("CustomURLController: incorrect library part - \(parts[1])")
                return nil
            }

            return (key, libraryId, page, annotation)
        }
    }
}
