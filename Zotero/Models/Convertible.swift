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

    init(request: ApiRequest, baseUrl: URL, token: String?) {
        switch request.endpoint {
        case .zotero(let path):
            self.url = baseUrl.appendingPathComponent(path)
        case .webDav(let url), .other(let url):
            self.url = url
        }
        self.token = token
        self.httpMethod = request.httpMethod
        self.encoding = request.encoding.alamoEncoding
        self.parameters = request.parameters
        self.headers = request.headers ?? [:]
        self.timeout = request.timeout
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
