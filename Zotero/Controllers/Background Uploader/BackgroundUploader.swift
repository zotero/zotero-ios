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

final class BackgroundUploader {
    enum Error: Swift.Error {
        case uploadFromMemoryOrStream
    }

    private let schemaVersion: Int
    private let context: BackgroundUploaderContext
    private let requestProvider: BackgroundUploaderRequestProvider

    init(context: BackgroundUploaderContext, requestProvider: BackgroundUploaderRequestProvider, schemaVersion: Int) {
        self.schemaVersion = schemaVersion
        self.requestProvider = requestProvider
        self.context = context
    }

    // MARK: - Actions

    func start(upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String], headers: [String: String]) -> Single<()> {
        return self.requestProvider.createRequest(for: upload, filename: filename, mimeType: mimeType, parameters: parameters, headers: headers, schemaVersion: self.schemaVersion)
                                   .flatMap({ [weak self] request, url, size in
                                       var newUpload = upload
                                       if upload.fileUrl != url {
                                           newUpload = upload.copy(with: url)
                                       }
                                       self?.startUpload(newUpload, request: request, size: size)
                                       return Single.just(())
                                   })
    }

    private func startUpload(_ upload: BackgroundUpload, request: URLRequest, size: Int64) {
        _ = ApiLogger.log(urlRequest: request, encoding: .url, logParams: .headers)

        let sessionId = UUID().uuidString
        let session = URLSessionCreator.createSession(for: sessionId, delegate: nil)
        self.context.save(identifier: sessionId)

        let task = session.uploadTask(with: request, fromFile: upload.fileUrl)
//        task.countOfBytesClientExpectsToSend = size
        task.earliestBeginDate = Date(timeIntervalSinceNow: 5)
        self.context.save(upload: upload.copy(with: sessionId), taskId: task.taskIdentifier)

        task.resume()
    }
}
