//
//  BackgroundUploader.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RxSwift
import RxCocoa

class BackgroundUploader: NSObject {
    enum Error: Swift.Error {
        case uploadFromMemoryOrStream
    }

    private let context: BackgroundUploaderContext
    private let fileStorage: FileStorage
    private let uploadProcessor: BackgroundUploadProcessor

    private var session: URLSession!
    private var finishedUploads: [BackgroundUpload]
    private var uploadsFinishedProcessing: Bool
    private var disposeBag: DisposeBag

    #if MAINAPP
    private var backgroundTaskId: UIBackgroundTaskIdentifier
    #endif

    var backgroundCompletionHandler: (() -> Void)?

    init(uploadProcessor: BackgroundUploadProcessor) {
        self.context = BackgroundUploaderContext()
        self.fileStorage = FileStorageController()
        self.uploadProcessor = uploadProcessor
        self.finishedUploads = []
        self.uploadsFinishedProcessing = true
        self.disposeBag = DisposeBag()

        #if MAINAPP
        self.backgroundTaskId = .invalid
        #endif

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
                queue: DispatchQueue,
                completion: @escaping (Swift.Error?) -> Void) {
        self.createMultipartformRequest(for: upload,
                                        filename: filename,
                                        mimeType: mimeType,
                                        parameters: parameters,
                                        headers: headers,
                                        queue: queue,
                                        completion: { [weak self] result in
                                            switch result {
                                            case .failure(let error):
                                                completion(error)
                                            case .success((let request, let fileUrl)):
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
                                            queue: DispatchQueue,
                                            completion: @escaping (Swift.Result<(URLRequest, URL), Swift.Error>) -> Void) {
        let formData = MultipartFormData(fileManager: FileManager.default)
        if let parameters = parameters {
            // Append parameters to the multipartform request.
            parameters.forEach { (key, value) in
                if let stringData = value.data(using: .utf8) {
                    formData.append(stringData, withName: key)
                }
            }
        }
        formData.append(upload.fileUrl, withName: "file", fileName: filename, mimeType: mimeType)

        let newFile = Files.uploadFile
        let newFileUrl = newFile.createUrl()

        do {
            try self.fileStorage.createDirectories(for: newFile)
            try formData.writeEncodedData(to: newFileUrl)
            var request = try URLRequest(url: upload.remoteUrl, method: .post, headers: headers.flatMap(HTTPHeaders.init))
            request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
            try request.validate()
            completion(.success((request, newFileUrl)))
        } catch let error {
            DDLogError("BackgroundUploader: error - \(error)")
            completion(.failure(error))
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
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
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
