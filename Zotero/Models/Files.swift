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

    static func attachmentFile(in libraryId: LibraryIdentifier, key: String, filename: String, contentType: String) -> File {
        let name = self.split(filename: filename).name
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName, key], name: name, contentType: contentType)
    }

    static func attachmentDirectory(in libraryId: LibraryIdentifier, key: String) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName, key])
    }

    static var uploads: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["uploads"])
    }

    static func temporaryZipUploadFile(key: String) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["uploads"], name: key, ext: "zip")
    }

    static var temporaryMultipartformUploadFile: File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["uploads"], name: UUID().uuidString, contentType: "")
    }

    static func temporaryFile(ext: String) -> File {
        return FileData(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero"], name: UUID().uuidString, ext: ext)
    }

    // MARK: - JSON cache

    static var jsonCache: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["jsons"])
    }

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
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["jsons"], name: "\(libraryId.folderName)_\(objectName)_\(key)", ext: "json")
    }

    // MARK: - Database

    static func dbFile(for userId: Int) -> File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["database"], name: "maindb_\(userId)", ext: "realm")
    }

    static var bundledDataDbFile: File {
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["database"], name: "translators", ext: "realm")
    }

    // MARK: - Logging

    static var debugLogDirectory: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["debug_logs"])
    }

    // MARK: - Bundled

    static var translators: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["translators"])
    }

    static func translator(filename: String) -> File {
        let name = self.split(filename: filename).name
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["translators"], name: name, ext: "")
    }

    static var styles: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["styles"])
    }

    static func style(filename: String) -> File {
        let name = self.split(filename: filename).name
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["styles"], name: name, ext: "csl")
    }

    // MARK: - PDF

    #if MAINAPP

    static func pdfToShare(filename: String, key: String) -> File {
        let (name, ext) = self.split(filename: filename)
        return FileData(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero", "sharing", key], name: name, ext: ext)
    }

    static func pageThumbnail(pageIndex: UInt, key: String, libraryId: LibraryIdentifier, appearance: Appearance) -> File {
        let nameSuffix: String
        switch appearance {
        case .dark:
            nameSuffix = "_dark"

        case .sepia:
            nameSuffix = "_sepia"

        case .light:
            nameSuffix = ""
        }
        return FileData(rootPath: Files.appGroupPath, relativeComponents: ["thumbnails", libraryId.folderName, key], name: "\(pageIndex)" + nameSuffix, contentType: "png")
    }

    static func pageThumbnails(for key: String, libraryId: LibraryIdentifier) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["thumbnails", libraryId.folderName, key])
    }

    static func pageThumbnails(for libraryId: LibraryIdentifier) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["thumbnails", libraryId.folderName])
    }

    #endif

    static var pageThumbnails: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["thumbnails"])
    }

    // MARK: - Annotations

    #if MAINAPP

    static func annotationPreview(annotationKey: String, pdfKey: String, libraryId: LibraryIdentifier, appearance: Appearance) -> File {
        let nameSuffix: String
        switch appearance {
        case .dark:
            nameSuffix = "_dark"

        case .sepia:
            nameSuffix = "_sepia"

        case .light:
            nameSuffix = ""
        }
        return FileData(
            rootPath: Files.appGroupPath,
            relativeComponents: ["annotations", libraryId.folderName, pdfKey],
            name: annotationKey + nameSuffix,
            ext: "png"
        )
    }

    static func annotationPreviews(for pdfKey: String, libraryId: LibraryIdentifier) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["annotations", libraryId.folderName, pdfKey])
    }

    static func annotationPreviews(for libraryId: LibraryIdentifier) -> File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["annotations", libraryId.folderName])
    }

    #endif

    static var annotationPreviews: File {
        return FileData.directory(rootPath: Files.appGroupPath, relativeComponents: ["annotations"])
    }

    // MARK: - Share extension

    static func shareExtensionDownload(key: String, ext: String) -> File {
        return FileData(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero", "shareext", "downloads"], name: "item_\(key)", ext: ext)
    }

    static func shareExtensionDownload(key: String, contentType: String) -> File {
        return FileData(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero", "shareext", "downloads"], name: "item_\(key)", contentType: contentType)
    }

    // MARK: Epub/Html reader

    static var tmpReaderDirectory: File {
        return FileData.directory(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero", UUID().uuidString])
    }

    // MARK: - Helper

    static var cache: File {
        return FileData.directory(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero"])
    }

    static func file(from url: URL) -> File {
        var (root, components) = self.rootAndComponents(from: url)
        if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
            if resourceValues.isDirectory == true {
                return FileData.directory(rootPath: root, relativeComponents: components)
            }
        } else if url.pathExtension.isEmpty {
            return FileData.directory(rootPath: root, relativeComponents: components)
        }
        var name = url.deletingPathExtension().lastPathComponent
        name = name.removingPercentEncoding ?? name
        if components.last == name {
            components = components.dropLast()
        }
        return FileData(rootPath: root, relativeComponents: components, name: name, ext: url.pathExtension)
    }

    private static func rootAndComponents(from url: URL) -> (String, [String]) {
        var urlString: String
        if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
            if resourceValues.isDirectory == true {
                urlString = url.relativeString
            } else {
                urlString = url.deletingLastPathComponent().relativeString
            }
        } else if url.pathExtension.isEmpty {
            urlString = url.relativeString
        } else {
            urlString = url.deletingLastPathComponent().relativeString
        }

        if urlString.hasPrefix("file://") {
            urlString = String(urlString[urlString.index(urlString.startIndex, offsetBy: 7)...])
        }

        if let range = urlString.range(of: self.appGroupPath) {
            return (self.appGroupPath, self.components(from: urlString, excluding: range))
        }
        if let range = urlString.range(of: self.cachesRootPath) {
            return (self.cachesRootPath, self.components(from: urlString, excluding: range))
        }
        if let range = urlString.range(of: self.documentsRootPath) {
            return (self.documentsRootPath, self.components(from: urlString, excluding: range))
        }

        return ((urlString.removingPercentEncoding ?? urlString), [])
    }

    private static func components(from string: String, excluding: Range<String.Index>) -> [String] {
        return string[excluding.upperBound..<string.endIndex].components(separatedBy: "/").filter({ !$0.isEmpty && $0 != "/" }).map({ $0.removingPercentEncoding ?? $0 })
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
    var folderName: String {
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
