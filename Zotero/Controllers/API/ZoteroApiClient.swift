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
import RxAlamofire
import RxSwift

struct ApiConstants {
    static let baseUrlString: String = "https://api.zotero.org/"
    static let version: Int = 3
    static let requestTimeout: Double = 30
    static let resourceTimeout: Double = 14400 // 4 hours
}

enum ZoteroApiError: Error {
    case unchanged
}

final class ZoteroApiClient: ApiClient {
    private let url: URL
    private let manager: Alamofire.Session

    private var token: String?

    init(baseUrl: String, configuration: URLSessionConfiguration) {
        guard let url = URL(string: baseUrl) else {
            fatalError("Incorrect base url provided for ZoteroApiClient")
        }

        self.url = url
        self.manager = Alamofire.Session(configuration: configuration)
    }

    func set(authToken: String?) {
        self.token = authToken
    }

    func send<Request: ApiResponseRequest>(request: Request) -> Single<(Request.Response, HTTPURLResponse)> {
        self.send(request: request, queue: .main)
    }

    func send<Request: ApiResponseRequest>(request: Request, queue: DispatchQueue) -> Single<(Request.Response, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        let startTime = CFAbsoluteTimeGetCurrent()
        return self.manager.rx.request(urlRequest: convertible)
                              .validate(acceptableStatusCodes: request.acceptableStatusCodes)
                              .log(request: request)
                              .flatMap({ dataRequest, logId -> Observable<(Request.Response, HTTPURLResponse)> in
                                  return dataRequest.rx.responseDataWithResponseError(queue: queue, acceptableStatusCodes: request.acceptableStatusCodes)
                                                       .log(identifier: logId, startTime: startTime, request: request)
                                                       .retryIfNeeded()
                                                       .flatMap { response, data -> Observable<(Request.Response, HTTPURLResponse)> in
                                                           do {
                                                               if response.statusCode == 304 {
                                                                   return Observable.error(ZoteroApiError.unchanged)
                                                               }

                                                               let decodedResponse = try JSONDecoder().decode(Request.Response.self, from: data)
                                                               return Observable.just((decodedResponse, response))
                                                           } catch let error {
                                                               return Observable.error(error)
                                                           }
                                                       }
                              })
                              .asSingle()
    }

    func send(request: ApiRequest) -> Single<(Data, HTTPURLResponse)> {
        self.send(request: request, queue: .main)
    }

    func send(request: ApiRequest, queue: DispatchQueue) -> Single<(Data, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        let startTime = CFAbsoluteTimeGetCurrent()
        return self.manager.rx.request(urlRequest: convertible)
                              .validate(acceptableStatusCodes: request.acceptableStatusCodes)
                              .log(request: request)
                              .flatMap({ dataRequest, logId -> Observable<(Data, HTTPURLResponse)> in
                                  return dataRequest.rx.responseDataWithResponseError(queue: queue, acceptableStatusCodes: request.acceptableStatusCodes)
                                                       .log(identifier: logId, startTime: startTime, request: request)
                                                       .retryIfNeeded()
                                                       .flatMap { (response, data) -> Observable<(Data, HTTPURLResponse)> in
                                                           if response.statusCode == 304 {
                                                               return Observable.error(ZoteroApiError.unchanged)
                                                           }
                                                           return Observable.just((data, response))
                                                       }
                              })
                              .asSingle()
    }

    func operation(from request: ApiRequest, queue: DispatchQueue, completion: @escaping (Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void) -> ApiOperation {
        return ApiOperation(apiRequest: request, requestCreator: self, queue: queue, completion: completion)
    }

    func download(request: ApiDownloadRequest) -> Observable<DownloadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return self.manager.rx.download(convertible) { _, _ -> (destinationURL: URL, options: DownloadRequest.Options) in
                                  return (request.downloadUrl, [.createIntermediateDirectories, .removePreviousFile])
                              }
    }

    func upload(request: ApiRequest, data: Data) -> Single<UploadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        let headers = request.headers.flatMap(HTTPHeaders.init)
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else { return Disposables.create() }
            subscriber(.success(self.manager.upload(data, to: convertible, method: method, headers: headers)))
            return Disposables.create()
        }
    }

    func upload(request: ApiRequest, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<UploadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        return self.manager.rx.upload(multipartFormData: multipartFormData, to: convertible, method: method, headers: request.headers.flatMap(HTTPHeaders.init)).asSingle()
    }
}

extension ZoteroApiClient: ApiRequestCreator {
    func dataRequest(for request: ApiRequest) -> DataRequest {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
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
