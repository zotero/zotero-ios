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

class BackgroundUploader: NSObject {
    enum Error: Swift.Error {
        case uploadFromMemoryOrStream
    }

    private let context: BackgroundUploaderContext
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

    func start(upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String], headers: [String: String]) -> Single<()> {
        return self.uploadProcessor.createMultipartformRequest(for: upload, filename: filename, mimeType: mimeType,
                                                               parameters: parameters, headers: headers)
                                   .flatMap({ [weak self] request, url in
                                       self?.startUpload(upload.copy(with: url), request: request)
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
