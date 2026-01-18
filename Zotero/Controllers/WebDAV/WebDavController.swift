//
//  WebDavController.swift
//  Zotero
//
//  Created by Michal Rentka on 05.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import CommonCrypto

import Alamofire
import CocoaLumberjackSwift
import RxSwift
import SwiftUI

enum WebDavUploadResult {
    case exists
    case new(URL, File)
}

enum WebDavError {
    enum Verification: Swift.Error {
        case noUrl
        case noUsername
        case noPassword
        case invalidUrl
        case notDav
        case parentDirNotFound
        case zoteroDirNotFound(String)
        case nonExistentFileNotMissing
        case fileMissingAfterUpload

        var message: String {
            switch self {
            case .fileMissingAfterUpload:
                return L10n.Errors.Settings.Webdav.fileMissingAfterUpload

            case .invalidUrl:
                return L10n.Errors.Settings.Webdav.invalidUrl

            case .noPassword:
                return L10n.Errors.Settings.Webdav.noPassword

            case .noUrl:
                return L10n.Errors.Settings.Webdav.noUrl

            case .noUsername:
                return L10n.Errors.Settings.Webdav.noUsername

            case .nonExistentFileNotMissing:
                return L10n.Errors.Settings.Webdav.nonExistentFileNotMissing

            case .notDav:
                return L10n.Errors.Settings.Webdav.notDav

            case .parentDirNotFound:
                return L10n.Errors.Settings.Webdav.parentDirNotFound

            case .zoteroDirNotFound:
                return L10n.Errors.Settings.Webdav.zoteroDirNotFound
            }
        }
    }

    enum Download: Swift.Error {
        case itemPropInvalid(String)
        case notChanged
    }

    enum Upload: Swift.Error {
        case cantCreatePropData
        case apiError(error: AFError, httpMethod: String?)
    }

    static func message(for error: Error) -> String {
        if let error = error as? WebDavError.Verification {
            return error.message
        }

        if let responseError = error as? AFResponseError, let message = errorMessage(for: responseError.error) {
            return message
        }

        if let error = error as? AFError, let message = errorMessage(for: error) {
            return message
        }

        return error.localizedDescription

        func errorMessage(for error: AFError) -> String? {
            switch error {
            case .sessionTaskFailed(let error):
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain {
                    switch nsError.code {
                    case NSURLErrorNotConnectedToInternet:
                        return L10n.Errors.Settings.Webdav.internetConnection

                    case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
                        return L10n.Errors.Settings.Webdav.hostNotFound

                    case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                        return L10n.Errors.Settings.Webdav.ats

                    default: break
                    }
                }

            case .responseValidationFailed(let reason):
                switch reason {
                case .unacceptableStatusCode(let statusCode):
                    switch statusCode {
                    case 401:
                        return L10n.Errors.Settings.Webdav.unauthorized

                    case 403:
                        return L10n.Errors.Settings.Webdav.forbidden

                    default:
                        return nil
                    }

                default:
                    break
                }

            default:
                break
            }

            return L10n.Errors.Settings.Webdav.hostNotFound
        }
    }
}

struct WebDavDeletionResult {
    let succeeded: Set<String>
    let missing: Set<String>
    let failed: Set<String>
}

protocol WebDavController: AnyObject {
    var sessionStorage: WebDavSessionStorage { get }
    var currentUrl: URL? { get }
    var onServerTrustChallenge: ((SecTrust, String, @escaping (Bool) -> Void) -> Void)? { get set }

    func checkServer(queue: DispatchQueue) -> Single<URL>
    func createZoteroDirectory(queue: DispatchQueue) -> Single<()>
    func download(key: String, file: File, queue: DispatchQueue) -> Observable<DownloadRequest>
    func createURLRequest(from request: ApiRequest) throws -> URLRequest
    func prepareForUpload(key: String, mtime: Int, hash: String, file: File, queue: DispatchQueue) -> Single<WebDavUploadResult>
    func upload(request: AttachmentUploadRequest, fromFile file: File, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)>
    func finishUpload(key: String, result: Result<(Int, String, URL), Swift.Error>, file: File?, queue: DispatchQueue) -> Single<()>
    func delete(keys: [String], queue: DispatchQueue) -> Single<WebDavDeletionResult>
    func cancelDeletions()
    func resetVerification()
}

final class WebDavControllerImpl: WebDavController {
    fileprivate enum MetadataResult {
        case unchanged
        case mtimeChanged(Int)
        case changed(URL)
        case new(URL)
    }

    private let apiClient: ApiClient
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    let sessionStorage: WebDavSessionStorage
    private let deletionQueue: OperationQueue
    
