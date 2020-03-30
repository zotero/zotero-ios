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
    var isDirectory: Bool { get }

    func createUrl() -> URL
    func createRelativeUrl() -> URL
}

extension File {
    var isDirectory: Bool {
        return self.name == "" && self.ext == ""
    }

    var mimeType: String {
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, self.ext as NSString, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }

    func createUrl() -> URL {
        if self.isDirectory {
            return self.createRelativeUrl()
        }
        return self.createRelativeUrl().appendingPathComponent(self.name).appendingPathExtension(self.ext)
    }

    func createRelativeUrl() -> URL {
        var url = URL(fileURLWithPath: self.rootPath)
        self.relativeComponents.forEach { component in
            url = url.appendingPathComponent(component)
        }
        return url
    }
}

struct FileData: File {
    let rootPath: String
    let relativeComponents: [String]
    let name: String
    let ext: String
}
