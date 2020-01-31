//
//  LoadPermissionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct LoadPermissionsSyncAction: SyncAction {
    typealias Result = KeyResponse

    unowned let apiClient: ApiClient

    var result: Single<KeyResponse> {
        return self.apiClient.send(request: KeyRequest())
                             .flatMap { (response, headers) in
                                 do {
                                     let json = try JSONSerialization.jsonObject(with: response, options: .allowFragments)
                                     let keyResponse = try KeyResponse(response: json)
                                     return Single.just(keyResponse)
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }
}
