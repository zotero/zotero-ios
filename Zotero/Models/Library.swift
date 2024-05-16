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
    let fileSyncType: LibraryFileSyncType

    var id: LibraryIdentifier {
        return self.identifier
    }

    var metadataAndFilesEditable: Bool {
        return metadataEditable && filesEditable
    }

    init(customLibrary: RCustomLibrary) {
        identifier = .custom(customLibrary.type)
        name = customLibrary.type.libraryName
        metadataEditable = true
        filesEditable = true
        fileSyncType = customLibrary.fileSyncType
    }

    init(group: RGroup) {
        identifier = .group(group.identifier)
        name = group.name
        metadataEditable = group.canEditMetadata
        filesEditable = group.canEditFiles
        fileSyncType = group.fileSyncType
    }

    init(identifier: LibraryIdentifier, name: String, metadataEditable: Bool, filesEditable: Bool, fileSyncType: LibraryFileSyncType) {
        self.identifier = identifier
        self.name = name
        self.metadataEditable = metadataEditable
        self.filesEditable = filesEditable
        self.fileSyncType = fileSyncType
    }

    func copy(with syncType: LibraryFileSyncType) -> Library {
        return Library(identifier: identifier, name: name, metadataEditable: metadataEditable, filesEditable: filesEditable, fileSyncType: syncType)
    }
}
