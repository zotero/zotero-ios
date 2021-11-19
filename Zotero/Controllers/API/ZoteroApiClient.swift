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

    func send<Request: ApiResponseRequest>(request: Request) -> Single<(Request.Response, HTTPURLResponse)> {
        self.send(request: request, queue: .main)
    }

    func send<Request: ApiResponseRequest>(request: Request, queue: DispatchQueue) -> Single<(Request.Response, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        return self.manager.rx.request(urlRequest: convertible)
                              .validate(acceptableStatusCodes: request.acceptableStatusCodes)
                              .flatMap({ dataRequest -> Observable<(Request.Response, HTTPURLResponse)> in
                                  return dataRequest.rx.responseDataWithResponseError(queue: queue, acceptableStatusCodes: request.acceptableStatusCodes,
                                                                                      encoding: request.encoding, logParams: request.logParams)
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
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        return self.manager.rx.request(urlRequest: convertible)
                              .validate(acceptableStatusCodes: request.acceptableStatusCodes)
                              .flatMap({ dataRequest -> Observable<(Data, HTTPURLResponse)> in
                                  return dataRequest.rx
                                                    .responseDataWithResponseError(queue: queue, acceptableStatusCodes: request.acceptableStatusCodes,
                                                                                   encoding: request.encoding, logParams: request.logParams)
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

    func operation(from request: ApiRequest, queue: DispatchQueue, completion: @escaping (Swift.Result<(HTTPURLResponse, Data?), Error>) -> Void) -> ApiOperation {
        return ApiOperation(apiRequest: request, requestCreator: self, queue: queue, completion: completion)
    }

    func download(request: ApiDownloadRequest) -> Observable<DownloadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        var logData: ApiLogger.StartData?
        return self.manager.rx.download(convertible) { _, _ -> (destinationURL: URL, options: DownloadRequest.Options) in
                                  return (request.downloadUrl, [.createIntermediateDirectories, .removePreviousFile])
                              }
                              .flatMap { downloadRequest in
                                  return Observable.just(downloadRequest.validate(statusCode: request.acceptableStatusCodes))
                              }
                              .do(onNext: { downloadRequest in
                                  downloadRequest.onURLRequestCreation { _request in
                                      logData = ApiLogger.log(urlRequest: _request, encoding: request.encoding, logParams: request.logParams)
                                  }
                              }, onError: { error in
                                  if let data = logData {
                                      ApiLogger.logDownload(result: .failure(error), startData: data)
                                  }
                              }, onCompleted: {
                                  if let data = logData {
                                      ApiLogger.logDownload(result: .success(()), startData: data)
                                  }
                              })

    }

    func upload(request: ApiRequest, data: Data) -> Single<UploadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        let headers = HTTPHeaders(convertible.allHeaders)
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else { return Disposables.create() }
            subscriber(.success(self.manager.upload(data, to: convertible, method: method, headers: headers).validate(statusCode: request.acceptableStatusCodes)))
            return Disposables.create()
        }
    }

    func upload(request: ApiRequest, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<UploadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        return self.manager.rx.upload(multipartFormData: multipartFormData, to: convertible, method: method, headers: HTTPHeaders(convertible.allHeaders))
                              .flatMap({ return Observable.just($0.validate(statusCode: request.acceptableStatusCodes)) })
                              .asSingle()
    }

    func upload(request: ApiRequest, fromFile file: File) -> Single<UploadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        return self.manager.rx.upload(file.createUrl(), to: convertible, method: method, headers: HTTPHeaders(convertible.allHeaders))
                              .flatMap({ return Observable.just($0.validate(statusCode: request.acceptableStatusCodes)) })
                              .asSingle()
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
