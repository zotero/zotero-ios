//
//  BackgroundUploader.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import RxSwift
import RxCocoa

class BackgroundUploader: NSObject {
    static let shared = BackgroundUploader()
    private let context = BackgroundUploaderContext()
    private let fileStorage: FileStorage = FileStorageController()
    private let disposeBag = DisposeBag()

    private var session: URLSession!
    private var finishedUploads: [BackgroundUpload] = []

    var uploadProcessor: BackgroundUploadProcessor?
    var backgroundCompletionHandler: (() -> Void)?

    override init() {
        super.init()

        let configuration = URLSessionConfiguration.background(withIdentifier: "org.zotero.background.upload.session")
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description]
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.networkServiceType = .background
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    // MARK: - Actions

    func upload(_ upload: BackgroundUpload,
                filename: String,
                mimeType: String,
                parameters: [String: String],
                headers: [String: String],
                completion: @escaping (Error?) -> Void) {
        self.createMultipartformRequest(for: upload,
                                        filename: filename,
                                        mimeType: mimeType,
                                        parameters: parameters,
                                        headers: headers,
                                        completion: { [weak self] result in
                                            switch result {
                                            case .failure(let error):
                                                completion(error)
                                            case .success(let request, let fileUrl):
                                                self?.startUpload(upload, request: request, fileUrl: fileUrl)
                                                completion(nil)
                                            }
                                        })
    }

    private func startUpload(_ upload: BackgroundUpload, request: URLRequest, fileUrl: URL) {
        let task = self.session.uploadTask(with: request, fromFile: fileUrl)
        self.context.saveUpload(upload, taskId: task.taskIdentifier)
        task.resume()
    }

    private func createMultipartformRequest(for upload: BackgroundUpload, filename: String, mimeType: String, parameters: [String: String]?, headers: [String: String]? = nil, completion: @escaping (Swift.Result<(URLRequest, URL), Error>) -> Void) {
        Alamofire.upload(multipartFormData: { data in
                             if let parameters = parameters {
                                 parameters.forEach { (key, value) in
                                     if let stringData = value.data(using: .utf8) {
                                         data.append(stringData, withName: key)
                                     }
                                 }
                             }
                             data.append(upload.fileUrl, withName: "file", fileName: filename, mimeType: mimeType)
                         },
                         usingThreshold: 0,
                         to: "http://",
                         method: .post,
                         headers: headers) { result in
                             switch result {
                             case .failure(let error):
                                 completion(.failure(error))
                             case .success(let request, _, let streamFileURL):
                                 request.suspend()
                                 defer { request.cancel() }

                                 guard let fileUrl = streamFileURL else {
                                    completion(.failure(AFError.multipartEncodingFailed(reason: .bodyPartURLInvalid(url: upload.fileUrl))))
                                    return
                                 }

                                 do {
                                     let file = Files.file(from: fileUrl)
                                     let newFile = Files.uploadFile(from: fileUrl)
                                     try self.fileStorage.move(from: file, to: newFile)

                                     var newRequest = URLRequest(url: upload.remoteUrl)
                                     newRequest.httpMethod = "POST"
                                     if let headers = request.request?.allHTTPHeaderFields {
                                         for (key, value) in headers {
                                             newRequest.addValue(value, forHTTPHeaderField: key)
                                         }
                                     }
                                    completion(.success((newRequest, newFile.createUrl())))
                                 } catch let error {
                                    completion(.failure(error))
                                 }
                             }
                         }
    }
}

extension BackgroundUploader: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard !self.finishedUploads.isEmpty,
              let processor = self.uploadProcessor else {
            self.completeBackgroundSession()
            return
        }

        let actions = self.finishedUploads.map({ processor.finish(upload: $0) })
        self.finishedUploads = []

        Observable.concat(actions)
                  .subscribe(onError: { [weak self] error in
                      self?.completeBackgroundSession()
                  }, onCompleted: { [weak self] in
                      self?.completeBackgroundSession()
                  })
                  .disposed(by: self.disposeBag)
    }

    private func completeBackgroundSession() {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}

extension BackgroundUploader: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let upload = self.context.loadUpload(for: task.taskIdentifier) else { return }
        self.finishedUploads.append(upload)
        self.context.deleteUpload(with: task.taskIdentifier)
    }
}
