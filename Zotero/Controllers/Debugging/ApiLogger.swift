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
    static func identifier(method: String, url: String) -> String {
        return "HTTP \(method) \(url)"
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
}
