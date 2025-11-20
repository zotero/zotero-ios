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
    private let disposeBag: DisposeBag
    private let processorQueue: DispatchQueue
    private let processorScheduler: SerialDispatchQueueScheduler

    private var sessions: [String: URLSession]
    private var finishedTasks: [String: [FinishedTask]]
    private var completionHandlers: [String: () -> Void]
    private var shareExtensionSessionIdDisposeBag: DisposeBag
    private var backgroundProcessingDisposeBag: DisposeBag

    init(context: BackgroundUploaderContext, processor: BackgroundUploadProcessor, backgroundTaskController: BackgroundTaskController) {
        let queue = DispatchQueue(label: "org.zotero.BackgroundUploadObserver.processorQueue", qos: .userInitiated)

        self.backgroundTaskController = backgroundTaskController
        self.processor = processor
        self.sessions = [:]
        self.finishedTasks = [:]
        self.completionHandlers = [:]
        self.context = context
        self.disposeBag = DisposeBag()
        self.shareExtensionSessionIdDisposeBag = DisposeBag()
        self.backgroundProcessingDisposeBag = DisposeBag()
        self.processorQueue = queue
        self.processorScheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.BackgroundUploadObserver.processorScheduler")

        super.init()
    }

    #if !MAINAPP
    deinit {
        self.stopObservingActiveSessionsInShareExtension()
    }
    #endif

    func startObservingInShareExtension(session: URLSession) {
        guard let sessionId = session.configuration.identifier else { return }
        inMainThread { [weak self] in
            self?.sessions[sessionId] = session
        }
    }

    func stopObservingActiveSessionsInShareExtension() {
        guard let (sessionId, _) = self.sessions.first else { return }
        self.sessions = [:]
        self.context.deleteShareExtensionSession(with: sessionId)
    }

    func stopObservingShareExtensionChanges() {
        self.shareExtensionSessionIdDisposeBag = DisposeBag()
    }

    func updateSessions() {
        inMainThread { [weak self] in
            guard let self = self else { return }
            self._updateSessions(uploadsWithTaskIds: self.context.uploadsWithTaskIds, sessionIds: Set(self.context.sessionIds), shareExtensionSessionIds: Set(self.context.shareExtensionSessionIds))
        }
    }

    private func _updateSessions(uploadsWithTaskIds: [Int: BackgroundUpload], sessionIds: Set<String>, shareExtensionSessionIds: Set<String>) {
        let (timedOutUploads, remainingSessionIds, remainingShareExtensionSessionIds) = self.invalidateTimedOut(uploads: uploadsWithTaskIds, sessions: sessionIds, andShareExtensionSessions: shareExtensionSessionIds)

        let remainingUploads = self.context.uploadsWithTaskIds
        DDLogInfo("BackgroundUploadObserver: active sessions (\(remainingSessionIds.count)) \(remainingSessionIds)")
        DDLogInfo("BackgroundUploadObserver: active uploads (\(remainingUploads.count)) \(remainingUploads.values.map({ ($0.key, $0.sessionId) }))")

        self.startObservingNew(sessionIdentifiers: remainingSessionIds)
        self.waitForShareExtensionSessionIdChange(from: remainingShareExtensionSessionIds)

        // Remove temporary upload files
        if !timedOutUploads.isEmpty {
            let deleteActions = timedOutUploads.map({ self.processor.finish(upload: $0, successful: false, queue: .main, scheduler: MainScheduler.instance) })
            Observable.concat(deleteActions).subscribe(on: MainScheduler.instance).subscribe().disposed(by: self.disposeBag)
        }
    }

    private func invalidateTimedOut(uploads: [Int: BackgroundUpload], sessions activeSessionIds: Set<String>, andShareExtensionSessions shareExtensionSessions: Set<String>) -> ([BackgroundUpload], Set<String>, Set<String>) {
        var remainingSessionIds: Set<String> = []
        var uploadsToRemove: [(Int, BackgroundUpload)] = []

        // Collect uploads that timed out and remaining active sessions of active uploads
        for (taskId, upload) in uploads {
            let timeout = self.timeout(for: upload.size)

            if Date().timeIntervalSince(upload.date) >= timeout {
                uploadsToRemove.append((taskId, upload))
                DDLogInfo("BackgroundUploadObserver: upload \(taskId); \(upload.key); \(upload.fileUrl.lastPathComponent) timed out")
                continue
            }

            if !upload.sessionId.isEmpty {
                remainingSessionIds.insert(upload.sessionId)
            }
        }

        let remainingShareExtensionSesssions = remainingSessionIds.intersection(shareExtensionSessions)

        // Remove uploads which timed out
        self.context.deleteUploads(with: uploadsToRemove.map({ $0.0 }))
        // Save remaining active sessions
        self.context.saveSessions(with: Array(remainingSessionIds))
        // Apply to share extension sessions as well
        self.context.saveShareExtensionSessions(with: Array(remainingShareExtensionSesssions))

        // Remove inactive sessions from memory so that they are not observed any more and cancel their tasks.
        let invalidatedSessionIds = activeSessionIds.subtracting(remainingSessionIds)
        for sessionId in invalidatedSessionIds {
            if let session = self.sessions[sessionId] {
                self.sessions[sessionId] = nil
                session.invalidateAndCancel()
            } else {
                URLSessionCreator.createSessionWithoutDelegate(for: sessionId).invalidateAndCancel()
            }
        }

        if !invalidatedSessionIds.isEmpty {
            DDLogInfo("BackgroundUploadObserver: invalidated sessions \(invalidatedSessionIds)")
        }

        return (uploadsToRemove.map({ $0.1 }), remainingSessionIds.subtracting(remainingShareExtensionSesssions), remainingShareExtensionSesssions)
    }

    private func startObservingNew(sessionIdentifiers identifiers: Set<String>) {
        for identifier in identifiers {
            guard self.sessions[identifier] == nil else { continue }

            DDLogInfo("BackgroundUploadObserver: start observing \(identifier)")

            let session = URLSessionCreator.createTaskSession(for: identifier, delegate: self)
            self.sessions[identifier] = session
        }
    }

    private func waitForShareExtensionSessionIdChange(from shareExtensionSessionIds: Set<String>) {
        // Reset dispose bag to cancel previous timer if it's running/
        self.shareExtensionSessionIdDisposeBag = DisposeBag()
        // If there are no session ids observed by share extension we don't need to wait for any changes.
        guard !shareExtensionSessionIds.isEmpty else { return }
        // Wait for 5 seconds and check whether some share extension finished observing its session.
        Single<Int>.timer(.seconds(5), scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.updateSessionsIfShareExtensionSessionIdsChanged(from: shareExtensionSessionIds)
                   })
                   .disposed(by: self.shareExtensionSessionIdDisposeBag)
    }

    private func updateSessionsIfShareExtensionSessionIdsChanged(from oldShareExtensionSessionIds: Set<String>) {
        let shareExtensionSessionIds = Set(self.context.shareExtensionSessionIds)

        // Check whether some session ids are not observed by its share extension anymore
        let finishedShareExtensionSessionIds = oldShareExtensionSessionIds.subtracting(shareExtensionSessionIds)

        guard !finishedShareExtensionSessionIds.isEmpty else {
            self.waitForShareExtensionSessionIdChange(from: shareExtensionSessionIds)
            return
        }

        self._updateSessions(uploadsWithTaskIds: self.context.uploadsWithTaskIds, sessionIds: Set(self.context.sessionIds), shareExtensionSessionIds: shareExtensionSessionIds)
    }

    private func timeout(for size: UInt64) -> TimeInterval {
        switch size / 1048576 {
        case 0..<5: return 600      // 10 minutes for files <5mb
        case 5..<10: return 1800    // 30 minutes for files <10mb
        case 10..<50: return 3600   // 1 hour for files < 50mb
        case 50..<100: return 10800 // 3 hours for files < 100mb
        default: return 86400       // 1 day
        }
    }

    func handleEventsForBackgroundURLSession(with identifier: String, completionHandler: @escaping () -> Void) {
        DDLogInfo("BackgroundUploadObserver: handle events for background url session \(identifier)")
        self.completionHandlers[identifier] = completionHandler
        let session = URLSessionCreator.createTaskSession(for: identifier, delegate: self)
        self.sessions[identifier] = session
    }

    func cancelAllUploads() {
        for sessionId in self.context.sessionIds {
            guard self.sessions[sessionId] == nil else { continue }
            URLSessionCreator.createSessionWithoutDelegate(for: sessionId).invalidateAndCancel()
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

        let finishAction: (BackgroundTask) -> Void = { [weak self] backgroundTask in
            // Detele processed uploads from context
            self?.context.deleteUploads(with: taskIds)
            // Call completion handler from AppDelegate
            self?.completionHandlers[sessionId]?()
            self?.completionHandlers[sessionId] = nil
            // End background task
            self?.backgroundTaskController.end(task: backgroundTask)
        }

        self.backgroundTaskController.start(task: { task in
            let actions = tasks.map({ self.processor.finish(upload: $0.upload, successful: !$0.didFail, queue: self.processorQueue, scheduler: self.processorScheduler) })
            self.backgroundProcessingDisposeBag = DisposeBag()

            DDLogError("BackgroundUploadObserver: process tasks for \(sessionId)")

            Observable.concat(actions)
                      .subscribe(on: self.processorScheduler)
                      .observe(on: MainScheduler.instance)
                      .subscribe(onError: { error in
                          DDLogError("BackgroundUploadObserver: couldn't finish tasks for \(sessionId) - \(error)")
                          finishAction(task)
                      }, onCompleted: {
                          DDLogInfo("BackgroundUploadObserver: finished tasks for \(sessionId)")
                          finishAction(task)
                      })
                      .disposed(by: self.backgroundProcessingDisposeBag)
        }, expirationHandler: {
            DDLogInfo("BackgroundUploadObserver: tasks expired for \(sessionId)")
            // Cancel upload finishing actions.
            self.backgroundProcessingDisposeBag = DisposeBag()
            // Remove upload from context so that it's processed by main app
            self.context.deleteUploads(with: taskIds)
            // Call completion handler from AppDelegate
            inMainThread {
                self.completionHandlers[sessionId]?()
                self.completionHandlers[sessionId] = nil
            }
        })
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

        session.invalidateAndCancel()
        if self.sessions[sessionId] != nil {
            self.sessions[sessionId] = nil
        }
        self.context.deleteSession(with: sessionId)
        self.context.deleteShareExtensionSession(with: sessionId)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
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

        #if !MAINAPP
        // This method is not called from share extension and since there is always just one task, we can call it here manually
        self.urlSessionDidFinishEvents(forBackgroundURLSession: session)
        #endif
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
            let responseError = AFResponseError(url: task.originalRequest?.url, httpMethod: task.originalRequest?.httpMethod, error: .createURLRequestFailed(error: someError!), headers: [:], response: "Upload failed")
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

        let responseError = AFResponseError(url: task.originalRequest?.url, httpMethod: task.originalRequest?.httpMethod, error: .responseValidationFailed(reason: .unacceptableStatusCode(code: response.statusCode)), headers: response.allHeaderFields, response: "Upload failed")
        ApiLogger.logFailedresponse(error: responseError, statusCode: response.statusCode, startData: logStartData)
        return true
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willBeginDelayedRequest request: URLRequest,
        completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void
    ) {
        completionHandler(.continueLoading, nil)
    }
}
