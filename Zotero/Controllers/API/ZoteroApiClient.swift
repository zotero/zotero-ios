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
}

enum ZoteroApiError: Error {
    case unknown
    case expired
    case unknownItemType(String)
    case jsonDecoding(Error)
    case unchanged(version: Int)
}

class ZoteroApiClient: ApiClient {
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

    func send<Request: ApiResponseRequest>(request: Request) -> Single<(Request.Response, ResponseHeaders)> {
        self.send(request: request, queue: .main)
    }

    func send<Request: ApiResponseRequest>(request: Request, queue: DispatchQueue) -> Single<(Request.Response, ResponseHeaders)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return self.manager.rx.request(urlRequest: convertible)
                              .validate()
                              .responseDataWithResponseError(queue: queue)
                              .log(request: request, url: convertible.url)
                              .retryIfNeeded()
                              .flatMap { (response, data) -> Observable<(Request.Response, ResponseHeaders)> in
                                  do {
                                      if response.statusCode == 304 {
                                          let version = request.headers?["If-Modified-Since-Version"].flatMap(Int.init) ?? 0
                                          return Observable.error(ZoteroApiError.unchanged(version: version))
                                      }

                                      let decodedResponse = try JSONDecoder().decode(Request.Response.self, from: data)
                                      return Observable.just((decodedResponse, response.allHeaderFields))
                                  } catch let error {
                                      return Observable.error(error)
                                  }
                              }
                              .asSingle()
    }

    func send(request: ApiRequest) -> Single<(Data, ResponseHeaders)> {
        self.send(request: request, queue: .main)
    }

    func send(request: ApiRequest, queue: DispatchQueue) -> Single<(Data, ResponseHeaders)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return self.manager.rx.request(urlRequest: convertible)
                              .validate()
                              .responseDataWithResponseError(queue: queue)
                              .log(request: request, url: convertible.url)
                              .retryIfNeeded()
                              .flatMap { (response, data) -> Observable<(Data, [AnyHashable : Any])> in
                                  if response.statusCode == 304 {
                                      let version = response.allHeaderFields.lastModifiedVersion
                                      return Observable.error(ZoteroApiError.unchanged(version: version))
                                  }

                                  return Observable.just((data, response.allHeaderFields))
                              }
                              .asSingle()
    }

    func operation(from request: ApiRequest, queue: DispatchQueue, completion: @escaping (Swift.Result<(Data, ResponseHeaders), Error>) -> Void) -> ApiOperation {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return ApiOperation(request: self.manager.request(convertible).validate(), apiRequest: request, queue: queue, completion: completion)
    }

    func download(request: ApiDownloadRequest) -> Observable<DownloadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return self.manager.rx.download(convertible) { _, _ -> (destinationURL: URL, options: DownloadRequest.Options) in
                                  return (request.downloadUrl, [.createIntermediateDirectories, .removePreviousFile])
                              }
    }

    func upload(request: ApiRequest, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<UploadRequest> {
        self.upload(request: request, queue: .main, multipartFormData: multipartFormData)
    }

    func upload(request: ApiRequest, queue: DispatchQueue, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<UploadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        return self.manager.rx.upload(multipartFormData: multipartFormData,
                                      to: convertible,
                                      method: method,
                                      headers: request.headers.flatMap(HTTPHeaders.init))
                              .asSingle()
    }
}

extension ResponseHeaders {
    var lastModifiedVersion: Int {
        // Workaround for broken headers (stored in case-sensitive dictionary)
        return ((self["Last-Modified-Version"] as? String) ??
                (self["last-modified-version"] as? String)).flatMap(Int.init) ?? 0
    }
}
