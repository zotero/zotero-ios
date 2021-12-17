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
                                   .flatMap({ request, url, size -> Single<(URL, UInt64, URLRequest, URLSession)> in
                                       return self.createSession().flatMap({ Single.just((url, size, request, $0)) })
                                   })
                                   .flatMap({ url, size, request, session -> Single<(BackgroundUpload, URLRequest, URLSession)> in
                                       let newUpload = upload.copy(withFileUrl: url, size: size, andSessionId: session.configuration.identifier!)
                                       return Single.just((newUpload, request, session))
                                   })
                                   .flatMap({ upload, request, session -> Single<()> in
                                       self.start(upload: upload, request: request, session: session)
                                       return Single.just(())
                                   })
    }

    private func createSession() -> Single<URLSession> {
        return Single.create { [weak self] subscriber in
            let sessionId = UUID().uuidString
            let session = URLSessionCreator.createSession(for: sessionId, delegate: nil)
            self?.context.saveSession(with: sessionId)
            subscriber(.success(session))
            return Disposables.create()
        }
    }

    private func start(upload: BackgroundUpload, request: URLRequest, session: URLSession) {
        _ = ApiLogger.log(urlRequest: request, encoding: .url, logParams: .headers)

        let task = session.uploadTask(with: request, fromFile: upload.fileUrl)
        task.countOfBytesClientExpectsToSend = Int64(upload.size)
        task.earliestBeginDate = Date(timeIntervalSinceNow: 5)
        self.context.save(upload: upload, taskId: task.taskIdentifier)

        task.resume()
    }
}
