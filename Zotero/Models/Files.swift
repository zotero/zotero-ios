//
//  Files.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Files {
    static var documentsRootPath: String = {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .allDomainsMask, true).first ?? "/"
    }()

    static var cachesRootPath: String = {
        return NSSearchPathForDirectoriesInDomains(.cachesDirectory, .allDomainsMask, true).first ?? "/"
    }()

    static func json(for group: SyncGroupType, object: SyncObjectType, version: Int, index: Int) -> File {
        return FileData(rootPath: Files.cachesRootPath,
                        relativeComponents: ["sync", group.fileComponent, object.fileComponent, version.description],
                        name: index.description, ext: "json")
    }

    static var dbFile: File {
        return FileData(rootPath: Files.documentsRootPath, relativeComponents: [], name: "maindb", ext: "realm")
    }
}
