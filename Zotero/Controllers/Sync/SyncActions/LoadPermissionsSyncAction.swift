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
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<KeyResponse> {
        let request = KeyRequest()
        return self.apiClient.send(request: request, queue: self.queue)
                             .mapData(httpMethod: request.httpMethod.rawValue)
                             .observe(on: self.scheduler)
                             .flatMap { data, _ in
                                 do {
                                     let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                                     let keyResponse = try KeyResponse(response: json)
                                     return Single.just(keyResponse)
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }
}