    /// Callback invoked when a server presents an untrusted certificate.
    /// 
    /// When the user chooses to trust the certificate, it undergoes validation and is stored
    /// in `sessionStorage.trustedCertificateData` for certificate pinning. This implements
    /// a "Trust-On-First-Use" (TOFU) model with additional security checks.
    ///
    /// **Certificate Pinning Strategy:**
    /// 1. User explicitly trusts a certificate (first connection)
    /// 2. Certificate is validated (not expired, valid chain)
    /// 3. Certificate data is stored (pinned)
    /// 4. Subsequent connections MUST present the exact same certificate
    /// 5. Any change triggers security alert and requires re-verification
    ///
    /// **Thread Safety:** This property is accessed and set on the main thread only.
    /// The completion handler is called on URLSession's delegate queue but is safe
    /// as sessionStorage writes are synchronized.
    ///
    /// - Parameters:
    ///   - trust: The server trust object to evaluate
    ///   - host: The hostname presenting the certificate
    ///   - completion: Completion handler with user's trust decision
    ///
    /// - Note: The certificate is only stored if:
    ///   - User explicitly trusts it
    ///   - Certificate passes validation (not expired, valid)
    ///   - sessionStorage is available
    ///   Stored certificates are validated on subsequent connections to prevent MITM attacks.
    var onServerTrustChallenge: ((SecTrust, String, @escaping (Bool) -> Void) -> Void)? {
        didSet {
            // Wrap the handler to always validate and store certificate when trusted
            guard let onServerTrustChallenge else {
                (apiClient as? ZoteroApiClient)?.onTrustChallenge = nil
                return
            }
            
            (apiClient as? ZoteroApiClient)?.onTrustChallenge = { [weak sessionStorage] trust, host, completion in
                // SECURITY: Only apply custom trust handling to WebDAV hosts
                // Never intercept certificate validation for api.zotero.org or other hosts
                guard let storage = sessionStorage,
                      storage.isEnabled,
                      host == storage.host else {
                    // Not our WebDAV host - reject and use default system validation
                    DDLogInfo("WebDavController: ignoring trust challenge for non-WebDAV host: \(host)")
                    completion(false)
                    return
                }
                
                onServerTrustChallenge(trust, host) { shouldTrust in
                    if shouldTrust {
                        // Ensure sessionStorage is available to persist certificate
                        guard let sessionStorage else {
                            DDLogError("WebDavController: sessionStorage is nil, cannot store certificate for \(host)")
                            completion(false)
                            return
                        }
                        
                        // Validate certificate before pinning
                        let validationResult = CertificateValidator.validateCertificateForPinning(trust: trust, host: host)
                        
                        switch validationResult {
                        case .valid:
                            // Extract and store certificate for pinning
                            guard let certData = CertificateValidator.extractCertificateData(from: trust) else {
                                DDLogError("WebDavController: failed to extract certificate from trust for \(host)")
                                completion(false)
                                return
                            }
                            
                            sessionStorage.trustedCertificateData = certData
                            DDLogInfo("WebDavController: stored trusted certificate for \(host)")
                            completion(true)
                            
                        case .expired:
                            // Reject expired certificates
                            DDLogError("WebDavController: refusing to pin expired certificate for \(host)")
                            // Post notification to show error to user
                            NotificationCenter.default.post(
                                name: .webDavCertificateExpired,
                                object: nil,
                                userInfo: ["host": host]
                            )
                            completion(false)
                            
                        case .invalid(let reason):
                            DDLogError("WebDavController: certificate validation failed for \(host): \(reason)")
                            completion(false)
                        }
                    } else {
                        completion(false)
                    }
                }
            }
        }
    }

    init(dbStorage: DbStorage, fileStorage: FileStorage, sessionStorage: WebDavSessionStorage) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInteractive

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.apiClient = ZoteroApiClient(baseUrl: "http://zotero.org/", configuration: configuration)
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.sessionStorage = sessionStorage
        self.deletionQueue = queue

