//
//  ApiRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19.11.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DefaultStatusCodes {
    static let acceptable: Set<Int> = Set(200..<300).union([304])
}

protocol ApiRequest {
    var endpoint: ApiEndpoint { get }
    var httpMethod: ApiHttpMethod { get }
    var parameters: [String: Any]? { get }
    var encoding: ApiParameterEncoding { get }
    var headers: [String: String]? { get }
    var debugUrl: String { get }
    var acceptableStatusCodes: Set<Int> { get }
    var logParams: ApiLogParameters { get }
    var timeout: Double { get }
}

extension ApiRequest {
    var timeout: Double {
        return ApiConstants.requestTimeout
    }
}

extension ApiRequest {
    var acceptableStatusCodes: Set<Int> {
        return DefaultStatusCodes.acceptable
    }

    var debugUrl: String {
        switch self.endpoint {
        case .zotero(let path):
            return ApiConstants.baseUrlString + path

        case .other(let url), .webDav(let url):
            return url.absoluteString
        }
    }

    var logParams: ApiLogParameters {
        return []
    }
}

protocol ApiResponseRequest: ApiRequest {
    associatedtype Response: Decodable
}

protocol ApiDownloadRequest: ApiRequest {
    var downloadUrl: URL { get }
}
