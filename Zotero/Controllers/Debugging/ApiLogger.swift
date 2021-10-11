//
//  ApiLogger.swift
//  Zotero
//
//  Created by Michal Rentka on 05.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct ApiLogger {
    private static var urlExpression: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"^https?://(?<username>.*):{1}(?<password>.*)@{1}.*$"#)
        } catch let error {
            DDLogError("ApiLogger: can't create url redaction expression - \(error)")
            return nil
        }
    }()

    static func identifier(method: String, url: String) -> String {
        return "HTTP \(method) \(redact(url: url))"
    }

    static func log(request: ApiRequest, url: URL?) -> String {
        let identifier = ApiLogger.identifier(method: request.httpMethod.rawValue, url: url?.absoluteString ?? request.debugUrl)
        DDLogInfo(identifier)
        if request.encoding != .url, let params = request.parameters {
            DDLogInfo("\(request.redact(parameters: params))")
        }
        return identifier
    }

    static func log(result: Result<(HTTPURLResponse, Data), Error>, time: CFAbsoluteTime, identifier: String, request: ApiRequest) {
        switch result {
        case .failure(let error):
            DDLogInfo("\(String(format: "(+%07.0f)", (time * 1000)))\(identifier) failed - \(error)")

        case .success((let response, let data)):
            DDLogInfo("\(String(format: "(+%07.0f)", (time * 1000)))\(identifier) succeeded with \(response.statusCode)")
            // Log only object responses
            if request is ObjectsRequest, let string = String(data: data, encoding: .utf8) {
                DDLogInfo("\(request.redact(response: string))")
            }
        }
    }

    private static func redact(url: String) -> String {
        guard let expression = self.urlExpression,
              let match = expression.matches(in: url, options: [], range: NSRange(url.startIndex..., in: url)).first else { return url }

        var redacted = url
        for name in ["password", "username"] {
            guard let range = Range(match.range(withName: name), in: url) else { continue }
            redacted = redacted.replacingCharacters(in: range, with: "<redacted>")
        }
        return redacted
    }
}
