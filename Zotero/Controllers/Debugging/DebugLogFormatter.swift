//
//  DebugLogFormatter.swift
//  Zotero
//
//  Created by Michal Rentka on 09/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

protocol DebugLogFormatterDelegate: AnyObject {
    func didFormat(message: String)
}

final class DebugLogFormatter: NSObject, DDLogFormatter {
    private let targetName: String
    private var lastTimestamp: Date?

    weak var delegate: DebugLogFormatterDelegate?

    private lazy var timeExpression: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"^\(\+[0-9]{7}\)"#)
        } catch let error {
            DDLogError("DebugLogFormatter: can't create time expression - \(error)")
            return nil
        }
    }()

    init(targetName: String) {
        self.targetName = targetName
    }

    func format(message logMessage: DDLogMessage) -> String? {
        var message = logMessage.message
        let level = self.logLevelString(from: logMessage.flag)
        let formattedTimeDiff: String

        if let match = self.timeExpression?.firstMatch(in: message, range: NSRange(message.startIndex..., in: message))?.substring(at: 0, in: message).flatMap(String.init) {
            formattedTimeDiff = match
            message = String(message[message.index(message.startIndex, offsetBy: match.count)...])
        } else {
            let timeDiff = (self.lastTimestamp.flatMap({ logMessage.timestamp.timeIntervalSince($0) }) ?? 0) * 1000
            formattedTimeDiff = String(format: "(+%07.0f)", timeDiff)
        }

        self.lastTimestamp = logMessage.timestamp
        let formattedMessage = "\(level) \(self.targetName)\(formattedTimeDiff): \(message). [(\(logMessage.line)) \(logMessage.fileName).\(logMessage.function ?? ""); \(logMessage.queueLabel)]"
        self.delegate?.didFormat(message: formattedMessage)
        return formattedMessage
    }

    private func logLevelString(from level: DDLogFlag) -> String {
        switch level {
        case .debug:
            return "[DEBUG]"

        case .error:
            return "[ERROR]"

        case .info:
            return "[INFO]"

        case .verbose:
            return "[VERBOSE]"

        case .warning:
            return "[WARNING]"

        default:
            return "[UNKNOWN]"
        }
    }
}
