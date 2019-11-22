//
//  BackgroundApiClient.swift
//  Zotero
//
//  Created by Michal Rentka on 22/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import RxAlamofire
import RxSwift

protocol BackgroundApiClient: class {
    func set(authToken: String?)
    func download(request: ApiDownloadRequest) -> Observable<RxProgress>
    func upload(request: ApiRequest, multipartFormData: @escaping (MultipartFormData) -> Void) -> Single<UploadRequest>
}
