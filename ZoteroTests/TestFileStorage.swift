//
//  TestFileStorage.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 06/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

@testable import Zotero

import Foundation

struct TestErrors {
    static let file = NSError(domain: "file", code: 123, userInfo: nil)
}

class TestFileStorage: FileStorage {
    var fileManager: FileManager = .default

    private var data: Data?
    private var file: File?

    func read(_ file: File) throws -> Data {
        if file.createUrl() == self.file?.createUrl(), let data = self.data {
            return data
        }
        throw TestErrors.file
    }

    func write(_ data: Data, to file: File, options: Data.WritingOptions) throws {
        self.data = data
        self.file = file
    }

    func remove(_ file: File) throws {
        if file.createUrl() == self.file?.createUrl() {
            self.data = nil
            self.file = nil
        }
    }

    func has(_ file: File) -> Bool {
        return file.createUrl() == self.file?.createUrl()
    }

    func copy(from url: File, to file: File) throws {}

    func size(of file: File) -> UInt64 {
        return UInt64(self.data?.count ?? 0)
    }

    func createDictionaries(for file: File) throws {}

    func move(from fromFile: File, to toFile: File) throws {}

    func createDirectories(for file: File) throws {}

    func contentsOfDirectory(at file: File) throws -> [File] {
        return []
    }

    func contentsOfDirectory(at file: File) throws -> [URL] {
        return []
    }

    func link(file fromFile: File, to toFile: File) throws {}

    func directoryData(for file: File) -> DirectoryData? {
        return nil
    }
}