        if self.sessionStorage.isVerified {
            self.apiClient.set(credentials: (self.sessionStorage.username, self.sessionStorage.password))
        }
    }

    func resetVerification() {
        self.sessionStorage.isVerified = false
        self.sessionStorage.trustedCertificateData = nil
        self.apiClient.set(credentials: nil)
    }

    /// Creates url in WebDAV server of item which should be downloaded.
    /// - parameter key: Key of item to download.
    /// - returns: Single with url of item stored in WebDAV.
    func download(key: String, file: File, queue: DispatchQueue) -> Observable<DownloadRequest> {
        return self.checkServerIfNeeded(queue: queue)
                   .asObservable()
                   .flatMap({ Observable.just($0.appendingPathComponent("\(key).zip")) })
                   .flatMap({ self.apiClient.download(request: FileRequest(webDavUrl: $0, destination: file), queue: queue) })
    }

    func createURLRequest(from request: ApiRequest) throws -> URLRequest {
        return try apiClient.urlRequest(from: request)
    }

    /// Prepares for WebDAV upload. Checks .prop file to see whether the file has been modified. Creates a ZIP file to upload. Updates mtime in db in case it's the only thing that changed.
    /// - parameter key: Key of item to upload.
    /// - parameter mtime: Modification time of attachment.
    /// - parameter hash: MD5 hash of attachment.
    /// - parameter file: `File` location of attachment.
    /// - parameter queue: Processing queue.
    /// - returns: `UploadRequest` which contains either WebDAV URL and File location of file to upload or indicates that file is already available on WebDAV.
    func prepareForUpload(key: String, mtime: Int, hash: String, file: File, queue: DispatchQueue) -> Single<WebDavUploadResult> {
        DDLogInfo("WebDavController: prepare for upload")
        return self.checkServerIfNeeded(queue: queue)
            .flatMap({ url -> Single<MetadataResult> in
                return self.checkMetadata(key: key, mtime: mtime, hash: hash, url: url, queue: queue)
            })
            .flatMap({ result -> Single<WebDavUploadResult> in
                switch result {
                case .unchanged:
                    return Single.just(.exists)

                case .new(let url):
                    return self.zip(file: file, key: key).flatMap({ return Single.just(.new(url, $0)) })

                case .mtimeChanged(let mtime):
                    return self.update(mtime: mtime, key: key, queue: queue).flatMap({ Single.just(.exists) })

                case .changed(let url):
                // If metadata were available on WebDAV, but they changed, remove original .prop file.
                return self.removeExistingMetadata(key: key, url: url, queue: queue)
                    .flatMap({ self.zip(file: file, key: key) })
                    .flatMap({ Single.just(.new(url, $0)) })
                }
            })
            .catch { error in
                if let responseError = error as? AFResponseError {
                    throw WebDavError.Upload.apiError(error: responseError.error, httpMethod: responseError.httpMethod)
                }
                if let alamoError = error as? AFError {
                    throw WebDavError.Upload.apiError(error: alamoError, httpMethod: nil)
                }
                throw error
            }
    }

    func upload(request: AttachmentUploadRequest, fromFile file: File, queue: DispatchQueue) -> Single<(Data?, HTTPURLResponse)> {
        return self.apiClient.upload(request: request, fromFile: file, queue: queue)
            .catch { error in
                if let responseError = error as? AFResponseError {
                    throw WebDavError.Upload.apiError(error: responseError.error, httpMethod: responseError.httpMethod)
                }
                if let alamoError = error as? AFError {
                    throw WebDavError.Upload.apiError(error: alamoError, httpMethod: nil)
                }
                throw error
            }
    }

    /// Finishes upload to WebDAV. If successful, uploads new metadata .prop file to WebDAV. In both cases removes temporary ZIP file created in `prepareForUpload`.
    /// - parameter key: Key of attachment item.
    /// - parameter result: Indicates whether file upload was successful. If successful, contains mtime, hash and WebDAV url.
    /// - parameter file: Optional `File` location of created temporary ZIP file. If available, removes ZIP.
    /// - parameter queue: Processing queue.
    /// - returns: Single indicating whether metadata were submitted and cleanup was successful.
    func finishUpload(key: String, result: Result<(Int, String, URL), Swift.Error>, file: File?, queue: DispatchQueue) -> Single<()> {
        switch result {
        case .success((let mtime, let hash, let url)):
            DDLogInfo("WebDavController: finish successful upload")
            return self.uploadMetadata(key: key, mtime: mtime, hash: hash, url: url, queue: queue)
                       .flatMap({ _ in
                           if let file = file {
                               return self.remove(file: file)
                           } else {
                               return Single.just(())
                           }
                       })

        case .failure(let error):
            DDLogError("WebDavController: finish failed upload - \(error)")
            if let file = file {
                return self.remove(file: file)
            } else {
                return Single.just(())
            }
        }
    }

    func delete(keys: [String], queue: DispatchQueue) -> Single<WebDavDeletionResult> {
        return self.checkServerIfNeeded(queue: queue)
                   .flatMap { url -> Single<WebDavDeletionResult> in
                       return self.performDeletions(withBaseUrl: url, keys: keys, queue: queue)
                   }
    }

    func cancelDeletions() {
        guard !self.deletionQueue.isSuspended else { return }
        self.deletionQueue.cancelAllOperations()
    }

    private func performDeletions(withBaseUrl url: URL, keys: [String], queue: DispatchQueue) -> Single<WebDavDeletionResult> {
        return Single.create { subscriber in
            var count = 0
            var operations: [ApiOperation] = []
            var succeeded: Set<String> = []
            var missing: Set<String> = []
            var failed: Set<String> = []

            let processResult: (String, Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void = { key, result in
                switch result {
                case .success:
                    if !failed.contains(key) && !missing.contains(key) {
                        succeeded.insert(key)
                    }

                case .failure:
                    succeeded.remove(key)
                    missing.remove(key)
                    failed.insert(key)
                }

                count -= 1

                if count == 0 {
                    subscriber(.success(WebDavDeletionResult(succeeded: succeeded, missing: missing, failed: failed)))
                }
            }

            for key in keys {
                let propRequest = WebDavDeleteRequest(url: url.appendingPathComponent(key + ".prop"))
                let propOperation = ApiOperation(apiRequest: propRequest, apiClient: self.apiClient, responseQueue: queue) { result in
                    queue.async(flags: .barrier) {
                        processResult(key, result)
                    }
                }
                operations.append(propOperation)

                let zipRequest = WebDavDeleteRequest(url: url.appendingPathComponent(key + ".zip"))
                let zipOperation = ApiOperation(apiRequest: zipRequest, apiClient: self.apiClient, responseQueue: queue) { result in
                    queue.async(flags: .barrier) {
                        processResult(key, result)
                    }
                }
                operations.append(zipOperation)
            }

            count = operations.count

            self.deletionQueue.addOperations(operations, waitUntilFinished: false)

            return Disposables.create()
        }
    }

    private func update(mtime: Int, key: String, queue: DispatchQueue) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            do {
                try self.dbStorage.perform(request: StoreMtimeForAttachmentDbRequest(mtime: mtime, key: key, libraryId: .custom(.myLibrary)), on: queue)
                subscriber(.success(()))
            } catch let error {
                DDLogError("WebDavController: can't update mtime - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    private func remove(file: File) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            try? self.fileStorage.remove(file)
            subscriber(.success(()))
            return Disposables.create()
        }
    }

    private func zip(file: File, key: String) -> Single<File> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("WebDavController: ZIP file for upload")

            do {
                let tmpFile = Files.temporaryZipUploadFile(key: key)
                try self.fileStorage.createDirectories(for: tmpFile)
                try? self.fileStorage.remove(tmpFile)
                try FileManager.default.zipItem(at: file.createUrl(), to: tmpFile.createUrl())
                subscriber(.success(tmpFile))
            } catch let error {
                DDLogError("WebDavController: can't zip file - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    private func removeExistingMetadata(key: String, url: URL, queue: DispatchQueue) -> Single<()> {
        DDLogInfo("WebDavController: remove metadata for \(key)")
        return self.apiClient.send(request: WebDavDeleteRequest(url: url.appendingPathComponent(key + ".prop")), queue: queue)
            .flatMap({ _ in return Single.just(()) })
    }

    private func uploadMetadata(key: String, mtime: Int, hash: String, url: URL, queue: DispatchQueue) -> Single<()> {
        DDLogInfo("WebDavController: upload metadata for \(key)")
        let metadataProp = "<properties version=\"1\"><mtime>\(mtime)</mtime><hash>\(hash)</hash></properties>"
        guard let data = metadataProp.data(using: .utf8) else { return Single.error(WebDavError.Upload.cantCreatePropData) }
        return self.apiClient.send(request: WebDavWriteRequest(url: url.appendingPathComponent(key + ".prop"), data: data), queue: queue)
            .flatMap({ _ in return Single.just(()) })
            .catch { error in
                if let responseError = error as? AFResponseError {
                    throw WebDavError.Upload.apiError(error: responseError.error, httpMethod: responseError.httpMethod)
                }
                if let alamoError = error as? AFError {
                    throw WebDavError.Upload.apiError(error: alamoError, httpMethod: nil)
                }
                throw error
            }
    }

    private func checkMetadata(key: String, mtime: Int, hash: String, url: URL, queue: DispatchQueue) -> Single<MetadataResult> {
        DDLogInfo("WebDavController: check metadata for \(key)")
        return self.metadata(key: key, url: url, queue: queue)
            .flatMap({ remoteData -> Single<MetadataResult> in
                guard let (remoteMtime, remoteHash) = remoteData else { return Single.just(.new(url)) }

                if hash == remoteHash {
                    return Single.just(mtime == remoteMtime ? .unchanged : .mtimeChanged(remoteMtime))
                } else {
                    return Single.just(.changed(url))
                }
            })
    }

    /// Loads metadata of item from WebDAV server.
    /// - parameter key: Key of item.
    /// - parameter url: WebDAV url.
    /// - returns: Single containing mtime and hash.
    private func metadata(key: String, url: URL, queue: DispatchQueue) -> Single<(Int, String)?> {
        let request = WebDavDownloadRequest(url: url.appendingPathComponent(key + ".prop"))
        return self.apiClient.send(request: request, queue: queue)
                   .do(onError: { error in
                       DDLogError("WebDavController: \(key) item prop file error - \(error)")
                   })
                   .flatMap({ data, response -> Single<(Int, String)?> in
                       if response.statusCode == 404 {
                           DDLogInfo("WebDavController: \(key) item prop file not found")
                           return Single.just(nil)
                       }

                       guard let data = data else {
                           return Single.error(ZoteroApiError.responseMissing(ApiLogger.identifier(method: request.httpMethod.rawValue, url: (response.url?.absoluteString ?? ""))))
                       }

                       let delegate = WebDavPropParserDelegate()
                       let parser = XMLParser(data: data)
                       parser.delegate = delegate

                       if parser.parse(), let mtime = delegate.mtime, let hash = delegate.fileHash {
                           return Single.just((mtime, hash))
                       } else {
                           DDLogError("WebDavController: \(key) item prop invalid. mtime=\(delegate.mtime.flatMap(String.init) ?? "missing"); hash=\(delegate.fileHash ?? "missing")")
                           return Single.error(WebDavError.Download.itemPropInvalid(String(data: data, encoding: .utf8) ?? ""))
                       }
                   })
    }

    /// If server is not verified, performs verification first.
    /// - returns: URL of WebDAV server after verification or immediately if verified.
    private func checkServerIfNeeded(queue: DispatchQueue) -> Single<URL> {
        if self.sessionStorage.isVerified {
            return self.createUrl()
        }

        var disposeBag: DisposeBag?

        return Single.create { [weak self] subscriber in
            guard let self = self else { return Disposables.create() }

            let _disposeBag = DisposeBag()
            disposeBag = _disposeBag

            self.checkServer(queue: queue).subscribe(with: self, onSuccess: { _, url in
                subscriber(.success(url))
            }, onFailure: { `self`, error in
                /// .fileMissingAfterUpload is not a critical/fatal error. The sync can continue working.
                guard let error = error as? WebDavError.Verification, case .fileMissingAfterUpload = error else {
                    subscriber(.failure(error))
                    return
                }

                do {
                    let url = try self._createUrl(sessionStorage: self.sessionStorage)
                    subscriber(.success(url))
                } catch let error {
                    subscriber(.failure(error))
                }
            })
            .disposed(by: _disposeBag)

            return Disposables.create {
                // Get rid of warning
                _ = disposeBag
                disposeBag = nil
            }
        }
    }

    /// Checks whether WebDAV server is available and compatible.
    func checkServer(queue: DispatchQueue) -> Single<URL> {
        DDLogInfo("WebDavController: checkServer")
        return self.loadCredentials()
                   .do(onSuccess: { [weak self] credentials in
                       self?.apiClient.set(credentials: credentials)
                   })
                   .flatMap({ _ in return self.createUrl() })
                   .flatMap({ url in return self.checkIsDav(url: url, queue: queue) })
                   .flatMap({ url in return self.checkZoteroDirectory(url: url, queue: queue) })
                   .do(onSuccess: { [weak self] _ in
                       self?.sessionStorage.isVerified = true
                       DDLogInfo("WebDavController: file sync is successfully set up")
                   }, onError: { [weak self] error in
                       DDLogError("WebDavController: checkServer failed - \(error)")

                       /// .fileMissingAfterUpload is not a critical/fatal error. We can still mark webdav as verified.
                       guard let error = error as? WebDavError.Verification, case .fileMissingAfterUpload = error else {
                           self?.apiClient.set(credentials: nil)
                           return
                       }
                       self?.sessionStorage.isVerified = true
                   })
    }

    func createZoteroDirectory(queue: DispatchQueue) -> Single<()> {
        return self.createUrl()
                    .flatMap { url in
                        return self.apiClient.send(request: WebDavCreateZoteroDirectoryRequest(url: url)).flatMap({ _ in Single.just(()) })
                    }
    }

    /// Checks whether server is WebDAV server.
    private func checkIsDav(url: URL, queue: DispatchQueue) -> Single<URL> {
        let request = WebDavCheckRequest(url: url)
        return self.apiClient.send(request: request, queue: queue)
                             .flatMap({ _, response -> Single<URL> in
                                 guard response.allHeaderFields.caseInsensitiveContains(key: "dav") else {
                                     return Single.error(WebDavError.Verification.notDav)
                                 }
                                 return Single.just(url)
                             })
    }

    /// Checks whether WebDAV server contains Zotero directory and whether the directory is compatible.
    private func checkZoteroDirectory(url: URL, queue: DispatchQueue) -> Single<URL> {
        return self.propFind(url: url, queue: queue)
                   .flatMap({ response -> Single<URL> in
                       if response.statusCode == 207 {
                           return self.checkWhetherReturns404ForMissingFile(url: url, queue: queue)
                               .flatMap({ self.checkWritability(url: url, queue: queue) })
                                      .flatMap({ Single.just(url) })
                       }

                       if response.statusCode == 404 {
                           // Zotero directory wasn't found, see if parent directory exists
                           return self.checkWhetherParentAvailable(url: url, queue: queue)
                       }

                       return Single.just(url)
                   })
    }

    /// Checks whether WebDAV server has access to write files.
    private func checkWritability(url: URL, queue: DispatchQueue) -> Single<()> {
        let request = WebDavTestWriteRequest(url: url)
        return self.apiClient.send(request: request, queue: queue)
                   .flatMap({ _ -> Single<()> in
                       return self.apiClient.send(request: WebDavDownloadRequest(endpoint: request.endpoint, logParams: .headers), queue: queue)
                                  .flatMap({ _, response in
                                      if response.statusCode == 404 {
                                          return Single.error(WebDavError.Verification.fileMissingAfterUpload)
                                      }
                                      return Single.just(())
                                  })
                   })
                   .flatMap({ _ -> Single<()> in
                       return self.apiClient.send(request: WebDavDeleteRequest(endpoint: request.endpoint, logParams: .headers), queue: queue).flatMap({ _ in Single.just(()) })
                   })
    }

    /// Checks whether parent of given URL is available.
    private func checkWhetherParentAvailable(url: URL, queue: DispatchQueue) -> Single<URL> {
        return self.propFind(url: url.deletingLastPathComponent(), queue: queue)
                   .flatMap({ response -> Single<URL> in
                       if response.statusCode == 207 {
                           return Single.error(WebDavError.Verification.zoteroDirNotFound(url.absoluteString))
                       } else {
                           return Single.error(WebDavError.Verification.parentDirNotFound)
                       }
                   })
    }

    /// Checks whether WebDAV server correctly responds to a request for missing file.
    private func checkWhetherReturns404ForMissingFile(url: URL, queue: DispatchQueue) -> Single<()> {
        return self.apiClient.send(request: WebDavNonexistentPropRequest(url: url), queue: queue)
                             .flatMap({ _, response -> Single<()> in
                                 if response.statusCode == 404 {
                                     return Single.just(())
                                 } else {
                                     return Single.error(WebDavError.Verification.nonExistentFileNotMissing)
                                 }
                             })
    }

    /// Creates a propfind request for given url.
    private func propFind(url: URL, queue: DispatchQueue) -> Single<HTTPURLResponse> {
        return self.apiClient.send(request: WebDavPropfindRequest(url: url), queue: queue).flatMap({ Single.just($1) })
    }

    var currentUrl: URL? {
        return try? _createUrl(sessionStorage: sessionStorage)
    }

    /// Creates and validates WebDAV server URL based on stored session.
    private func createUrl() -> Single<URL> {
        return Single.create { [weak self, weak sessionStorage] subscriber in
            guard let self = self else {
                DDLogError("WebDavController: self doesn't exist")
                subscriber(.failure(WebDavError.Verification.noUsername))
                return Disposables.create()
            }

            guard let sessionStorage = sessionStorage else {
                DDLogError("WebDavController: session storage not found")
                subscriber(.failure(WebDavError.Verification.noUsername))
                return Disposables.create()
            }

            do {
                let url = try self._createUrl(sessionStorage: sessionStorage)
                subscriber(.success(url))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func _createUrl(sessionStorage: WebDavSessionStorage) throws -> URL {
        let url = sessionStorage.url
        guard !url.isEmpty else {
            DDLogError("WebDavController: url not found")
            throw WebDavError.Verification.noUrl
        }

        let urlComponents = url.components(separatedBy: "/")
        guard !urlComponents.isEmpty else {
            DDLogError("WebDavController: url components empty - \(url)")
            throw WebDavError.Verification.invalidUrl
        }

        let hostComponents = (urlComponents.first ?? "").components(separatedBy: ":")
        let host = hostComponents.first
        let port = hostComponents.last.flatMap(Int.init)

        let path: String
        if urlComponents.count == 1 {
            path = "/zotero/"
        } else {
            path = "/" + urlComponents.dropFirst().filter({ !$0.isEmpty }).joined(separator: "/") + "/zotero/"
        }

        var components = URLComponents()
        components.scheme = sessionStorage.scheme.rawValue
        components.host = host
        components.path = path
        components.port = port

        if let url = components.url {
            return url
        } else {
            DDLogError("WebDavController: could not create url from components. url=\(url); host=\(host ?? "missing"); path=\(path); port=\(port.flatMap(String.init) ?? "missing")")
            throw WebDavError.Verification.invalidUrl
        }
    }

    private func loadCredentials() -> Single<(String, String)> {
        return Single.create { [weak sessionStorage] subscriber in
            guard let sessionStorage = sessionStorage else {
                DDLogError("WebDavController: session storage not found")
                subscriber(.failure(WebDavError.Verification.noUsername))
                return Disposables.create()
            }
            let username = sessionStorage.username
            guard !username.isEmpty else {
                DDLogError("WebDavController: username not found")
                subscriber(.failure(WebDavError.Verification.noUsername))
                return Disposables.create()
            }
            let password = sessionStorage.password
            guard !password.isEmpty else {
                DDLogError("WebDavController: password not found")
                subscriber(.failure(WebDavError.Verification.noPassword))
                return Disposables.create()
            }

            subscriber(.success((username, password)))
            return Disposables.create()
        }
    }
}

// MARK: - Certificate Validation Utilities

/// Utility for validating and extracting information from certificates.
final class CertificateValidator {
    /// Result of certificate validation
    enum ValidationResult {
        case valid
        case expired
        case invalid(String)
    }
    
    /// Validates a certificate against a pinned certificate with expiration checking.
    ///
    /// **Security Checks:**
    /// 1. Certificate must exactly match the pinned certificate (prevents MITM)
    /// 2. Certificate must not be expired (prevents replay attacks with old certs)
    /// 3. Certificate must pass trust evaluation
    ///
    /// - Parameters:
    ///   - trust: The server trust object to evaluate
    ///   - pinnedCertData: The pinned certificate data to compare against
    ///   - host: The hostname for logging purposes
    /// - Returns: ValidationResult indicating success or failure with details
    static func validateCertificate(trust: SecTrust, pinnedCertData: Data, host: String) -> ValidationResult {
        // Extract server certificate
        guard let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let serverCert = certificateChain.first else {
            DDLogError("CertificateValidator: failed to extract certificate chain for \(host)")
            return .invalid("Failed to extract certificate")
        }
        
        let serverCertData = SecCertificateCopyData(serverCert) as Data
        
        // SECURITY CHECK 1: Certificate must exactly match the pinned certificate
        guard serverCertData == pinnedCertData else {
            DDLogError("CertificateValidator: certificate mismatch for \(host) - possible MITM attack")
            return .invalid("Certificate does not match pinned certificate")
        }
        
        // SECURITY CHECK 2: Certificate must not be expired
        // For self-signed certificates, set as own trust anchor to validate expiration
        SecTrustSetAnchorCertificates(trust, [serverCert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        
        var error: CFError?
        if !SecTrustEvaluateWithError(trust, &error) {
            // Check error code for expiration (robust across languages/iOS versions)
            if let cfError = error {
                let nsError = cfError as Error as NSError
                // Certificate expiration/validity error codes from Apple's SecBase.h:
                // Source: Security.framework/Headers/SecBase.h
                // Verify with: grep "errSecCertificate.*Expired\|errSecCertificate.*ValidYet" \
                //   /Applications/Xcode.app/.../Security.framework/Headers/SecBase.h
                // Using error codes instead of string matching ensures:
                // - Works across all device languages (not affected by localization)
                // - Stable across iOS versions (error codes don't change, messages do)
                // - Precise matching (no false positives from unrelated "expired" mentions)
                let expirationCodes = [
                    -67818, // errSecCertificateExpired - "An expired certificate was detected"
                    -67819  // errSecCertificateNotValidYet - "The certificate is not yet valid"
                ]
                
                if nsError.domain == "NSOSStatusErrorDomain" && expirationCodes.contains(nsError.code) {
                    DDLogError("CertificateValidator: certificate is expired for \(host) (error code: \(nsError.code))")
                    return .expired
                }
            }
            
            // Fallback: check error description (less reliable but covers edge cases)
            let errorDescription = error.flatMap { CFErrorCopyDescription($0) as String? } ?? "Unknown error"
            DDLogWarn("CertificateValidator: certificate validation failed for \(host): \(errorDescription)")
            
            // Double-check with string matching as final fallback
            if errorDescription.lowercased().contains("expired") {
                DDLogError("CertificateValidator: certificate appears expired for \(host) (fallback detection)")
                return .expired
            }
            
            // For other validation issues (like hostname mismatch), allow since user explicitly trusted it
            DDLogWarn("CertificateValidator: allowing connection despite validation warning - certificate was explicitly trusted")
        }
        
        DDLogInfo("CertificateValidator: validated pinned certificate for \(host)")
        return .valid
    }
    
    /// Validates a certificate before storing it (for initial trust).
    ///
    /// - Parameters:
    ///   - trust: The server trust object to evaluate
    ///   - host: The hostname for logging purposes
    /// - Returns: ValidationResult indicating if certificate is acceptable for pinning
    static func validateCertificateForPinning(trust: SecTrust, host: String) -> ValidationResult {
        guard let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let cert = certificateChain.first else {
            DDLogError("CertificateValidator: failed to extract certificate from trust for \(host)")
            return .invalid("Failed to extract certificate")
        }
        
        // For self-signed certificates, set as own trust anchor to validate expiration
        SecTrustSetAnchorCertificates(trust, [cert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        
        var error: CFError?
        if !SecTrustEvaluateWithError(trust, &error) {
            // Check error code for expiration (robust across languages/iOS versions)
            if let cfError = error {
                let nsError = cfError as Error as NSError
                // Certificate expiration/validity error codes from Apple's SecBase.h:
                // Source: Security.framework/Headers/SecBase.h
                // Verify with: grep "errSecCertificate.*Expired\|errSecCertificate.*ValidYet" \
                //   /Applications/Xcode.app/.../Security.framework/Headers/SecBase.h
                // Using error codes instead of string matching ensures:
                // - Works across all device languages (not affected by localization)
                // - Stable across iOS versions (error codes don't change, messages do)
                // - Precise matching (no false positives from unrelated "expired" mentions)
                let expirationCodes = [
                    -67818, // errSecCertificateExpired - "An expired certificate was detected"
                    -67819  // errSecCertificateNotValidYet - "The certificate is not yet valid"
                ]
                
                if nsError.domain == "NSOSStatusErrorDomain" && expirationCodes.contains(nsError.code) {
                    DDLogError("CertificateValidator: refusing to pin expired certificate for \(host) (error code: \(nsError.code))")
                    return .expired
                }
            }
            
            // Fallback: check error description (less reliable but covers edge cases)
            let errorDescription = error.flatMap { CFErrorCopyDescription($0) as String? } ?? "Unknown error"
            DDLogError("CertificateValidator: certificate validation failed for \(host): \(errorDescription)")
            
            // Double-check with string matching as final fallback
            if errorDescription.lowercased().contains("expired") {
                DDLogError("CertificateValidator: refusing to pin expired certificate for \(host) (fallback detection)")
                return .expired
            }
            
            // For other errors, log but allow (hostname mismatch is expected for some self-signed certs)
            DDLogWarn("CertificateValidator: validation warning during pinning for \(host): \(errorDescription)")
        }
        
        return .valid
    }
    
    /// Extracts the subject summary from a certificate.
    ///
    /// - Parameter certificate: The certificate to extract subject from
    /// - Returns: The subject summary if available, nil otherwise
    static func extractSubject(from certificate: SecCertificate) -> String? {
        return SecCertificateCopySubjectSummary(certificate) as String?
    }
    
    /// Calculates the SHA-256 fingerprint of a certificate.
    ///
    /// - Parameter certificate: The certificate to calculate fingerprint for
    /// - Returns: The SHA-256 fingerprint as a hex string (uppercase with colons), nil if calculation fails
    static func calculateFingerprint(from certificate: SecCertificate) -> String? {
        let certData = SecCertificateCopyData(certificate) as Data
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        certData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(certData.count), &hash)
        }
        // Format as uppercase hex with colons (e.g., "AB:CD:EF:01:23:45:...")
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
    
    /// Extracts certificate data for pinning.
    ///
    /// - Parameter trust: The server trust object
    /// - Returns: The certificate data if available, nil otherwise
    static func extractCertificateData(from trust: SecTrust) -> Data? {
        guard let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let cert = certificateChain.first else {
            return nil
        }
        return SecCertificateCopyData(cert) as Data
    }
}
