//
//  DebugLogFormatter.swift
//  Zotero
//
//  Created by Michal Rentka on 09/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

class DebugLogFormatter: NSObject, DDLogFormatter {
    private let targetName: String
    private var lastTimestamp: Date?

    init(targetName: String) {
        self.targetName = targetName
    }

    func format(message logMessage: DDLogMessage) -> String? {
        let level = self.logLevelString(from: logMessage.flag)
        let timeDiff = self.lastTimestamp.flatMap({ logMessage.timestamp.timeIntervalSince($0) }) ?? 0
        let timeWarning: String
        if timeDiff > 0.5 {
            timeWarning = " 🕐❗️"
        } else if timeDiff > 0.25 {
            timeWarning = " 🕐❓"
        } else {
            timeWarning = ""
        }
        let formattedTimeDiff = String(format: "+%.8f%@", timeDiff, timeWarning)
        self.lastTimestamp = logMessage.timestamp
        return "\(level) \(self.targetName)(\(formattedTimeDiff)): \(logMessage.message)." +
               " [(\(logMessage.line)) \(logMessage.fileName).\(logMessage.function ?? ""); " +
               "\(logMessage.queueLabel); \(logMessage.timestamp.timeIntervalSince1970)]"
    }

    private func logLevelString(from level: DDLogFlag) -> String {
        switch level {
        case .debug:
            return "[DEBUG]"
        case .error:
            return "[❗️ERROR❗️]"
        case .info:
            return "[INFO]"
        case .verbose:
            return "[VERBOSE]"
        case .warning:
            return "[❓WARNING❓]"
        default:
            return "[UNKNOWN]"
        }
    }
}
