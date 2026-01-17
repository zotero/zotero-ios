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

private enum ApiAuthType {
    case authHeader(String)
    case credentials(username: String, password: String)

    var authHeader: String? {
        switch self {
        case .authHeader(let header):
            return header
        
        case .credentials(let username, let password):
            guard let base64Encoded = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() else { return nil }
            return "Basic \(base64Encoded)"
        }
    }

    var credentials: (username: String, password: String)? {
        switch self {
        case .credentials(let username, let password):
            return (username, password)

        case .authHeader:
            return nil
        }
    }
}

final class ZoteroApiClient: ApiClient {
    private let url: URL
    private let manager: Alamofire.Session
    private let sessionDelegate = ZoteroSessionDelegate()

    private var token: ApiAuthType?
    
    var onTrustChallenge: ((SecTrust, String, @escaping (Bool) -> Void) -> Void)? {
        get { sessionDelegate.onTrustChallenge }
        set { sessionDelegate.onTrustChallenge = newValue }
    }

    init(baseUrl: String, configuration: URLSessionConfiguration) {
        guard let url = URL(string: baseUrl) else {
            fatalError("Incorrect base url provided for ZoteroApiClient")
        }

        self.url = url
        self.manager = Alamofire.Session(configuration: configuration, delegate: sessionDelegate)
    }

    func set(authToken: String?) {
        token = authToken.flatMap({ .authHeader($0) })
    }

    func set(credentials: (String, String)?) {
        guard let (username, password) = credentials else {
            token = nil
            return
        }
        token = .credentials(username: username, password: password)
    }

    /// Creates and starts a data request, takes care of retrying request in case of failure. Responds on main queue.
    func send(request: ApiRequest) -> Single<(Data?, HTTPURLResponse)> {
        self.send(request: request, queue: .main)
    }

    /// Creates and starts a data request, takes care of retrying request in case of failure.
    func send(request: ApiRequest, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: token?.authHeader, additionalHeaders: self.manager.sessionConfiguration.httpAdditionalHeaders)
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

    /// Creates download request. Request needs to be started manually.
    func download(request: ApiDownloadRequest, queue: DispatchQueue) -> Observable<DownloadRequest> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: token?.authHeader, additionalHeaders: self.manager.sessionConfiguration.httpAdditionalHeaders)
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
        let convertible = Convertible(request: request, baseUrl: self.url, token: token?.authHeader, additionalHeaders: self.manager.sessionConfiguration.httpAdditionalHeaders)
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        let headers = HTTPHeaders(convertible.allHeaders)
        return self.createUploadRequest(request: request, queue: queue) { $0.upload(data, to: convertible, method: method, headers: headers) }
    }

    func upload(request: ApiRequest, queue: DispatchQueue, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<(Data?, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: token?.authHeader, additionalHeaders: self.manager.sessionConfiguration.httpAdditionalHeaders)
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        let headers = HTTPHeaders(convertible.allHeaders)
        return self.createUploadRequest(request: request, queue: queue) { $0.upload(multipartFormData: multipartFormData, to: convertible, method: method, headers: headers) }
    }

    func upload(request: ApiRequest, fromFile file: File, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: token?.authHeader, additionalHeaders: self.manager.sessionConfiguration.httpAdditionalHeaders)
        let method = HTTPMethod(rawValue: request.httpMethod.rawValue)
        let headers = HTTPHeaders(convertible.allHeaders)
        return self.createUploadRequest(request: request, queue: queue) { $0.upload(file.createUrl(), to: convertible, method: method, headers: headers) }
    }

    func urlRequest(from request: ApiRequest) throws -> URLRequest {
        let convertible = Convertible(request: request, baseUrl: url, token: token?.authHeader, additionalHeaders: manager.sessionConfiguration.httpAdditionalHeaders)
        return try convertible.asURLRequest()
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
        return Single.create { [weak self] subscriber in
            guard let self else {
                return Disposables.create()
            }
            var alamoRequest = create(manager)
            if let credentials = token?.credentials {
                alamoRequest = alamoRequest.authenticate(username: credentials.username, password: credentials.password)
            }
            subscriber(.success(alamoRequest))
            return Disposables.create()
        }
    }
}

extension ResponseHeaders {
    var lastModifiedVersion: Int {
        // Workaround for broken headers (stored in case-sensitive dictionary)
        return (self.value(forCaseInsensitive: "last-modified-version") as? String).flatMap(Int.init) ?? 0
    }
}

