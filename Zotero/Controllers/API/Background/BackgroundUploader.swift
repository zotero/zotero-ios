//
//  BackgroundUploader.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import RxSwift
import RxCocoa

class BackgroundUploader: NSObject {
    private let context: BackgroundUploaderContext
    private let fileStorage: FileStorage
    private let uploadProcessor: BackgroundUploadProcessor

    private var session: URLSession!
    private var finishedUploads: [BackgroundUpload]
    private var uploadsFinishedProcessing: Bool
    private var backgroundTaskId: UIBackgroundTaskIdentifier
    private var disposeBag: DisposeBag

    var backgroundCompletionHandler: (() -> Void)?

    init(uploadProcessor: BackgroundUploadProcessor) {
        self.context = BackgroundUploaderContext()
        self.fileStorage = FileStorageController()
        self.uploadProcessor = uploadProcessor
        self.finishedUploads = []
        self.uploadsFinishedProcessing = true
        self.backgroundTaskId = .invalid
        self.disposeBag = DisposeBag()

        super.init()

        let configuration = URLSessionConfiguration.background(withIdentifier: "org.zotero.background.upload.session")
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description]
        configuration.sharedContainerIdentifier = AppGroup.identifier
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    // MARK: - Actions

    func cancel() {
        self.session.invalidateAndCancel()
        self.context.deleteAllUploads()
    }

    func ongoingUploads() -> [String] {
        return self.context.activeUploads.map({ $0.md5 })
    }

    func upload(_ upload: BackgroundUpload,
                filename: String,
                mimeType: String,
                parameters: [String: String],
                headers: [String: String],
                completion: @escaping (Error?) -> Void) {
        self.createMultipartformRequest(for: upload,
                                        filename: filename,
                                        mimeType: mimeType,
                                        parameters: parameters,
                                        headers: headers,
                                        completion: { [weak self] result in
                                            switch result {
                                            case .failure(let error):
                                                completion(error)
                                            case .success(let request, let fileUrl):
                                                self?.startUpload(upload.copy(with: fileUrl), request: request)
                                                completion(nil)
                                            }
                                        })
    }

    // MARK: - Uploading

    private func startUpload(_ upload: BackgroundUpload, request: URLRequest) {
        let task = self.session.uploadTask(with: request, fromFile: upload.fileUrl)
        self.context.saveUpload(upload, taskId: task.taskIdentifier)
        task.resume()
    }

    /// Creates a multipartform request for a file upload. The original file is copied to another folder so that it can be streamed from it.
    /// It needs to be deleted once the upload finishes (successful or not).
    /// - parameter upload: Backgroud upload to prepare
    /// - parameter filename: Filename for file to upload
    /// - parameter mimeType: Mimetype of file to upload
    /// - parameter parameters: Extra parameters for upload
    /// - parameter headers: Headers to be sent with the upload request
    /// - parameter completion: Completion containing a result of multipartform encoding. Successful encoding provides a URLRequest that can be used
    ///                         to upload the file and URL pointing to the file which will be uploaded.
    private func createMultipartformRequest(for upload: BackgroundUpload, filename: String, mimeType: String,
                                            parameters: [String: String]?, headers: [String: String]? = nil,
                                            completion: @escaping (Swift.Result<(URLRequest, URL), Error>) -> Void) {
        // iOS doesn't provide a simple way to create a multipartform request for uploading the file to backend. Alamofire is used to simplify
        // the process. Normally, Alamofire would encode the request and send it by itself, but it doesn't support background uploads. So we just
        // use it to create a propert multipartform request and file for us, then we copy the request and file and cancel original Alamofire request.
        Alamofire.upload(multipartFormData: { data in
                             if let parameters = parameters {
                                 // Append parameters to the multipartform request.
                                 parameters.forEach { (key, value) in
                                     if let stringData = value.data(using: .utf8) {
                                         data.append(stringData, withName: key)
                                     }
                                 }
                             }
                             // Append a file url to the multipartform request. For background uploads we have to use file for uploading.
                             data.append(upload.fileUrl, withName: "file", fileName: filename, mimeType: mimeType)
                         },
                         usingThreshold: 0, // set to 0 so that Alamofire doesn't try to stream from memory.
                         to: "http://", // set to "http://" because we don't want Alamofire to automatically send the request and empty string doesn't work
                         method: .post,
                         headers: headers) { result in
                             switch result {
                             case .failure(let error):
                                 completion(.failure(error))

                             case .success(let request, _, let streamFileURL):
                                 // Suspend the original request so that it doesn't continue. We cancel it in defer, because cancelling the request
                                 // delete the file in streamFileURL and we wouldn't be able to copy it.
                                 request.suspend()
                                 defer { request.cancel() }

                                 guard let fileUrl = streamFileURL else {
                                    completion(.failure(AFError.multipartEncodingFailed(reason: .bodyPartURLInvalid(url: upload.fileUrl))))
                                    return
                                 }

                                 do {
                                     // Move the file to a location controlled by us, so that it doesn't get deleted before upload.
                                     let file = Files.file(from: fileUrl)
                                     let newFile = Files.uploadFile(from: fileUrl)
                                     try self.fileStorage.move(from: file, to: newFile)
                                     // Create a new request with correct URL
                                     var newRequest = URLRequest(url: upload.remoteUrl)
                                     newRequest.httpMethod = "POST"
                                     // Copy request headers generated by Alamofire
                                     if let headers = request.request?.allHTTPHeaderFields {
                                         for (key, value) in headers {
                                             newRequest.addValue(value, forHTTPHeaderField: key)
                                         }
                                     }

                                    completion(.success((newRequest, newFile.createUrl())))
                                 } catch let error {
                                    completion(.failure(error))
                                 }
                             }
                         }
    }

