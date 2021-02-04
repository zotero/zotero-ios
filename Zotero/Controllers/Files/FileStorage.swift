//
//  FileStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DirectoryData {
    let fileCount: Int
    let mbSize: Double
}

protocol FileStorage: class {
    var fileManager: FileManager { get }
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
    func link(file fromFile: File, to toFile: File) throws
    func directoryData(for files: [File]) -> DirectoryData
}

final class FileStorageController: FileStorage {
    let fileManager: FileManager = .default

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

    func link(file fromFile: File, to toFile: File) throws {
        let toUrl = toFile.createUrl()

        guard !self.fileManager.fileExists(atPath: toUrl.path) else { return }

        try self.createDirectories(for: toFile)
        try self.fileManager.linkItem(at: fromFile.createUrl(), to: toUrl)
    }

    func directoryData(for files: [File]) -> DirectoryData {
        var all = DirectoryData(fileCount: 0, mbSize: 0)

        for file in files {
            if let fileData = self.directoryData(for: file) {
                all = DirectoryData(fileCount: fileData.fileCount + all.fileCount, mbSize: fileData.mbSize + all.mbSize)
            }
        }

        return all
    }

    private func directoryData(for file: File) -> DirectoryData? {
        let properties: Set<URLResourceKey> = [.totalFileSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = self.fileManager.enumerator(at: file.createUrl(), includingPropertiesForKeys: Array(properties)) else { return nil }

        var totalSize = 0
        var count = 0

        for case let url as URL in enumerator {
            guard let resourceValues = (try? url.resourceValues(forKeys: properties)),
                  let isRegularFile = resourceValues.isRegularFile, isRegularFile else { continue }
            let size = resourceValues.totalFileSize ?? resourceValues.fileSize ?? 0
            totalSize += size
            count += 1
        }

        return DirectoryData(fileCount: count, mbSize: (Double(totalSize) / 1048576))
    }
}
