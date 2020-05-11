//
//  Files.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Files {
    // MARK: - Base paths

    static var appGroupPath: String = {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?.path ?? Files.documentsRootPath
    }()

    static var documentsRootPath: String = {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .allDomainsMask, true).first ?? "/"
    }()

    static var cachesRootPath: String = {
        return NSSearchPathForDirectoriesInDomains(.cachesDirectory, .allDomainsMask, true).first ?? "/"
    }()

    // MARK: - Items

    static func objectFile(for object: SyncObject, libraryId: LibraryIdentifier,
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

        return FileData(rootPath: Files.appGroupPath,
                        relativeComponents: ["downloads"],
                        name: "library_\(libraryId.fileName)_\(objectName)_\(key)",
                        ext: ext)
    }

    // MARK: - Database

    static func dbFile(for userId: Int) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["database"], name: "maindb_\(userId)", ext: "realm")
    }

    static var translatorsDbFile: File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["database"], name: "translators", ext: "realm")
    }

    // MARK: - Logging

    static var debugLogDirectory: File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["debug_logs"], name: "", ext: "")
    }

    // MARK: - Bundled

    static var translators: File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["translators"], name: "", ext: "")
    }

    static func translator(filename: String) -> File {
        let name = filename.split(separator: ".").first.flatMap({ String($0) }) ?? filename
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["translators"], name: name, ext: "")
    }

    // MARK: - Annotations

    static func annotationPreview(annotationKey: String, pdfKey: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["annotations", pdfKey], name: annotationKey, ext: "jpg")
    }

    // MARK: - Share extension

    static func shareExtensionTmpItem(key: String, ext: String) -> File {
        return FileData(rootPath: Files.appGroupPath,
                        relativeComponents: ["tmp"],
                        name: "item_\(key)",
                        ext: ext)
    }

    // MARK: - Helper

    static func file(from url: URL) -> File {
        return FileData(rootPath: url.deletingLastPathComponent().relativePath, relativeComponents: [],
                        name: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension.lowercased())
    }

    static func uploadFile(from streamUrl: URL) -> File {
        return FileData(rootPath: Files.appGroupPath,
                        relativeComponents: ["uploads"],
                        name: streamUrl.lastPathComponent,
                        ext: streamUrl.pathExtension)
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
