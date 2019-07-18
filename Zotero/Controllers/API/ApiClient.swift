//
//  ApiClient.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import RxAlamofire
import RxSwift

enum ApiParameterEncoding {
    case json, url, array
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
    var path: String { get }
    var httpMethod: ApiHttpMethod { get }
    var parameters: [String: Any]? { get }
    var encoding: ApiParameterEncoding { get }
    var headers: [String: String]? { get }
}

protocol ApiResponseRequest: ApiRequest {
    associatedtype Response: Decodable
}

protocol ApiDownloadRequest: ApiRequest {
    var downloadUrl: URL { get }
}

protocol ApiUploadRequest {
    var url: URL { get }
    var httpMethod: ApiHttpMethod { get }
    var headers: [String: String]? { get }
}

typealias RequestCompletion<Response> = (Swift.Result<Response, Error>) -> Void
typealias ResponseHeaders = [AnyHashable: Any]

protocol ApiClient: class {
    func set(authToken: String?)
    func send<Request: ApiResponseRequest>(request: Request) -> Single<(Request.Response, ResponseHeaders)>
    func send(dataRequest: ApiRequest) -> Single<(Data, ResponseHeaders)>
    func download(request: ApiDownloadRequest) -> Observable<RxProgress>
    func upload(request: ApiUploadRequest, multipartFormData: @escaping (MultipartFormData) -> Void) -> Observable<UploadRequest>
}
