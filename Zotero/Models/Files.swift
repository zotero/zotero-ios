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

    // MARK: - Attachments

    static var downloadDirectory: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["downloads"])
    }

    static func libraryDirectory(for libraryId: LibraryIdentifier) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName])
    }

    static func attachmentFile(in libraryId: LibraryIdentifier, key: String, contentType: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName], name: key, contentType: contentType)
    }

    static func attachmentFile(in libraryId: LibraryIdentifier, key: String, ext: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName], name: key, ext: ext)
    }

    static func link(filename: String, key: String) -> File {
        let (name, ext) = self.split(filename: filename)
        return FileData(rootPath: self.cachesRootPath, relativeComponents: ["links", key], name: name, ext: ext)
    }

    // MARK: - JSON cache

    static func jsonCacheFile(for object: SyncObject, libraryId: LibraryIdentifier, key: String) -> File {
        let objectName: String
        switch object {
        case .collection:
            objectName = "collection"
        case .item, .trash:
            objectName = "item"
        case .search:
            objectName = "search"
        }
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["jsons"],
                        name: "\(libraryId.folderName)_\(objectName)_\(key)", ext: "json")
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
        let name = self.split(filename: filename).name
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["translators"], name: name, ext: "")
    }

    // MARK: - Annotations

    static func annotationPreview(annotationKey: String, pdfKey: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["annotations", pdfKey], name: annotationKey, ext: "jpg")
    }

    // MARK: - Share extension

    static func shareExtensionTmpItem(key: String, ext: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["tmp"], name: "item_\(key)", ext: ext)
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

    private static func split(filename: String) -> (name: String, extension: String) {
        if let index = filename.lastIndex(of: ".") {
            return (String(filename[filename.startIndex..<index]),
                    String(filename[filename.index(index, offsetBy: 1)..<filename.endIndex]))
        }
        return (filename, "")
    }
}

extension LibraryIdentifier {
    fileprivate var folderName: String {
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