/// Delegates URLSession challenges to handle server trust validation for WebDAV connections.
///
/// This delegate intercepts server trust challenges and allows the application to implement
/// certificate pinning for WebDAV servers with self-signed or untrusted certificates.
///
/// **Certificate Trust Flow:**
/// 1. Server presents certificate during TLS handshake
/// 2. System finds certificate untrusted (not in system trust store)
/// 3. URLSession calls this delegate with server trust challenge
/// 4. Delegate invokes `onTrustChallenge` callback (typically shows UI to user)
/// 5. User decides whether to trust the certificate
/// 6. If trusted, certificate is pinned for future validation
/// 7. Connection proceeds with accepted credential
///
/// **Thread Safety (@unchecked Sendable):**
/// This class is marked as @unchecked Sendable because:
/// - Inherits from Alamofire's SessionDelegate which manages internal synchronization
/// - `onTrustChallenge` closure access is protected by NSLock for thread-safe reads/writes
/// - URLSession guarantees delegate methods are called serially (not concurrently)
/// - Challenge timeout uses thread-safe DispatchQueue.global() + NSLock
/// - Completion handlers are designed for concurrent invocation (with lock protection)
///
/// **Timeout Protection:** 60-second timeout prevents indefinite hangs if UI doesn't respond.
class ZoteroSessionDelegate: SessionDelegate, @unchecked Sendable {
    private var _onTrustChallenge: ((SecTrust, String, @escaping (Bool) -> Void) -> Void)?
    private let trustChallengeLock = NSLock()
    private let challengeTimeout: TimeInterval = 60.0
    
    var onTrustChallenge: ((SecTrust, String, @escaping (Bool) -> Void) -> Void)? {
        get {
            trustChallengeLock.lock()
            defer { trustChallengeLock.unlock() }
            return _onTrustChallenge
        }
        set {
            trustChallengeLock.lock()
            defer { trustChallengeLock.unlock() }
            _onTrustChallenge = newValue
        }
    }

    // SESSION-LEVEL CHALLENGE: Handle challenges at the session level
    // Some servers trigger session-level challenges before task-level challenges
    // Note: Not overriding - implementing URLSessionDelegate protocol method directly
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           let host = challenge.protectionSpace.host as String?,
           onTrustChallenge != nil {
            handleTrustChallenge(trust: trust, host: host, completionHandler: completionHandler)
            return
        }
        
        completionHandler(.performDefaultHandling, nil)
    }
    
    // TASK-LEVEL CHALLENGE: Handle challenges at the task level
    // This is called for authentication challenges and is the primary entry point for certificate validation
    override func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // CERTIFICATE PINNING ENTRY POINT: Intercept server trust challenges
        // This is the first point where we can validate server certificates
        // before establishing the connection
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           let host = challenge.protectionSpace.host as String?,
           onTrustChallenge != nil {
            // Call the handler - it will decide whether to handle this host or reject
            handleTrustChallenge(trust: trust, host: host, completionHandler: completionHandler)
            return
        }

        // DELEGATE FORWARDING: Use default handling for all other cases
        // This includes non-trust challenges and trust challenges when no handler is set
        completionHandler(.performDefaultHandling, nil)
    }
    
    // SHARED CHALLENGE HANDLER: Common logic for both session and task-level challenges
    // Handles certificate trust with timeout protection and user callback
    // The handler itself decides whether to handle this host or reject
    private func handleTrustChallenge(trust: SecTrust, host: String, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let onTrustChallenge = onTrustChallenge else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        var completed = false
        let lock = NSLock()
        
        // TIMEOUT PROTECTION: Prevent indefinite hangs if UI doesn't respond
        // After 60 seconds, automatically reject the challenge to prevent resource leaks
        DispatchQueue.global().asyncAfter(deadline: .now() + challengeTimeout) {
            lock.lock()
            defer { lock.unlock() }
            if !completed {
                completed = true
                DDLogWarn("ZoteroSessionDelegate: trust challenge timed out for \(host)")
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
        
        // CALLBACK TO UI: Let application decide whether to trust this certificate
        // The handler can reject by returning false if the host doesn't match its configuration
        onTrustChallenge(trust, host) { shouldTrust in
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            
            if shouldTrust {
                // HANDLER ACCEPTED: Certificate will be pinned by WebDavController
                // Return credential to proceed with connection
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                // HANDLER REJECTED: Fall back to default handling
                // This happens when host doesn't match WebDAV configuration or user rejected
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
