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

fileprivate enum ApiAuthType {
    case authHeader(String)
    case credentials(username: String, password: String)

    var authHeader: String? {
        switch self {
        case .authHeader(let header): return header
        case .credentials: return nil
        }
    }

    var credentials: (username: String, password: String)? {
        switch self {
        case .credentials(let username, let password): return (username, password)
        case .authHeader: return nil
        }
    }
}

final class ZoteroApiClient: ApiClient {
    private let url: URL
    private let manager: Alamofire.Session

    private var tokens: [ApiEndpointType: ApiAuthType]

    init(baseUrl: String, configuration: URLSessionConfiguration, includeCredentialDelegate: Bool = false) {
        guard let url = URL(string: baseUrl) else {
            fatalError("Incorrect base url provided for ZoteroApiClient")
        }

        self.url = url
        let delegate = includeCredentialDelegate ? CredentialSessionDelegate() : SessionDelegate()
        self.manager = Alamofire.Session(configuration: configuration, delegate: delegate)
        self.tokens = [:]
    }

    func set(authToken: String?, for endpoint: ApiEndpointType) {
        self.tokens[endpoint] = authToken.flatMap({ .authHeader($0) })
    }

    func set(credentials: (String, String)?, for endpoint: ApiEndpointType) {
        if let credentials = credentials {
            self.tokens[endpoint] = .credentials(username: credentials.0, password: credentials.1)
            (self.manager.delegate as? CredentialSessionDelegate)?.credential = URLCredential(user: credentials.0, password: credentials.1, persistence: .forSession)
        } else {
            self.tokens[endpoint] = nil
        }
    }

    /// Creates and starts a data request, takes care of retrying request in case of failure. Responds on main queue.
    func send(request: ApiRequest) -> Single<(Data?, HTTPURLResponse)> {
        self.send(request: request, queue: .main)
    }

    /// Creates and starts a data request, takes care of retrying request in case of failure.
    func send(request: ApiRequest, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        return self.createRequestSingle(for: request.endpoint) { $0.request(convertible).validate(acceptableStatusCodes: request.acceptableStatusCodes) }
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
        return self.createRequestSingle(for: request.endpoint) { manager -> DownloadRequest in
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
        return self.createRequestSingle(for: request.endpoint) { create($0).validate(acceptableStatusCodes: request.acceptableStatusCodes) }
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

    private func createRequestSingle<R: Request>(for endpoint: ApiEndpoint, create: @escaping (Alamofire.Session) -> R) -> Single<R> {
        return Single.create { subscriber in
            let alamoRequest = self.createRequest(for: endpoint, create: create)
            subscriber(.success(alamoRequest))
            return Disposables.create()
        }
    }

    private func createRequest<R: Request>(for endpoint: ApiEndpoint, create: @escaping (Alamofire.Session) -> R) -> R {
        var alamoRequest = create(self.manager)
        if let credentials = self.tokens[self.endpointType(for: endpoint)]?.credentials {
            alamoRequest = alamoRequest.authenticate(username: credentials.username, password: credentials.password)
        }
        return alamoRequest
    }

    private func endpointType(for endpoint: ApiEndpoint) -> ApiEndpointType {
        switch endpoint {
        case .zotero:
            return .zotero
        case .webDav:
            return .webDav
        case .other:
            return .other
        }
    }

    private func token(for endpoint: ApiEndpoint) -> String? {
        return self.tokens[self.endpointType(for: endpoint)]?.authHeader
    }
}

extension ZoteroApiClient: ApiRequestCreator {
    func dataRequest(for request: ApiRequest) -> DataRequest {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token(for: request.endpoint))
        return self.createRequest(for: request.endpoint) { $0.request(convertible).validate(acceptableStatusCodes: request.acceptableStatusCodes) }
    }
}

extension ResponseHeaders {
    var lastModifiedVersion: Int {
        // Workaround for broken headers (stored in case-sensitive dictionary)
        return (self.value(forCaseInsensitive: "last-modified-version") as? String).flatMap(Int.init) ?? 0
    }
}

fileprivate final class CredentialSessionDelegate: SessionDelegate {
    var credential: URLCredential?

    override func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.previousFailureCount == 0 else {
            completionHandler(.rejectProtectionSpace, nil)
            return
        }

        if let credential = self.credential {
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
