//
//  Files.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Files {
    static var appGroupPath: String = {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "org.zotero.ios.Zotero")?.path ?? Files.documentsRootPath
    }()

    static var documentsRootPath: String = {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .allDomainsMask, true).first ?? "/"
    }()

    static var cachesRootPath: String = {
        return NSSearchPathForDirectoriesInDomains(.cachesDirectory, .allDomainsMask, true).first ?? "/"
    }()

    static func sharedItem(key: String, ext: String) -> File {
        return FileData(rootPath: Files.appGroupPath,
                        relativeComponents: ["extension"],
                        name: "item_\(key)",
                        ext: ext)
    }

    static func file(from url: URL) -> File {
        return FileData(rootPath: url.deletingLastPathComponent().relativePath, relativeComponents: [],
                        name: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension.lowercased())
    }

    static func dbFile(for userId: Int) -> File {
        return FileData(rootPath: Files.appGroupPath,
                        relativeComponents: ["database"],
                        name: "maindb_\(userId)", ext: "realm")
    }
}
