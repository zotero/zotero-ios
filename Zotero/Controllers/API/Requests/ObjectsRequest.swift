//
//  ObjectsRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ObjectsRequest: ApiDownloadJsonRequest {
    let groupType: SyncGroupType
    let objectType: SyncObjectType
    let version: Int?
    let file: File

    var path: String {
//        if self.objectType == .group {
//            return
//        }
        return "\(self.groupType.apiPath)/\(self.objectType.apiPath)"
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String : Any]? {
//        switch self.objectType {
//            case .
//        }
        return nil
    }
}
