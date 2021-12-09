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
    var mimeType: String { get }
    var directory: File { get }

    func createUrl() -> URL
    func createRelativeUrl() -> URL
    func copyWithExt(_ ext: String) -> File
}

extension File {
    func createUrl() -> URL {
        var url = self.createRelativeUrl()
        if !self.name.isEmpty {
            url = url.appendingPathComponent(self.name)
        }
        if !self.ext.isEmpty {
            url = url.appendingPathExtension(self.ext)
        }
        return url
    }

    func createRelativeUrl() -> URL {
        var url = URL(fileURLWithPath: self.rootPath)
        self.relativeComponents.forEach { component in
            url = url.appendingPathComponent(component)
        }
        return url
    }

    var directory: File {
        return FileData.directory(rootPath: self.rootPath, relativeComponents: self.relativeComponents)
    }

    func copyWithExt(_ ext: String) -> File {
        return FileData(rootPath: self.rootPath, relativeComponents: self.relativeComponents, name: self.name, ext: ext)
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
            self.mimeType = contentType
            self.ext = contentType.extensionFromMimeType ?? ""
        case .ext(let ext):
            self.mimeType = ext.mimeTypeFromExtension ?? "application/octet-stream"
            self.ext = ext
        case .directory:
            self.mimeType = ""
            self.ext = ""
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
