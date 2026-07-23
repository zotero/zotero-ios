//
//  URLSessionCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 15.12.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class URLSessionCreator {
    static func createBackgroundConfiguration(
        for identifier: String,
        isDiscretionary: Bool = false,
        httpMaximumConnectionsPerHost: Int? = nil
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.timeoutIntervalForRequest = ApiConstants.requestTimeout
        configuration.timeoutIntervalForResource = ApiConstants.resourceTimeout
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = isDiscretionary
        if let httpMaximumConnectionsPerHost {
            configuration.httpMaximumConnectionsPerHost = httpMaximumConnectionsPerHost
        }
        return configuration
    }

    static func createSessionWithoutDelegate(for identifier: String) -> URLSession {
        return URLSession(configuration: createBackgroundConfiguration(for: identifier), delegate: nil, delegateQueue: nil)
    }

    static func createSession(for identifier: String, delegate: URLSessionDelegate) -> URLSession {
        return URLSession(configuration: createBackgroundConfiguration(for: identifier), delegate: BackgroundSessionDelegate(forwardingDelegate: delegate), delegateQueue: nil)
    }

    static func createTaskSession(for identifier: String, delegate: URLSessionTaskDelegate) -> URLSession {
        return URLSession(configuration: createBackgroundConfiguration(for: identifier), delegate: BackgroundSessionTaskDelegate(forwardingTaskDelegate: delegate), delegateQueue: nil)
    }

    static func createDownloadSession(for identifier: String, delegate: URLSessionDownloadDelegate, httpMaximumConnectionsPerHost: Int) -> URLSession {
        return URLSession(
            configuration: createBackgroundConfiguration(for: identifier, httpMaximumConnectionsPerHost: httpMaximumConnectionsPerHost),
            delegate: BackgroundSessionDownloadDelegate(forwardingDownloadDelegate: delegate),
            delegateQueue: nil
        )
    }
}

class BackgroundSessionDelegate: NSObject {
    weak var forwardingDelegate: URLSessionDelegate?
    weak var forwardingTaskDelegate: URLSessionTaskDelegate?
    weak var forwardingDownloadDelegate: URLSessionDownloadDelegate?

    init(forwardingDelegate: URLSessionDelegate) {
        self.forwardingDelegate = forwardingDelegate
    }
}

class BackgroundSessionTaskDelegate: BackgroundSessionDelegate {
    init(forwardingTaskDelegate: URLSessionTaskDelegate) {
        super.init(forwardingDelegate: forwardingTaskDelegate)
        self.forwardingTaskDelegate = forwardingTaskDelegate
    }
}

class BackgroundSessionDownloadDelegate: BackgroundSessionTaskDelegate {
    init(forwardingDownloadDelegate: URLSessionDownloadDelegate) {
        super.init(forwardingTaskDelegate: forwardingDownloadDelegate)
        self.forwardingDownloadDelegate = forwardingDownloadDelegate
    }
}

extension BackgroundSessionDelegate: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        forwardingDelegate?.urlSessionDidFinishEvents?(forBackgroundURLSession: session)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        forwardingDelegate?.urlSession?(session, didBecomeInvalidWithError: error)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let forwardingDelegate, forwardingDelegate.responds(to: #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        forwardingDelegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
    }
}

extension BackgroundSessionTaskDelegate: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let forwardingTaskDelegate, forwardingTaskDelegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:))) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        forwardingTaskDelegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        forwardingTaskDelegate?.urlSession?(session, task: task, didCompleteWithError: error)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willBeginDelayedRequest request: URLRequest,
        completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void
    ) {
        guard let forwardingTaskDelegate, forwardingTaskDelegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:willBeginDelayedRequest:completionHandler:))) else {
            completionHandler(.continueLoading, nil)
            return
        }
        forwardingTaskDelegate.urlSession?(session, task: task, willBeginDelayedRequest: request, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        forwardingTaskDelegate?.urlSession?(session, taskIsWaitingForConnectivity: task)
    }
}

extension BackgroundSessionDownloadDelegate: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        forwardingDownloadDelegate?.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        forwardingDownloadDelegate?.urlSession?(
            session,
            downloadTask: downloadTask,
            didWriteData: bytesWritten,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite
        )
    }
}
