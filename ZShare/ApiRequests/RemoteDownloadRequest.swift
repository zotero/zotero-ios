//
//  DownloadRequest.swift
//  ZShare
//
//  Created by Michal Rentka on 21/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RemoteDownloadRequest: ApiDownloadRequest {
    var downloadUrl: URL

    var path: String

    var httpMethod: ApiHttpMethod

    var parameters: [String : Any]?

    var encoding: ApiParameterEncoding

    var headers: [String : String]?


}
