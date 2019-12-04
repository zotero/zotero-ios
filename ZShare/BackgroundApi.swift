//
//  BackgroundApi.swift
//  ZShare
//
//  Created by Michal Rentka on 04/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift
import RxAlamofire

class BackgroundApi {
    static let shared = BackgroundApi()

    let client: ApiClient
    let disposeBag: DisposeBag

    init() {
        let bgConfiguration = URLSessionConfiguration.background(withIdentifier: "org.zotero.ios.Zotero.ZShare")
        bgConfiguration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description]
        bgConfiguration.sharedContainerIdentifier = AppGroup.identifier

        self.client = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: bgConfiguration)
        self.disposeBag = DisposeBag()
    }
}
