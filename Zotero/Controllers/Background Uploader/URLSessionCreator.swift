//
//  URLSessionCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 15.12.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class URLSessionCreator {
    static func createSession(
        for identifier: String,
        forwardingDelegate: URLSessionDelegate? = nil,
        forwardingTaskDelegate: URLSessionTaskDelegate? = nil,
        forwardingDownloadDelegate: URLSessionDownloadDelegate? = nil,
        delegateQueue: OperationQueue? = nil,
        isDiscretionary: Bool = false,
        httpMaximumConnectionsPerHost: Int? = nil
    ) -> URLSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.timeoutIntervalForRequest = ApiConstants.requestTimeout
        configuration.timeoutIntervalForResource = ApiConstants.resourceTimeout
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = isDiscretionary
        if let httpMaximumConnectionsPerHost {
            configuration.httpMaximumConnectionsPerHost = httpMaximumConnectionsPerHost
        }
        let session = URLSession(configuration: configuration, delegate: BackgroundSessionDelegate(), delegateQueue: delegateQueue)
        if let backgroundSessionDelegate = session.delegate as? BackgroundSessionDelegate {
            backgroundSessionDelegate.forwardingDelegate = forwardingDelegate
            backgroundSessionDelegate.forwardingTaskDelegate = forwardingTaskDelegate
            backgroundSessionDelegate.forwardingDownloadDelegate = forwardingDownloadDelegate
        }
        return session
    }
}

final class BackgroundSessionDelegate: NSObject {
    weak var forwardingDelegate: URLSessionDelegate?
    weak var forwardingTaskDelegate: URLSessionTaskDelegate?
    weak var forwardingDownloadDelegate: URLSessionDownloadDelegate?
}

extension BackgroundSessionDelegate: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        forwardingDelegate?.urlSessionDidFinishEvents?(forBackgroundURLSession: session)
    }
}

extension BackgroundSessionDelegate: URLSessionTaskDelegate {
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
}

extension BackgroundSessionDelegate: URLSessionDownloadDelegate {
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
