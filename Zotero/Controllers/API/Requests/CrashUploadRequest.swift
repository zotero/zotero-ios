//
//  CrashUploadRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CrashUploadRequest: ApiUploadRequest {
    let url: URL = URL(string: "")!

    var httpMethod: ApiHttpMethod { return .post }

    var headers: [String : String]? {
        return nil
    }
}
