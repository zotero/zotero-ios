//
//  FileStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol FileStorage: class {
    func read(_ file: File) throws -> Data
    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws
    func remove(_ file: File) throws
    func copy(from fromFile: File, to toFile: File) throws
    func move(from fromFile: File, to toFile: File) throws
    func has(_ file: File) -> Bool
    func size(of file: File) -> UInt64
    func createDirectories(for file: File) throws
    func contentsOfDirectory(at file: File) throws -> [URL]
    func contentsOfDirectory(at file: File) throws -> [File]
}

class FileStorageController: FileStorage {
    private let fileManager: FileManager = .default

    func read(_ file: File) throws -> Data {
        return try Data(contentsOf: file.createUrl())
    }

    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws {
        try self.createDirectories(for: file)
        try data.write(to: file.createUrl(), options: options)
    }

    func remove(_ file: File) throws {
        if file.isDirectory {
            // This File instance is a directory, remove its contents.
            let contents = try self.fileManager.contentsOfDirectory(at: file.createUrl(), includingPropertiesForKeys: [], options: [])
            for url in contents {
                try self.fileManager.removeItem(at: url)
            }
        }
        try self.fileManager.removeItem(at: file.createUrl())
    }

    func copy(from fromFile: File, to toFile: File) throws {
        try self.createDirectories(for: toFile)
        try self.fileManager.copyItem(at: fromFile.createUrl(), to: toFile.createUrl())
    }

    func move(from fromFile: File, to toFile: File) throws {
        try self.createDirectories(for: toFile)
        try self.fileManager.moveItem(atPath: fromFile.createUrl().path, toPath: toFile.createUrl().path)
    }

    func has(_ file: File) -> Bool {
        return self.fileManager.fileExists(atPath: file.createUrl().path)
    }

    func size(of file: File) -> UInt64 {
        let attributes = try? self.fileManager.attributesOfItem(atPath: file.createUrl().path)
        return (attributes?[FileAttributeKey.size] as? UInt64) ?? 0
    }

    func createDirectories(for file: File) throws {
        let relativeUrl = file.createRelativeUrl()
        try self.fileManager.createMissingDirectories(for: relativeUrl)
    }

    func contentsOfDirectory(at file: File) throws -> [URL] {
        return try self.fileManager.contentsOfDirectory(at: file.createUrl(), includingPropertiesForKeys: [], options: [])
    }

    func contentsOfDirectory(at file: File) throws -> [File] {
        return try self.contentsOfDirectory(at: file).map { Files.file(from: $0) }
    }
}