    // MARK: - Finishing upload

    private func finishUploads(uploads: [BackgroundUpload]) {
        guard !uploads.isEmpty else {
            self.uploadsFinishedProcessing = true
            self.completeBackgroundSession()
            return
        }

        // Start background task so that we can send register requests to API and store results in DB.
        self.startBackgroundTask()
        // Create actions for all uploads for this background session.
        let actions = uploads.map({ self.uploadProcessor.finish(upload: $0) })
        // Process all actions, call appropriate completion handlers and finish the background task.
        Observable.concat(actions)
                  .observeOn(MainScheduler.instance)
                  .subscribe(onError: { [weak self] error in
                      self?.uploadsFinishedProcessing = true
                      self?.completeBackgroundSession()
                      self?.endBackgroundTask()
                  }, onCompleted: { [weak self] in
                      self?.uploadsFinishedProcessing = true
                      self?.completeBackgroundSession()
                      self?.endBackgroundTask()
                  })
                  .disposed(by: self.disposeBag)
    }

    private func completeBackgroundSession() {
        self.backgroundCompletionHandler?()
        self.backgroundCompletionHandler = nil
    }

    /// Starts background task in the main app. We can limit this to the main app, because the share extension is always closed after the upload
    /// is started, so the upload will be finished in the main app.
    private func startBackgroundTask() {
        #if MAINAPP
        guard UIApplication.shared.applicationState == .background else { return }
        self.backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "org.zotero.background.upload.finish") { [weak self] in
            guard let `self` = self else { return }
            // If the background time expired, cancel ongoing upload processing
            self.disposeBag = DisposeBag()
            UIApplication.shared.endBackgroundTask(self.backgroundTaskId)
            self.backgroundTaskId = .invalid
        }
        #endif
    }

    /// Ends the background task in the main app.
    private func endBackgroundTask() {
        #if MAINAPP
        guard self.backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(self.backgroundTaskId)
        self.backgroundTaskId = .invalid
        #endif
    }
}

extension BackgroundUploader: URLSessionDelegate {
    /// Background uploads started in share extension are started in background session and the share extension is closed immediately.
    /// The background url session always finishes in main app. We need to ask for additional time to register uploads and write results to DB.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if self.uploadsFinishedProcessing {
            self.completeBackgroundSession()
        }
    }
}

extension BackgroundUploader: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.uploadsFinishedProcessing = false

        if let upload = self.context.loadUpload(for: task.taskIdentifier) {
            if error == nil && task.error == nil {
                self.finishedUploads.append(upload)
            }
            self.context.deleteUpload(with: task.taskIdentifier)
        }

        if self.context.activeUploads.isEmpty {
            self.finishUploads(uploads: self.finishedUploads)
            self.finishedUploads = []
        }
    }
}
