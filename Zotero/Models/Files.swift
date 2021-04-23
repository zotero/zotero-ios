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

    static var downloads: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["downloads"])
    }

    static func downloads(for libraryId: LibraryIdentifier) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName])
    }

    static func newAttachmentFile(in libraryId: LibraryIdentifier, key: String, filename: String, contentType: String) -> File {
        let name = self.split(filename: filename).name
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName, key], name: name, contentType: contentType)
    }

    static func newAttachmentDirectory(in libraryId: LibraryIdentifier, key: String) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName, key])
    }

    static func attachmentFile(in libraryId: LibraryIdentifier, key: String, contentType: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName], name: key, contentType: contentType)
    }

    static func attachmentFile(in libraryId: LibraryIdentifier, key: String, ext: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName], name: key, ext: ext)
    }

    static func snapshotHtmlFile(in libraryId: LibraryIdentifier, key: String, filename: String) -> File {
        let (name, ext) = self.split(filename: filename)
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName, key], name: name, ext: ext)
    }

    static func snapshotZipFile(in libraryId: LibraryIdentifier, key: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName], name: key, ext: "zip")
    }

    static func link(filename: String, key: String) -> File {
        let (name, ext) = self.split(filename: filename)
        return FileData(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero", "links", key], name: name, ext: ext)
    }

    static var temporaryUploadFile: File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["uploads"], name: UUID().uuidString, ext: "")
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
        case .settings:
            objectName = "settings"
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
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["translators"])
    }

    static func translator(filename: String) -> File {
        let name = self.split(filename: filename).name
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["translators"], name: name, ext: "")
    }

    // MARK: - PDF

    static func pdfToShare(filename: String, key: String) -> File {
        let (name, ext) = self.split(filename: filename)
        return FileData(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero", "sharing", key], name: name, ext: ext)
    }

    // MARK: - Annotations

    static func annotationPreview(annotationKey: String, pdfKey: String, libraryId: LibraryIdentifier, isDark: Bool) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["annotations", libraryId.folderName, pdfKey],
                        name: annotationKey + (isDark ? "_dark" : ""), ext: "png")
    }

    static func annotationPreviews(for pdfKey: String, libraryId: LibraryIdentifier) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["annotations", libraryId.folderName, pdfKey])
    }

    static func annotationPreviews(for libraryId: LibraryIdentifier) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["annotations", libraryId.folderName])
    }

    static var annotationPreviews: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["annotations"])
    }

    // MARK: - Share extension

    static func shareExtensionTmpItem(key: String, ext: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["tmp"], name: "item_\(key)", ext: ext)
    }

    static func shareExtensionTmpItem(key: String, contentType: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["tmp"], name: "item_\(key)", contentType: contentType)
    }

    // MARK: - Helper

    static var cache: File {
        return FileData.directory(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero"])
    }

    static func file(from url: URL) -> File {
        if url.hasDirectoryPath {
            return FileData(rootPath: url.deletingLastPathComponent().relativePath, relativeComponents: [url.lastPathComponent], name: "", type: .directory)
        }
        return FileData(rootPath: url.deletingLastPathComponent().relativePath, relativeComponents: [],
                        name: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
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
