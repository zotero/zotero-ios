//
//  ApiClient.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import RxSwift

enum ApiParameterEncoding {
    case json
    case url
    case array
    case data
}

enum ApiHttpMethod: String {
    case options  = "OPTIONS"
    case get      = "GET"
    case head     = "HEAD"
    case post     = "POST"
    case put      = "PUT"
    case patch    = "PATCH"
    case delete   = "DELETE"
    case trace    = "TRACE"
    case connect  = "CONNECT"
    case propfind = "PROPFIND"
    case mkcol    = "MKCOL"
}

typealias ResponseHeaders = [AnyHashable: Any]

protocol ApiClient: AnyObject {
    func set(authToken: String?, for endpoint: ApiEndpointType)
    func set(credentials: (String, String)?, for endpoint: ApiEndpointType)
    func send<Request: ApiResponseRequest>(request: Request) -> Single<(Request.Response, HTTPURLResponse)>
    func send<Request: ApiResponseRequest>(request: Request, queue: DispatchQueue) -> Single<(Request.Response, HTTPURLResponse)>
    func send(request: ApiRequest) -> Single<(Data?, HTTPURLResponse)>
    func send(request: ApiRequest, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)>
    func download(request: ApiDownloadRequest, queue: DispatchQueue) -> Observable<DownloadRequest>
    func upload(request: ApiRequest, queue: DispatchQueue, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<(Data?, HTTPURLResponse)>
    func upload(request: ApiRequest, data: Data, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)>
    func upload(request: ApiRequest, fromFile file: File, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)>
    func operation(from request: ApiRequest, queue: DispatchQueue, completion: @escaping (Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void) -> ApiOperation
}

protocol ApiRequestCreator: AnyObject {
    func dataRequest(for request: ApiRequest) -> DataRequest
}
