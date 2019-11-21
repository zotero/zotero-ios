//
//  FileStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol FileStorage {
    func read(_ file: File) throws -> Data
    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws
    func remove(_ file: File) throws
    func copy(from fromFile: File, to toFile: File) throws
    func move(from fromFile: File, to toFile: File) throws
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

    func move(from fromFile: File, to toFile: File) throws {
        try self.fileManager.moveItem(at: fromFile.createUrl(), to: toFile.createUrl())
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
