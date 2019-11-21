//
//  Files+Extras.swift
//  Zotero
//
//  Created by Michal Rentka on 21/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension Files {
    static func objectFile(for object: SyncController.Object, libraryId: LibraryIdentifier,
                           key: String, ext: String) -> File {
        let objectName: String

        switch object {
        case .collection:
            objectName = "collection"
        case .item, .trash:
            objectName = "item"
        case .search:
            objectName = "search"
        case .tag:
            objectName = "tag"
        case .group:
            objectName = "group"
        }

        return FileData(rootPath: Files.documentsRootPath,
                        relativeComponents: ["downloads"],
                        name: "library_\(libraryId.fileName)_\(objectName)_\(key)", ext: ext)
    }
}

extension LibraryIdentifier {
    fileprivate var fileName: String {
        switch self {
        case .custom(let type):
            switch type {
            case .myLibrary:
                return "custom_my_library"
            }
        case .group(let identifier):
            return "group_\(identifier)"
        }
    }
}
