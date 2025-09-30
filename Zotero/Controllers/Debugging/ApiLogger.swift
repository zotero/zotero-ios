//
//  ApiLogger.swift
//  Zotero
//
//  Created by Michal Rentka on 05.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift

struct ApiLogger {
    struct StartData {
        let id: String
        let time: CFAbsoluteTime
        let logParams: ApiLogParameters
    }

    private static var urlExpression: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"^https?://(?<username>.*):{1}(?<password>.*)@{1}.*$"#)
        } catch let error {
            DDLogError("ApiLogger: can't create url redaction expression - \(error)")
            return nil
        }
    }()

    private static var passwordExpression: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #""password":"(?<password>.*?)""#)
        } catch let error {
            DDLogError("ApiLogger: can't create password redaction expression - \(error)")
            return nil
        }
    }()

    // MARK: - Logging

    static func log(urlRequest: URLRequest, encoding: ApiParameterEncoding, logParams: ApiLogParameters) -> StartData {
        let identifier = self.logRequestIdentifier(urlRequest: urlRequest, logParams: logParams)
        self.logRequestBody(urlRequest: urlRequest, encoding: encoding, logParams: logParams)

        if logParams.contains(.headers), let headers = urlRequest.allHTTPHeaderFields {
            self.log(headers: headers)
        }

        return StartData(id: identifier, time: CFAbsoluteTimeGetCurrent(), logParams: logParams)
    }

    static func logSuccessfulResponse(statusCode: Int, data: Data?, headers: [AnyHashable: Any]?, startData: StartData) {
        self.logResponseIdentifier(statusCode: statusCode, success: true, startData: startData)

        if startData.logParams.contains(.headers) {
            self.log(headers: headers ?? [:])
        }
        // TODO: Fix crashing log
//        if startData.logParams.contains(.response), let data, let string = String(data: data, encoding: .utf8) {
//            DDLogInfo(DDLogMessageFormat(stringLiteral: string))
        if startData.logParams.contains(.response), let data, String(data: data, encoding: .utf8) != nil {
            DDLogInfo(DDLogMessageFormat(stringLiteral: "Response omitted due to crashing bug"))
        }
    }

    static func logFailedresponse(error: AFResponseError, statusCode: Int, startData: StartData) {
        self.logResponseIdentifier(statusCode: statusCode, success: false, startData: startData)

        if startData.logParams.contains(.headers) {
            self.log(headers: error.headers ?? [:])
        }

        if error.response.isEmpty || error.response == "No Response" {
            DDLogError("\(error.error)")
        } else {
            DDLogError("\(error.response) - \(error.error)")
        }
    }

    static func logFailedresponse(error: Error, headers: [String: Any]?, statusCode: Int, startData: StartData) {
        self.logResponseIdentifier(statusCode: statusCode, success: false, startData: startData)

        if startData.logParams.contains(.headers) {
            self.log(headers: headers ?? [:])
        }

        DDLogError("\(error)")
    }

    // MARK: - Helpers

    static func identifier(method: String, url: String) -> String {
        return "HTTP \(method) \(redact(url: url))"
    }

    private static func logRequestIdentifier(urlRequest: URLRequest, logParams: ApiLogParameters) -> String {
        let method = urlRequest.httpMethod ?? "-"
        let url = urlRequest.url?.absoluteString ?? "-"
        let identifier = ApiLogger.identifier(method: method, url: url)
        DDLogInfo(DDLogMessageFormat(stringLiteral: identifier))
        return identifier
    }

    private static func logResponseIdentifier(statusCode: Int, success: Bool, startData: StartData) {
        let timeString: String
        if startData.time == 0 {
            timeString = "+0000000"
        } else {
            let time = CFAbsoluteTimeGetCurrent() - startData.time
            timeString = String(format: "(+%07.0f)", (time * 1000))
        }
        DDLogInfo("\(timeString)\(startData.id) \(success ? "succeeded" : "failed") with \(statusCode)")
    }

    private static func logRequestBody(urlRequest: URLRequest, encoding: ApiParameterEncoding, logParams: ApiLogParameters) {
        switch encoding {
        case .json, .array:
            if let data = urlRequest.httpBody, let string = String(data: data, encoding: .utf8) {
                let message = DDLogMessageFormat(stringLiteral: self.redact(parameters: string))
                DDLogInfo(message)
            }

        case .data:
            if let data = urlRequest.httpBody {
                DDLogInfo("Data: \(data.count) bytes")
            }

        case .url: return
        }
    }

    private static func log(headers: [AnyHashable: Any]) {
        guard !headers.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: self.redact(headers: headers), options: .prettyPrinted),
              let string = String(data: data, encoding: .utf8) else { return }
        DDLogInfo(DDLogMessageFormat(stringLiteral: string))
    }

    // MARK: - Redacting

    private static func redact(headers: [AnyHashable: Any]) -> [AnyHashable: Any] {
        #if DEBUG
        return headers
        #else
        var redacted = headers
        if headers["Zotero-API-Key"] != nil {
            redacted["Zotero-API-Key"] = "<redacted>"
        }
        if headers["Authorization"] != nil {
            redacted["Authorization"] = "<redacted>"
        }
        return redacted
        #endif
    }

    private static func redact(url: String) -> String {
        #if DEBUG
        return url
        #else
        return url.redact(with: self.urlExpression, groups: ["password", "username"])
        #endif
    }

    private static func redact(parameters: String) -> String {
        #if DEBUG
        return parameters
        #else
        return parameters.redact(with: self.passwordExpression, groups: ["password"])
        #endif
    }
}

extension String {
    fileprivate func redact(with expression: NSRegularExpression?, groups: [String]) -> String {
        guard !groups.isEmpty,
              let expression = expression,
              let match = expression.matches(in: self, options: [], range: NSRange(self.startIndex..., in: self)).first else { return self }

        var redacted = self
        for name in groups {
            guard let range = Range(match.range(withName: name), in: self) else { continue }
            redacted = redacted.replacingCharacters(in: range, with: "<redacted>")
        }
        return redacted
    }
}
