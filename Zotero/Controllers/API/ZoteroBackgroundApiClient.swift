//
//  ZoteroBackgroundApiClient.swift
//  Zotero
//
//  Created by Michal Rentka on 22/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjack
import RxAlamofire
import RxSwift

class ZoteroBackgroundApiClient: BackgroundApiClient {
    private let url: URL
    private let manager: SessionManager

    private var token: String?

    init(baseUrl: String, identifier: String, headers: [String: String]? = nil) {
        guard let url = URL(string: baseUrl) else {
            fatalError("Incorrect base url provided for ZoteroApiClient")
        }

        self.url = url

        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.httpAdditionalHeaders = headers
        configuration.sharedContainerIdentifier = "group.org.zotero.ios.Zotero"

        self.manager = SessionManager(configuration: configuration)
    }

    func set(authToken: String?) {
        self.token = authToken
    }

    func download(request: ApiDownloadRequest) -> Observable<RxProgress> {
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        return self.manager.rx.download(convertible) { _, _ -> (destinationURL: URL, options: DownloadRequest.DownloadOptions) in
                                  return (request.downloadUrl, [.createIntermediateDirectories, .removePreviousFile])
                              }
                              .flatMap { downloadRequest -> Observable<RxProgress> in
                                  return downloadRequest.rx.progress()
                              }
    }

    func upload(request: ApiRequest, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<UploadRequest> {
        return Single.create { [weak self] subscriber in
            guard let `self` = self else {
                subscriber(.error(ZoteroApiError.expired))
                return Disposables.create()
            }


            let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)

            let method = HTTPMethod(rawValue: request.httpMethod.rawValue)!
            self.manager.upload(multipartFormData: multipartFormData,
                                to: convertible,
                                method: method,
                                headers: request.headers,
                                encodingCompletion: { result in
                switch result {
                case .success(let request, _, _):
                    subscriber(.success(request))
                case .failure(let error):
                    subscriber(.error(error))
                }
            })

            return Disposables.create()
        }
    }
}
