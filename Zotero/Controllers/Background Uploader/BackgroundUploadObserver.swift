//
//  BackgroundUploadObserver.swift
//  Zotero
//
//  Created by Michal Rentka on 15.12.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift
import RxCocoa

private struct FinishedTask {
    let taskId: Int
    let upload: BackgroundUpload
    let didFail: Bool
}

final class BackgroundUploadObserver: NSObject {
    let context: BackgroundUploaderContext
    private let backgroundTaskController: BackgroundTaskController
    private let processor: BackgroundUploadProcessor

    private var sessions: [String: URLSession]
    private var finishedTasks: [String: [FinishedTask]]
    private var completionHandlers: [String: () -> Void]

    init(context: BackgroundUploaderContext, processor: BackgroundUploadProcessor, backgroundTaskController: BackgroundTaskController) {
        self.backgroundTaskController = backgroundTaskController
        self.processor = processor
        self.sessions = [:]
        self.finishedTasks = [:]
        self.completionHandlers = [:]
        self.context = BackgroundUploaderContext()

        super.init()
    }

    func observeNewSessions(syncAction: @escaping () -> Void) {
        let ids = self.context.sessionIds

        DDLogInfo("BackgroundUploadObserver: active sessions \(ids)")

        #if DEBUG
        let uploads = self.context.uploads
        DDLogInfo("BackgroundUploadObserver: active uploads (\(uploads.count)) \(uploads.map({ ($0.key, $0.sessionId) }))")
        #endif

        for id in ids {
            guard self.sessions[id] == nil else { continue }

            DDLogInfo("BackgroundUploadObserver: start observing \(id)")

            let session = URLSessionCreator.createSession(for: id, delegate: self)
            self.sessions[id] = session

            // TODO: - check for timed out session and cancel sessions/uploads
        }
    }

    func handleEventsForBackgroundURLSession(with identifier: String, completionHandler: @escaping () -> Void) {
        DDLogInfo("BackgroundUploadObserver: handle events for background url session \(identifier)")
        self.completionHandlers[identifier] = completionHandler
        let session = URLSessionCreator.createSession(for: identifier, delegate: self)
        self.sessions[identifier] = session
    }

    func cancelAllUploads() {
        for id in self.context.sessionIds {
            guard self.sessions[id] == nil else { continue }
            let session = URLSessionCreator.createSession(for: id, delegate: self)
            session.invalidateAndCancel()
        }

        for (_, session) in self.sessions {
            session.invalidateAndCancel()
        }

        self.sessions = [:]
        self.context.deleteAllSessionIds()
        self.context.deleteAllUploads()
    }

    private func process(finishedTasks tasks: [FinishedTask], for sessionId: String) {
        let taskIds = tasks.map({ $0.taskId })
        let actions = tasks.map({ self.processor.finish(upload: $0.upload, successful: !$0.didFail) })
        var disposeBag = DisposeBag()

        let backgroundTask = self.backgroundTaskController.startTask(expirationHandler: { [weak self] in
            // Cancel upload finishing actions.
            disposeBag = DisposeBag()
            // Remove upload from context so that it's processed by main app
            self?.context.deleteUploads(with: taskIds)
            // Call completion handler from AppDelegate
            inMainThread {
                self?.completionHandlers[sessionId]?()
                self?.completionHandlers[sessionId] = nil
            }
        })

        DDLogError("BackgroundUploadObserver: process tasks for \(sessionId)")

        let finishAction: () -> Void = { [weak self] in
            // Detele processed uploads from context
            self?.context.deleteUploads(with: taskIds)
            // Call completion handler from AppDelegate
            self?.completionHandlers[sessionId]?()
            self?.completionHandlers[sessionId] = nil
            // End background task
            self?.backgroundTaskController.end(task: backgroundTask)

        }

        Observable.concat(actions)
                  .observe(on: MainScheduler.instance)
                  .subscribe(onError: { [weak self] error in
                      DDLogError("BackgroundUploadObserver: couldn't finish tasks for \(sessionId) - \(error)")
                      finishAction()
                  }, onCompleted: { [weak self] in
                      DDLogError("BackgroundUploadObserver: finished tasks for \(sessionId)")
                      finishAction()
                  })
                  .disposed(by: disposeBag)
    }
}

extension BackgroundUploadObserver: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let sessionId = session.configuration.identifier else { return }

        DDLogInfo("BackgroundUploadObserver: \(sessionId) session did finish events")
        if let tasks = self.finishedTasks[sessionId] {
            self.process(finishedTasks: tasks, for: sessionId)
        }
        self.finishedTasks[sessionId] = nil

        if self.sessions[sessionId] != nil {
            self.sessions[sessionId] = nil
        }
        self.context.delete(identifier: sessionId)
    }
}

extension BackgroundUploadObserver: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        guard let upload = self.context.loadUpload(for: task.taskIdentifier), let sessionId = session.configuration.identifier else { return }

        DDLogInfo("BackgroundUploader: finished background task \(task.taskIdentifier); \(upload.key); \(upload.fileUrl.lastPathComponent)")

        let didFail = self.log(task: task, error: error)
        let finishedTask = FinishedTask(taskId: task.taskIdentifier, upload: upload, didFail: didFail)

        if var tasks = self.finishedTasks[sessionId] {
            tasks.append(finishedTask)
            self.finishedTasks[sessionId] = tasks
        } else {
            self.finishedTasks[sessionId] = [finishedTask]
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
