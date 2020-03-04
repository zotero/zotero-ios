//
//  DebugLogging.swift
//  Zotero
//
//  Created by Michal Rentka on 04/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

protocol DebugLoggingCoordinator: class {
    func share(logs: [URL], completed: @escaping () -> Void)
    func show(error: DebugLogging.Error)
}

class DebugLogFormatter: NSObject, DDLogFormatter {
    private var lastTimestamp: Date?

    func format(message logMessage: DDLogMessage) -> String? {
        let schema = self.schema(from: logMessage.file)
        let level = self.logLevelString(from: logMessage.level)
        let timeDiff = self.lastTimestamp.flatMap({ logMessage.timestamp.timeIntervalSince($0) }) ?? 0
        self.lastTimestamp = logMessage.timestamp
        return "\(level) \(schema)(+\(timeDiff)): \(logMessage.message)." +
               " [\(logMessage.queueLabel); \(logMessage.fileName); " +
               "\(logMessage.function ?? ""); \(logMessage.line); \(logMessage.timestamp.timeIntervalSince1970)]"
    }

    private func schema(from file: String) -> String {
        if file.contains("Zotero/") {
            return "Zotero"
        } else if file.contains("ZShare/") {
            return "ZShare"
        } else {
            return "Unknown"
        }
    }

    private func logLevelString(from level: DDLogLevel) -> String {
        switch level {
        case .all:
            return "[ALL]"
        case .debug:
            return "[DEBUG]"
        case .error:
            return "[ERROR]"
        case .info:
            return "[INFO]"
        case .off:
            return "[OFF]"
        case .verbose:
            return "[VERBOSE]"
        case .warning:
            return "[WARNING]"
        @unknown default:
            return "[UNKNOWN]"
        }
    }
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

    @UserDefault(key: "StartLoggingOnNextLaunch", defaultValue: false)
    private var startLoggingOnLaunch: Bool
    private var logger: DDFileLogger?
    weak var coordinator: DebugLoggingCoordinator?

    init(fileStorage: FileStorage) {
        self.fileStorage = fileStorage
    }

    var isLoggingInProgress: Bool {
        return self.logger != nil
    }

    var isWaitingOnTermination: Bool {
        return self.startLoggingOnLaunch
    }

    func start(type: LoggingType) {
        switch type {
        case .immediate:
            self.startLogger()
        case .nextLaunch:
            self.startLoggingOnLaunch = true
        }
    }

    func stop() {
        guard let logger = self.logger else { return }

        DDLog.remove(logger)
        self.logger = nil

        logger.rollLogFile { [weak self] in
            DispatchQueue.main.async {
                self?.shareLogs()
            }
        }
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

    func startLoggingOnLaunchIfNeeded() {
        guard self.startLoggingOnLaunch else { return }
        self.startLoggingOnLaunch = false
        self.startLogger()
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
            logger.logFormatter = DebugLogFormatter()

            DDLog.add(logger)
            self.logger = logger
        } catch let error {
            DDLogError("DebugLogging: can't start logger - \(error)")
            self.coordinator?.show(error: .start)
        }
    }
}
