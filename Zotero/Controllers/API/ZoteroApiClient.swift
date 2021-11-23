//
//  ZoteroApiClient.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RxSwift

struct ApiConstants {
    static let baseUrlString: String = "https://api.zotero.org/"
    static let version: Int = 3
    static let requestTimeout: Double = 30
    static let resourceTimeout: Double = 14400 // 4 hours
}

enum ZoteroApiError: Error {
    case unchanged
    case responseMissing(String)
}

final class ZoteroApiClient: ApiClient {
    private let url: URL
    private let manager: Alamofire.Session

    private var tokens: [ApiEndpointType: String]

    init(baseUrl: String, configuration: URLSessionConfiguration) {
        guard let url = URL(string: baseUrl) else {
            fatalError("Incorrect base url provided for ZoteroApiClient")
        }

        self.url = url
        self.manager = Alamofire.Session(configuration: configuration)
        self.tokens = [:]
    }

    func token(for endpoint: ApiEndpointType) -> String? {
        return self.tokens[endpoint]
    }

    func set(authToken: String?, for endpoint: ApiEndpointType) {
        self.tokens[endpoint] = authToken
    }

    /// Creates and starts a data request, takes care of retrying request in case of failure. Responds on main queue.
    func send(request: ApiRequest) -> Single<(Data?, HTTPURLResponse)> {
        self.send(request: request, queue: .main)
    }

    /// Creates and starts a data request, takes care of retrying request in case of failure.
    func send(request: ApiRequest, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        return self.createRequest { $0.request(convertible).validate(acceptableStatusCodes: request.acceptableStatusCodes) }
                   .flatMap({ (dataRequest: DataRequest) -> Single<(Data?, HTTPURLResponse)> in
                       return dataRequest.rx.loggedResponseDataWithResponseError(queue: queue, encoding: request.encoding, logParams: request.logParams)
                                         .retryIfNeeded()
                                         .asSingle()
                                         .flatMap { data, response -> Single<(Data?, HTTPURLResponse)> in
                                             if response.statusCode == 304 {
                                                 return Single.error(ZoteroApiError.unchanged)
                                             }
                                             return Single.just((data, response))
                                         }
                   })
    }

    /// Creates, starts a data request and encodes response. Takes care of retrying request in case of failure. Responds on main queue.
    func send<Request: ApiResponseRequest>(request: Request) -> Single<(Request.Response, HTTPURLResponse)> {
        self.send(request: request, queue: .main)
    }

    /// Creates, starts a data request and encodes response. Takes care of retrying request in case of failure.
    func send<Request: ApiResponseRequest>(request: Request, queue: DispatchQueue) -> Single<(Request.Response, HTTPURLResponse)> {
        return self.send(request: request, queue: queue)
                   .mapData(httpMethod: request.httpMethod.rawValue)
                   .flatMap { data, response -> Single<(Request.Response, HTTPURLResponse)> in
                       do {
                            let decodedResponse = try JSONDecoder().decode(Request.Response.self, from: data)
                            return Single.just((decodedResponse, response))
                        } catch let error {
                            return Single.error(error)
                        }
                   }
    }

    /// Creates ApiOperation which performs request.
    func operation(from request: ApiRequest, queue: DispatchQueue, completion: @escaping (Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void) -> ApiOperation {
        return ApiOperation(apiRequest: request, requestCreator: self, queue: queue, completion: completion)
    }

    /// Creates download request. Request needs to be started manually.
    func download(request: ApiDownloadRequest, queue: DispatchQueue) -> Observable<DownloadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        return self.createRequest { manager -> DownloadRequest in
                       return manager.download(convertible) { _, _ in (request.downloadUrl, [.createIntermediateDirectories, .removePreviousFile]) }
                                     .validate(statusCode: request.acceptableStatusCodes)
                   }
                   .asObservable()
                   .flatMap { downloadRequest -> Observable<DownloadRequest> in
                       return downloadRequest.rx.loggedResponseWithResponseError(queue: queue, encoding: request.encoding, logParams: request.logParams)
                   }
    }

    func upload(request: ApiRequest, data: Data, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        let headers = HTTPHeaders(convertible.allHeaders)
        return self.createUploadRequest(request: request, queue: queue) { $0.upload(data, to: convertible, method: method, headers: headers) }
    }

    func upload(request: ApiRequest, queue: DispatchQueue, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<(Data?, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        let headers = HTTPHeaders(convertible.allHeaders)
        return self.createUploadRequest(request: request, queue: queue) { $0.upload(multipartFormData: multipartFormData, to: convertible, method: method, headers: headers) }
    }

    func upload(request: ApiRequest, fromFile file: File, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        let headers = HTTPHeaders(convertible.allHeaders)
        return self.createUploadRequest(request: request, queue: queue) { $0.upload(file.createUrl(), to: convertible, method: method, headers: headers) }
    }

    private func createUploadRequest(request: ApiRequest, queue: DispatchQueue, create: @escaping (Alamofire.Session) -> UploadRequest) -> Single<(Data?, HTTPURLResponse)> {
        return self.createRequest { create($0).validate(acceptableStatusCodes: request.acceptableStatusCodes) }
                   .flatMap({ uploadRequest -> Single<(Data?, HTTPURLResponse)> in
                       return uploadRequest.rx.loggedResponseDataWithResponseError(queue: queue, encoding: request.encoding, logParams: request.logParams)
                                           .retryIfNeeded()
                                           .asSingle()
                                           .flatMap { data, response -> Single<(Data?, HTTPURLResponse)> in
                                               if response.statusCode == 304 {
                                                   return Single.error(ZoteroApiError.unchanged)
                                               }
                                               return Single.just((data, response))
                                           }
                   })
    }

    private func createRequest<R: Request>(create: @escaping (Alamofire.Session) -> R) -> Single<R> {
        return Single.create { subscriber in
            let alamoRequest = create(self.manager)
            subscriber(.success(alamoRequest))
            return Disposables.create()
        }
    }

    private func token(for endpoint: ApiEndpoint) -> String? {
        let endpointType: ApiEndpointType
        switch endpoint {
        case .zotero:
            endpointType = .zotero
        case .webDav:
            endpointType = .webDav
        case .other:
            endpointType = .other
        }
        return self.tokens[endpointType]
    }
}

extension ZoteroApiClient: ApiRequestCreator {
    func dataRequest(for request: ApiRequest) -> DataRequest {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        return self.manager.request(convertible).validate(acceptableStatusCodes: request.acceptableStatusCodes)
    }
}

extension ResponseHeaders {
    var lastModifiedVersion: Int {
        // Workaround for broken headers (stored in case-sensitive dictionary)
        return ((self["Last-Modified-Version"] as? String) ??
                (self["last-modified-version"] as? String)).flatMap(Int.init) ?? 0
    }
}
