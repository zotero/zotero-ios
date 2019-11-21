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

    func createUrl() -> URL
    func createRelativeUrl() -> URL
}

struct FileData: File {
    var rootPath: String
    var relativeComponents: [String]
    var name: String
    var ext: String

    var mimeType: String {
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, self.ext as NSString, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }

    func createUrl() -> URL {
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
