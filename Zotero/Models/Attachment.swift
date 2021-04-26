//
//  Attachment.swift
//  Zotero
//
//  Created by Michal Rentka on 02/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct Attachment: Identifiable, Equatable {
    enum FileLocation {
        case local, remote, remoteMissing
    }

    enum NewFileLinkType {
        case importedUrl, importedFile, embeddedImage, linkedFile
    }

    enum Kind: Equatable {
        case file(filename: String, contentType: String, location: FileLocation, linkType: NewFileLinkType)
        case url(URL)
    }

    let type: Kind
    let title: String
    let key: String
    let libraryId: LibraryIdentifier

    var id: String { return self.key }

    init(type: Kind, title: String, key: String, libraryId: LibraryIdentifier) {
        self.key = key
        self.title = title
        self.libraryId = libraryId
        self.type = type
    }

    init?(item: RItem, type: Kind) {
        guard let libraryId = item.libraryId else {
            DDLogError("Attachment: library not assigned to item (\(item.key))")
            return nil
        }

        self.libraryId = libraryId
        self.key = item.key
        self.title = item.displayTitle
        self.type = type
    }

    func changed(location: FileLocation) -> Attachment {
        switch self.type {
        case .url: return self
        case .file(let filename, let contentType, _, let linkType):
            return Attachment(type: .file(filename: filename, contentType: contentType, location: location, linkType: linkType),
                              title: self.title,
                              key: self.key,
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
