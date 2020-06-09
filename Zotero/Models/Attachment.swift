//
//  Attachment.swift
//  Zotero
//
//  Created by Michal Rentka on 02/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

struct Attachment: Identifiable, Equatable {
    enum ContentType: Equatable {
        case file(file: File, filename: String, isLocal: Bool, hasRemoteResource: Bool)
        case url(URL)

        static func == (lhs: ContentType, rhs: ContentType) -> Bool {
            switch (lhs, rhs) {
            case (.url(let lUrl), .url(let rUrl)):
                return lUrl == rUrl
            case (.file(let lFile, _, _, _), .file(let rFile, _, _, _)):
                return lFile.createUrl() == rFile.createUrl()
            default:
                return false
            }
        }
    }

    let key: String
    let title: String
    let type: ContentType
    let libraryId: LibraryIdentifier

    var iconName: String {
        switch self.type {
        case .file(let file, _, _, _):
            switch file.ext {
            case "pdf":
                return "pdf"
            default:
                return "document"
            }
        case .url:
            return "web-page"
        }
    }

    var id: String { return self.key }

    init(key: String, title: String, type: ContentType,
         libraryId: LibraryIdentifier) {
        self.key = key
        self.title = title
        self.type = type
        self.libraryId = libraryId
    }

    init?(item: RItem, type: ContentType) {
        guard let libraryId = item.libraryObject?.identifier else {
            DDLogError("Attachment: library not assigned to item (\(item.key))")
            return nil
        }

        self.libraryId = libraryId
        self.key = item.key
        self.title = item.displayTitle
        self.type = type
    }

    func changed(isLocal: Bool) -> Attachment {
        switch type {
        case .url: return self
        case .file(let file, let filename, _, let hasRemoteResource):
            return Attachment(key: self.key,
                              title: self.title,
                              type: .file(file: file, filename: filename, isLocal: isLocal, hasRemoteResource: hasRemoteResource),
                              libraryId: self.libraryId)
        }
    }
}

extension Attachment: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.key)
        hasher.combine(self.title)
    }
}
