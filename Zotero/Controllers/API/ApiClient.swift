//
//  ApiClient.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

enum ApiParameterEncoding {
    case json, url
}

enum ApiHttpMethod: String {
    case options = "OPTIONS"
    case get     = "GET"
    case head    = "HEAD"
    case post    = "POST"
    case put     = "PUT"
    case patch   = "PATCH"
    case delete  = "DELETE"
    case trace   = "TRACE"
    case connect = "CONNECT"
}

protocol ApiRequest {
    associatedtype Response: Decodable

    var path: String { get }
    var httpMethod: ApiHttpMethod { get }
    var parameters: [String: Any]? { get }
    var encoding: ApiParameterEncoding { get }
}

typealias RequestCompletion<Response> = (Result<Response>) -> Void

protocol ApiClient: class {
    func set(authToken: String?)
    func send<Request: ApiRequest>(request: Request,
                                   completion: @escaping RequestCompletion<Request.Response>)
    func send<Request: ApiRequest>(request: Request) -> Single<Request.Response>
}
