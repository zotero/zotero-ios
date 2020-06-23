//
//  DebugLogging.swift
//  Zotero
//
//  Created by Michal Rentka on 04/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

protocol DebugLoggingCoordinator: class {
    func share(logs: [URL], completed: @escaping () -> Void)
    func show(error: DebugLogging.Error)
}

class DebugLogging {
    enum LoggingType {
        case immediate, nextLaunch
    }

    enum Error: Swift.Error {
        case start
        case contentReading
    }

    private let fileStorage: FileStorage

    @UserDefault(key: "IsDebugLoggingEnabled", defaultValue: false)
    private(set) var isEnabled: Bool
    private var logger: DDFileLogger?
    weak var coordinator: DebugLoggingCoordinator?

    init(fileStorage: FileStorage) {
        self.fileStorage = fileStorage
    }

    func start(type: LoggingType) {
        self.isEnabled = true
        if type == .immediate {
            self.startLogger()
        }
    }

    func stop() {
        self.isEnabled = false

        guard let logger = self.logger else { return }

        DDLog.remove(logger)
        self.logger = nil

        logger.rollLogFile { [weak self] in
            DispatchQueue.main.async {
                self?.shareLogs()
            }
        }
    }

    func startLoggingOnLaunchIfNeeded() {
        guard self.isEnabled else { return }
        self.startLogger()
    }

    func storeLogs(completed: @escaping () -> Void) {
        guard let logger = self.logger else {
            completed()
            return
        }
        logger.rollLogFile(withCompletion: completed)
    }

    private func shareLogs() {
        do {
            let logs: [URL] = try self.fileStorage.contentsOfDirectory(at: Files.debugLogDirectory)
            // TODO: - share logs
            self.coordinator?.share(logs: logs) { [weak self] in
                self?.clearDebugDirectory()
            }
        } catch let error {
            DDLogError("DebugLogging: can't read debug directory contents - \(error)")
            self.coordinator?.show(error: .contentReading)
        }
    }

    private func clearDebugDirectory() {
        do {
            try self.fileStorage.remove(Files.debugLogDirectory)
        } catch let error {
            DDLogError("DebugLogging: can't delete directory - \(error)")
        }
    }

    private func startLogger() {
        do {
            let file = Files.debugLogDirectory
            if self.fileStorage.has(file) {
                try self.fileStorage.remove(file)
            }
            try self.fileStorage.createDirectories(for: file)

            let manager = DDLogFileManagerDefault(logsDirectory: file.createUrl().path)
            let logger = DDFileLogger(logFileManager: manager)
            let targetName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
            logger.logFormatter = DebugLogFormatter(targetName: targetName)
            logger.doNotReuseLogFiles = true
            logger.rollingFrequency = 60

            DDLog.add(logger)
            self.logger = logger
        } catch let error {
            DDLogError("DebugLogging: can't start logger - \(error)")
            self.coordinator?.show(error: .start)
        }
    }
}
