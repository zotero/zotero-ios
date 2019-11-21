//
//  CoordinatedFileStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 21/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol CoordinatedFileStorage {
    func read(_ file: File, options: NSFileCoordinator.ReadingOptions) throws -> Data
    func write(_ data: Data, to file: File, dataOptions: Data.WritingOptions, coordinatorOptions: NSFileCoordinator.WritingOptions) throws
}

class CoordinatedFileStorageController: CoordinatedFileStorage {
    private let fileManager: FileManager = .default
    private let coordinator: NSFileCoordinator = NSFileCoordinator()

    func read(_ file: File, options: NSFileCoordinator.ReadingOptions) throws -> Data {
        var coordinatorError: NSError?
        var readingError: NSError?
        var readData: Data?

        self.coordinator.coordinate(readingItemAt: file.createUrl(), options: options, error: &coordinatorError) { url in
            do {
                readData = try Data(contentsOf: url)
            } catch let error {
                readingError = error as NSError
            }
        }

        guard let data = readData else {
            throw coordinatorError ?? readingError ?? NSError()
        }
        return data
    }

    func write(_ data: Data, to file: File, dataOptions: Data.WritingOptions, coordinatorOptions: NSFileCoordinator.WritingOptions) throws {
        var coordinatorError: NSError?
        var writingError: NSError?

        self.coordinator.coordinate(writingItemAt: file.createUrl(), options: coordinatorOptions, error: &coordinatorError) { url in
            do {
                try self.fileManager.createMissingDirectories(for: url.deletingLastPathComponent())
                try data.write(to: url, options: dataOptions)
            } catch let error {
                writingError = error as NSError
            }
        }

        if let error = coordinatorError ?? writingError {
            throw error
        }
    }
}
