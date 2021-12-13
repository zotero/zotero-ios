//
//  BackgroundUploader.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Alamofire
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
    private unowned let backgroundTaskController: BackgroundTaskController?

    private var session: URLSession!

    init(uploadProcessor: BackgroundUploadProcessor, schemaVersion: Int, backgroundTaskController: BackgroundTaskController?) {
        self.context = BackgroundUploaderContext()
        self.uploadProcessor = uploadProcessor
        self.backgroundTaskController = backgroundTaskController

        super.init()

        let configuration = URLSessionConfiguration.background(withIdentifier: "org.zotero.background.upload.session")
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description,
                                               "Zotero-Schema-Version": schemaVersion]
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.timeoutIntervalForRequest = ApiConstants.requestTimeout
        configuration.timeoutIntervalForResource = ApiConstants.resourceTimeout

        let delegate: URLSessionDelegate?
        #if MAINAPP
        delegate = self
        #else
        delegate = nil
        #endif

        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    var uploads: [BackgroundUpload] {
        return self.context.uploads
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

    private func process(upload: BackgroundUpload, taskId: Int, didFail: Bool, backgroundTaskController: BackgroundTaskController) {
        #if MAINAPP
        var disposeBag: DisposeBag = DisposeBag()

        let backgroundTask = backgroundTaskController.startTask()
        backgroundTask.expirationHandler = { [weak self] in
            // Remove upload from context so that it's processed by main app
            self?.context.deleteUpload(with: taskId)
            // Cancel upload finishing action.
            disposeBag = DisposeBag()
        }

        self.uploadProcessor.finish(upload: upload, successful: !didFail)
                            .observe(on: MainScheduler.instance)
                            .subscribe(onError: { [weak self] error in
                                DDLogError("BackgroundUploader: failed processing finished tasks - \(error)")
                                // Remove upload from context so that it's processed by main app
                                self?.context.deleteUpload(with: taskId)
                                // End background task
                                backgroundTaskController.end(task: backgroundTask)
                            }, onCompleted: { [weak self] in
                                DDLogError("BackgroundUploader: done processing finished tasks")
                                // Remove upload from context so that it's processed by main app
                                self?.context.deleteUpload(with: taskId)
                                // End background task
                                backgroundTaskController.end(task: backgroundTask)
                            })
                            .disposed(by: disposeBag)
        #endif
    }

    // MARK: - Uploading

    private func startUpload(_ upload: BackgroundUpload, request: URLRequest) {
        _ = ApiLogger.log(urlRequest: request, encoding: .url, logParams: .headers)

        let task = self.session.uploadTask(with: request, fromFile: upload.fileUrl)
        self.context.save(upload: upload, taskId: task.taskIdentifier)
        task.resume()
    }
}

extension BackgroundUploader: URLSessionDelegate {
    /// Background uploads started in share extension are started in background session and the share extension is closed immediately.
    /// The background url session always finishes in main app. We need to ask for additional time to register uploads and write results to DB.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    }
}

extension BackgroundUploader: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        guard let upload = self.context.loadUpload(for: task.taskIdentifier) else { return }

        DDLogInfo("BackgroundUploader: finished background task \(task.taskIdentifier); \(upload.key); \(upload.fileUrl.lastPathComponent)")
        
        let didFail = self.log(task: task, error: error)
        if let controller = self.backgroundTaskController {
            self.process(upload: upload, taskId: task.taskIdentifier, didFail: didFail, backgroundTaskController: controller)
        } else {
            self.context.deleteUpload(with: task.taskIdentifier)
        }
    }

    /// Logs response of `URLSessionTask` and returns whether request was successfull or not.
    /// - parameter task: `URLSessionTask` to log.
    /// - parameter error: `Error` provided by task delegate.
    /// - returns: `true` if task failed, `false` otherwise.
    private func log(task: URLSessionTask, error: Swift.Error?) -> Bool {
        let logId = ApiLogger.identifier(method: task.originalRequest?.httpMethod ?? "POST", url: task.originalRequest?.url?.absoluteString ?? "")
        let logStartData = ApiLogger.StartData(id: logId, time: 0, logParams: .headers)

        if error != nil || task.error != nil {
            let someError = error ?? task.error
            let responseError = AFResponseError(error: .createURLRequestFailed(error: someError!), headers: [:], response: "Upload failed")
            ApiLogger.logFailedresponse(error: responseError, statusCode: 0, startData: logStartData)
            return true
        }

        guard let response = task.response as? HTTPURLResponse else {
            ApiLogger.logSuccessfulResponse(statusCode: 0, data: nil, headers: [:], startData: logStartData)
            return false
        }

        if 200..<300 ~= response.statusCode {
            ApiLogger.logSuccessfulResponse(statusCode: response.statusCode, data: nil, headers: response.allHeaderFields, startData: logStartData)
            return false
        }

        let responseError = AFResponseError(error: .responseValidationFailed(reason: .unacceptableStatusCode(code: response.statusCode)), headers: response.allHeaderFields, response: "Upload failed")
        ApiLogger.logFailedresponse(error: responseError, statusCode: response.statusCode, startData: logStartData)
        return true
    }
}
