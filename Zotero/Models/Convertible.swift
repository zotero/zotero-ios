//
//  Convertible.swift
//  Zotero
//
//  Created by Michal Rentka on 22/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire

struct Convertible {
    let url: URL
    private let token: String?
    private let httpMethod: ApiHttpMethod
    private let encoding: ParameterEncoding
    private let parameters: [String: Any]?
    private let headers: [String: String]
    private let timeout: Double

    init(request: ApiRequest, baseUrl: URL, token: String?, additionalHeaders: [AnyHashable: Any]?) {
        switch request.endpoint {
        case .zotero(let path):
            self.url = baseUrl.appendingPathComponent(path)
            self.token = token
            self.headers = Convertible.merge(headers: request.headers ?? [:], with: additionalHeaders)

        case .webDav(let url):
            self.url = url
            self.token = token
            self.headers = Convertible.merge(headers: request.headers ?? [:], with: additionalHeaders)

        case .other(let url):
            self.url = url
            self.token = nil
            self.headers = [:]
        }

        self.httpMethod = request.httpMethod
        self.encoding = request.encoding.alamoEncoding
        self.parameters = request.parameters
        self.timeout = request.timeout
    }

    private static func merge(headers: [String: String], with additional: [AnyHashable: Any]?) -> [String: String] {
        guard let additional, !additional.isEmpty else { return headers }

        let mappedToString = Dictionary(
            additional.map({ key, value -> (String, String) in
                let stringKey = (key as? String) ?? "\(key)"
                let stringValue = (value as? String) ?? "\(value)"
                return (stringKey, stringValue)
            }),
            uniquingKeysWith: { left, _ in left }
        )

        return headers.merging(mappedToString, uniquingKeysWith: { left, _ in left })
    }

    var allHeaders: [String: String] {
        var headers = self.headers
        if let token = self.token {
            headers["Authorization"] = token
        }
        let userAgent = HTTPHeader.defaultUserAgent
        headers[userAgent.name] = userAgent.value
        return headers
    }
}

extension Convertible: URLRequestConvertible {
    func asURLRequest() throws -> URLRequest {
        var request = URLRequest(url: self.url)
        request.timeoutInterval = self.timeout
        request.httpMethod = self.httpMethod.rawValue
        request.allHTTPHeaderFields = self.headers
        if let token = self.token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        let userAgent = HTTPHeader.defaultUserAgent
        request.setValue(userAgent.value, forHTTPHeaderField: userAgent.name)
        return try self.encoding.encode(request as URLRequestConvertible, with: self.parameters)
    }
}

extension Convertible: URLConvertible {
    func asURL() throws -> URL {
        return self.url
    }
}

extension ApiParameterEncoding {
    fileprivate var alamoEncoding: ParameterEncoding {
        switch self {
        case .json:
            return JSONEncoding()

        case .url:
            return URLEncoding()

        case .array:
            return ArrayEncoding()

        case .data:
            return RawDataEncoding()
        }
    }
}
