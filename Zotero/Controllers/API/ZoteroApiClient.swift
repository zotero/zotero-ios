//
//  ZoteroApiClient.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjack
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
}

class ZoteroApiClient: ApiClient {
    private let url: URL
    private let manager: SessionManager

    private var token: String?

    init(baseUrl: String, configuration: URLSessionConfiguration) {
        guard let url = URL(string: baseUrl) else {
            fatalError("Incorrect base url provided for ZoteroApiClient")
        }

        self.url = url
        self.manager = SessionManager(configuration: configuration)
    }

    func set(authToken: String?) {
        self.token = authToken
    }

    func send<Request: ApiResponseRequest>(request: Request) -> Single<(Request.Response, ResponseHeaders)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return self.manager.rx.request(urlRequest: convertible)
                              .validate()
                              .responseDataWithResponseError()
                              .log(request: request, convertible: convertible)
                              .retryIfNeeded()
                              .flatMap { (response, data) -> Observable<(Request.Response, ResponseHeaders)> in
                                  do {
                                      let decodedResponse = try JSONDecoder().decode(Request.Response.self,
                                                                                     from: data)
                                      return Observable.just((decodedResponse, response.allHeaderFields))
                                  } catch let error {
                                      return Observable.error(error)
                                  }
                              }
                              .asSingle()
    }

    func send(request: ApiRequest) -> Single<(Data, ResponseHeaders)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return self.manager.rx.request(urlRequest: convertible)
                              .validate()
                              .responseDataWithResponseError()
                              .log(request: request, convertible: convertible)
                              .retryIfNeeded()
                              .flatMap { (response, data) -> Observable<(Data, [AnyHashable : Any])> in
                                  return Observable.just((data, response.allHeaderFields))
                              }
                              .asSingle()
    }

    func download(request: ApiDownloadRequest) -> Observable<DownloadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return self.manager.rx.download(convertible) { _, _ -> (destinationURL: URL, options: DownloadRequest.DownloadOptions) in
                                  return (request.downloadUrl, [.createIntermediateDirectories, .removePreviousFile])
                              }
    }

    func upload(request: ApiRequest, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<UploadRequest> {
        return Single.create { [weak self] subscriber in
            guard let `self` = self else {
                subscriber(.error(ZoteroApiError.expired))
                return Disposables.create()
            }

            let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)

            let method = HTTPMethod(rawValue: request.httpMethod.rawValue)!
            self.manager.upload(multipartFormData: multipartFormData,
                                to: convertible,
                                method: method,
                                headers: request.headers,
                                encodingCompletion: { result in
                switch result {
                case .success(let request, _, _):
                    subscriber(.success(request))
                case .failure(let error):
                    subscriber(.error(error))
                }
            })

            return Disposables.create()
        }
    }
}
