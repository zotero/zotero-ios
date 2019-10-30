//
//  FileStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
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

protocol FileStorage {
    func read(_ file: File) throws -> Data
    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws
    func remove(_ file: File) throws
    func copy(from url: File, to file: File) throws
    func has(_ file: File) -> Bool
    func size(of file: File) -> UInt64
    func createDictionaries(for file: File) throws
}

extension FileStorage {
    /// Copy attachments from file picker url (external app sandboxes) to our internal url (our app sandbox)
    /// - parameter attachments: Attachments which will be copied if needed
    func copyAttachmentFilesIfNeeded(for attachments: [ItemDetailStore.State.Attachment]) throws {
        for attachment in attachments {
            switch attachment.type {
            case .url: continue
            case .file(let originalFile, _, _):
                let newFile = Files.objectFile(for: .item, libraryId: attachment.libraryId,
                                               key: attachment.key, ext: originalFile.ext)
                // Make sure that the file was not already moved to our internal location before
                guard originalFile.createUrl() != newFile.createUrl() else { continue }

                // We can just "try?" to copy the file here, if it doesn't work the user will be notified during sync
                // process and can try to remove/re-add the attachment
                try self.copy(from: originalFile, to: newFile)
            }
        }
    }
}

class FileStorageController: FileStorage {
    private let fileManager: FileManager = .default

    func read(_ file: File) throws -> Data {
        return try Data(contentsOf: file.createUrl())
    }

    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws {
        let url = file.createUrl()
        try self.fileManager.createMissingDirectories(for: url.deletingLastPathComponent())
        try data.write(to: url, options: options)
    }

    func remove(_ file: File) throws {
        try self.fileManager.removeItem(at: file.createUrl())
    }

    func copy(from fromFile: File, to toFile: File) throws {
        try self.fileManager.copyItem(at: fromFile.createUrl(), to: toFile.createUrl())
    }

    func has(_ file: File) -> Bool {
        return self.fileManager.fileExists(atPath: file.createUrl().path)
    }

    func size(of file: File) -> UInt64 {
        let attributes = try? self.fileManager.attributesOfItem(atPath: file.createUrl().path)
        return (attributes?[FileAttributeKey.size] as? UInt64) ?? 0
    }

    func createDictionaries(for file: File) throws {
        try self.fileManager.createMissingDirectories(for: file.createRelativeUrl())
    }
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
