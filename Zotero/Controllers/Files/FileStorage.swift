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

protocol FileStorage: AnyObject {
    var fileManager: FileManager { get }
    func read(_ file: File) throws -> Data
    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws
    func remove(_ file: File) throws
    func copy(from path: String, to toFile: File) throws
    func copy(from fromFile: File, to toFile: File) throws
    func move(from path: String, to toFile: File) throws
    func move(from fromFile: File, to toFile: File) throws
    func has(_ file: File) -> Bool
    func size(of file: File) -> UInt64
    func size(of path: String) -> UInt64
    func createDirectories(for file: File) throws
    func contentsOfDirectory(at file: File) throws -> [URL]
    func contentsOfDirectory(at file: File) throws -> [File]
    func sortedContentsOfDirectory(at file: File) throws -> [URL]
    func link(file fromFile: File, to toFile: File) throws
    func directoryData(for files: [File]) -> DirectoryData
    func isZip(file: File) -> Bool
    func isPdf(file: File) -> Bool
    func isEmptyOrNotFoundResponse(file: File) -> Bool
    func clearCache()
}

final class FileStorageController: FileStorage {
    let fileManager: FileManager = .default

    func read(_ file: File) throws -> Data {
        return try Data(contentsOf: file.createUrl())
    }

    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws {
        try createDirectories(for: file)
        try data.write(to: file.createUrl(), options: options)
    }

    func remove(_ file: File) throws {
        let url = file.createUrl()
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            // This File instance is a directory, remove its contents.
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [], options: [])
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        }

        // Delete the file/directory itself.
        try fileManager.removeItem(at: url)
    }

    func copy(from path: String, to toFile: File) throws {
        try createDirectories(for: toFile)
        try fileManager.copyItem(atPath: path, toPath: toFile.createUrl().path)
    }

    func copy(from fromFile: File, to toFile: File) throws {
        try createDirectories(for: toFile)
        try fileManager.copyItem(at: fromFile.createUrl(), to: toFile.createUrl())
    }

    func move(from fromFile: File, to toFile: File) throws {
        try move(from: fromFile.createUrl().path, to: toFile)
    }

    func move(from path: String, to toFile: File) throws {
        try createDirectories(for: toFile)
        try fileManager.moveItem(atPath: path, toPath: toFile.createUrl().path)
    }

    func has(_ file: File) -> Bool {
        return fileManager.fileExists(atPath: file.createUrl().path)
    }

    func size(of path: String) -> UInt64 {
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        return (attributes?[FileAttributeKey.size] as? UInt64) ?? 0
    }

    func size(of file: File) -> UInt64 {
        return size(of: file.createUrl().path)
    }

    func createDirectories(for file: File) throws {
        let relativeUrl = file.createRelativeUrl()
        try fileManager.createMissingDirectories(for: relativeUrl)
    }

    func sortedContentsOfDirectory(at file: File) throws -> [URL] {
        return try fileManager.contentsOfDirectory(at: file.createUrl(), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .map({ url in (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast) })
            .sorted(by: { $0.1 < $1.1 })
            .map({ $0.0 })
    }

    func contentsOfDirectory(at file: File) throws -> [URL] {
        return try fileManager.contentsOfDirectory(at: file.createUrl(), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    }

    func contentsOfDirectory(at file: File) throws -> [File] {
        return try contentsOfDirectory(at: file).map { Files.file(from: $0) }
    }

    func link(file fromFile: File, to toFile: File) throws {
        let toUrl = toFile.createUrl()

        guard !fileManager.fileExists(atPath: toUrl.path) else { return }

        try createDirectories(for: toFile)
        try fileManager.linkItem(at: fromFile.createUrl(), to: toUrl)
    }

    func directoryData(for files: [File]) -> DirectoryData {
        var fileCount: Int = 0
        var mbSize: Double = 0

        for file in files {
            guard let fileData = directoryData(for: file) else { continue }
            fileCount += fileData.fileCount
            mbSize += fileData.mbSize
        }

        return DirectoryData(fileCount: fileCount, mbSize: mbSize)

        func directoryData(for file: File) -> DirectoryData? {
            let properties: Set<URLResourceKey> = [.totalFileSizeKey, .fileSizeKey, .isRegularFileKey]
            guard let enumerator = fileManager.enumerator(at: file.createUrl(), includingPropertiesForKeys: Array(properties)) else { return nil }

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

    func isZip(file: File) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: file.createUrl().path) else { return false }
        defer { handle.closeFile() }
        let data = handle.readData(ofLength: 4)
        return data.starts(with: [0x50, 0x4b, 0x03, 0x04])
    }

    func isPdf(file: File) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: file.createUrl().path) else { return false }
        defer { handle.closeFile() }
        let data = handle.readData(ofLength: 4)
        return data.starts(with: [0x25, 0x50, 0x44, 0x46])
    }

    func isEmptyOrNotFoundResponse(file: File) -> Bool {
        let size = size(of: file)
        return size == 0 || (size == 9 && (try? read(file)).flatMap({ String(data: $0, encoding: .utf8) })?.caseInsensitiveCompare("Not found") == .orderedSame)
    }

    func clearCache() {
        // Remove general cache folder
        try? remove(Files.cache)
        // Remove cached item jsons
        try? remove(Files.jsonCache)
        // Remove annotation preview cache
        try? remove(Files.annotationPreviews)
        // Remove attachment page thumbnails
        try? remove(Files.pageThumbnails)
        // Remove interrupted upload files
        try? remove(Files.uploads)
        // Remove downloaded files
        try? remove(Files.downloads)
    }
}
