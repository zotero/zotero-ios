//
//  BackgroundUploader.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift
import RxCocoa

final class BackgroundUploader: NSObject {
    enum Error: Swift.Error {
        case uploadFromMemoryOrStream
    }

    private let context: BackgroundUploaderContext
    private let uploadProcessor: BackgroundUploadProcessor

    private var session: URLSession!
    private var finishedUploads: [(Int, BackgroundUpload)]
    private var failedUploads: [(Int, BackgroundUpload)]
    private var uploadsFinishedProcessing: Bool
    private var disposeBag: DisposeBag

    #if MAINAPP
    private var backgroundTaskId: UIBackgroundTaskIdentifier
    #endif

    var backgroundCompletionHandler: (() -> Void)?

    init(uploadProcessor: BackgroundUploadProcessor, schemaVersion: Int) {
        self.context = BackgroundUploaderContext()
        self.uploadProcessor = uploadProcessor
        self.finishedUploads = []
        self.failedUploads = []
        self.uploadsFinishedProcessing = true
        self.disposeBag = DisposeBag()

        #if MAINAPP
        self.backgroundTaskId = .invalid
        #endif

        super.init()

        let configuration = URLSessionConfiguration.background(withIdentifier: "org.zotero.background.upload.session")
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description,
                                               "Zotero-Schema-Version": schemaVersion]
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.timeoutIntervalForRequest = ApiConstants.requestTimeout
        configuration.timeoutIntervalForResource = ApiConstants.resourceTimeout
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    var ongoingUploads: [BackgroundUpload] {
        return self.context.activeUploads
    }

    var ongoingUploadMd5s: [String] {
        return self.context.activeUploads.map({ $0.md5 })
    }

    // MARK: - Actions

    func cancel() {
        self.session.invalidateAndCancel()
        self.context.deleteAllUploads()
    }

    func start(upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String], headers: [String: String]) -> Single<()> {
        return self.uploadProcessor.createRequest(for: upload, filename: filename, mimeType: mimeType, parameters: parameters, headers: headers)
                                   .flatMap({ [weak self] request, url in
                                       var newUpload = upload
                                       if upload.fileUrl != url {
                                           newUpload = upload.copy(with: url)
                                       }
                                       self?.startUpload(newUpload, request: request)
                                       return Single.just(())
                                   })
    }

    // MARK: - Uploading

    private func startUpload(_ upload: BackgroundUpload, request: URLRequest) {
        let task = self.session.uploadTask(with: request, fromFile: upload.fileUrl)
        self.context.saveUpload(upload, taskId: task.taskIdentifier)
        task.resume()
    }

    // MARK: - Finishing upload

    private func finish(successfulUploads: [(Int, BackgroundUpload)], failedUploads: [(Int, BackgroundUpload)]) {
        guard !successfulUploads.isEmpty || !failedUploads.isEmpty else {
            self.uploadsFinishedProcessing = true
            self.completeBackgroundSession()
            return
        }

        let taskIds = successfulUploads.map({ $0.0 }) + failedUploads.map({ $0.0 })
        // Start background task so that we can send register requests to API and store results in DB.
        self.startBackgroundTask(expireAction: { [weak self] in
            // If background task expires before all uploads are processed, remove taskIds from context, so that they are processed by main app when opened.
            self?.context.deleteUploads(with: taskIds)
        })
        // Create actions for all uploads for this background session.
        let actions = failedUploads.map({ self.uploadProcessor.finish(upload: $0.1, successful: false) }) + successfulUploads.map({ self.uploadProcessor.finish(upload: $0.1, successful: true) })
        // Process all actions, call appropriate completion handlers and finish the background task.
        Observable.concat(actions)
                  .observe(on: MainScheduler.instance)
                  .subscribe(onError: { [weak self] error in
                      self?.uploadsFinishedProcessing = true
                      self?.context.deleteUploads(with: taskIds)
                      self?.completeBackgroundSession()
                      self?.endBackgroundTask()
                  }, onCompleted: { [weak self] in
                      self?.uploadsFinishedProcessing = true
                      self?.context.deleteUploads(with: taskIds)
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
    private func startBackgroundTask(expireAction: @escaping () -> Void) {
        #if MAINAPP
        guard UIApplication.shared.applicationState == .background else { return }
        self.backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "org.zotero.background.upload.finish") { [weak self] in
            guard let `self` = self else { return }
            expireAction()
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
        inMainThread {
            if self.uploadsFinishedProcessing {
                self.completeBackgroundSession()
            }
        }
    }
}

extension BackgroundUploader: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        inMainThread {
            self.uploadsFinishedProcessing = false

            if let upload = self.context.loadUpload(for: task.taskIdentifier) {
                if error == nil && task.error == nil {
                    self.finishedUploads.append((task.taskIdentifier, upload))
                } else {
                    self.failedUploads.append((task.taskIdentifier, upload))
                }
            }

            if self.context.activeUploads.count == (self.finishedUploads.count + self.failedUploads.count) {
                self.finish(successfulUploads: self.finishedUploads, failedUploads: self.failedUploads)
                self.finishedUploads = []
                self.failedUploads = []
            }
        }
    }
}
