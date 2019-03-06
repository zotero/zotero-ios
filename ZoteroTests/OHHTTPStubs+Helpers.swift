//
//  OHHTTPStubs+Helpers.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 05/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Alamofire
import OHHTTPStubs

extension ApiRequest {
    func stubCondition(with baseUrl: URL) -> OHHTTPStubsTestBlock {
        guard let url = (try? Convertible(request: self, baseUrl: baseUrl,
                                          token: nil, headers: [:]).asURLRequest())?.url,
              let host = baseUrl.host else {
            return { _ in false }
        }
        return isHost(host)&&isPath(url.path)&&isQuery(url.query)
    }
}

public func isQuery(_ query: String?) -> OHHTTPStubsTestBlock {
    return { $0.url?.query == query }
}

