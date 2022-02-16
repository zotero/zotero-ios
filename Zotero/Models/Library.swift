//
//  Library.swift
//  Zotero
//
//  Created by Michal Rentka on 19/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Library: Equatable, Identifiable, Hashable {
    let identifier: LibraryIdentifier
    let name: String
    let metadataEditable: Bool
    let filesEditable: Bool

    var id: LibraryIdentifier {
        return self.identifier
    }

    init(customLibrary: RCustomLibrary) {
        self.identifier = .custom(customLibrary.type)
        self.name = customLibrary.type.libraryName
        self.metadataEditable = true
        self.filesEditable = true
    }

    init(group: RGroup) {
        self.identifier = .group(group.identifier)
        self.name = group.name
        self.metadataEditable = group.canEditMetadata
        self.filesEditable = group.canEditFiles
    }

    init(identifier: LibraryIdentifier, name: String, metadataEditable: Bool, filesEditable: Bool) {
        self.identifier = identifier
        self.name = name
        self.metadataEditable = metadataEditable
        self.filesEditable = filesEditable
    }
}
