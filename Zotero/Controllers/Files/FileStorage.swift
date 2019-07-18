//
//  FileStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol File {
    var rootPath: String { get }
    var relativeComponents: [String] { get }
    var name: String { get }
    var ext: String { get }

    func createUrl() -> URL
    func createRelativeUrl() -> URL
}

protocol FileStorage {
    func read(_ file: File) throws -> Data
    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws
    func remove(_ file: File) throws
    func has(_ file: File) -> Bool
    func size(of file: File) -> UInt64
    func createDictionaries(for file: File) throws
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
