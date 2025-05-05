//
//  File.swift
//  Zotero
//
//  Created by Michal Rentka on 21/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import MobileCoreServices

protocol File {
    var rootPath: String { get }
    var relativeComponents: [String] { get }
    var name: String { get }
    var ext: String { get }
    var fileName: String { get }
    var mimeType: String { get }
    var directory: File { get }

    func createUrl() -> URL
    func createRelativeUrl() -> URL
    func appending(relativeComponent: String) -> File
    func copy(withExt ext: String) -> File
    func copy(withName name: String, ext: String) -> File
}

extension File {
    func createUrl() -> URL {
        var url = createRelativeUrl()
        if !name.isEmpty {
            url = url.appendingPathComponent(name)
        }
        if !ext.isEmpty {
            url = url.appendingPathExtension(ext)
        }
        return url
    }

    func createRelativeUrl() -> URL {
        var url = URL(fileURLWithPath: rootPath)
        relativeComponents.forEach { component in
            url = url.appendingPathComponent(component)
        }
        return url
    }

    var fileName: String {
        var fileName = name
        if !ext.isEmpty {
            fileName += "." + ext
        }
        return fileName
    }

    var directory: File {
        return FileData.directory(rootPath: rootPath, relativeComponents: relativeComponents)
    }

    func appending(relativeComponent: String) -> File {
        return FileData(rootPath: rootPath, relativeComponents: relativeComponents + [relativeComponent], name: name, ext: ext)
    }

    func copy(withName name: String, ext: String) -> File {
        return FileData(rootPath: rootPath, relativeComponents: relativeComponents, name: name, ext: ext)
    }

    func copy(withExt ext: String) -> File {
        return FileData(rootPath: rootPath, relativeComponents: relativeComponents, name: name, ext: ext)
    }
}

struct FileData: File {
    enum ContentType {
        case contentType(String)
        case ext(String)
        case directory
    }

    let rootPath: String
    let relativeComponents: [String]
    let name: String
    let ext: String
    let mimeType: String

    init(rootPath: String, relativeComponents: [String], name: String, type: ContentType) {
        self.rootPath = rootPath
        self.relativeComponents = relativeComponents
        self.name = name

        switch type {
        case .contentType(let contentType):
            mimeType = contentType
            ext = (!contentType.isEmpty ? contentType.extensionFromMimeType : nil) ?? ""
            
        case .ext(let ext):
            mimeType = (!ext.isEmpty ? ext.mimeTypeFromExtension : nil) ?? "application/octet-stream"
            self.ext = ext

        case .directory:
            mimeType = ""
            ext = ""
        }
    }

    init(rootPath: String, relativeComponents: [String], name: String, ext: String) {
        self.init(rootPath: rootPath, relativeComponents: relativeComponents, name: name, type: .ext(ext))
    }

    init(rootPath: String, relativeComponents: [String], name: String, contentType: String) {
        self.init(rootPath: rootPath, relativeComponents: relativeComponents, name: name, type: .contentType(contentType))
    }

    static func directory(rootPath: String, relativeComponents: [String]) -> FileData {
        return FileData(rootPath: rootPath, relativeComponents: relativeComponents, name: "", type: .directory)
    }
}

extension FileData: Hashable {}
