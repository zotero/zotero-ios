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

func createStub(for request: ApiRequest, ignorePostParams: Bool = false,
                baseUrl: URL, headers: [String: Any]? = nil,
                statusCode: Int32 = 200, response: Any) {
    stub(condition: request.stubCondition(with: baseUrl,
                                          ignorePostParams: ignorePostParams), response: { _ -> OHHTTPStubsResponse in
        return OHHTTPStubsResponse(jsonObject: response, statusCode: statusCode, headers: headers)
    })
}

extension ApiRequest {
    func stubCondition(with baseUrl: URL, ignorePostParams: Bool = false) -> OHHTTPStubsTestBlock {
        guard let urlRequest = (try? Convertible(request: self, baseUrl: baseUrl,
                                                 token: nil, headers: [:]).asURLRequest()),
              let url = urlRequest.url,
              let host = baseUrl.host else {
            return { _ in false }
        }

        let methodCondition: OHHTTPStubsTestBlock
        switch self.httpMethod {
        case .delete:
            methodCondition = isMethodDELETE()
        case .get:
            methodCondition = isMethodGET()
        case .post:
            methodCondition = isMethodPOST()
        case .put:
            methodCondition = isMethodPUT()
        case .head:
            methodCondition = isMethodHEAD()
        case .patch:
            methodCondition = isMethodPATCH()
        default:
            methodCondition = isMethodGET()
        }

        let bodyCondition: OHHTTPStubsTestBlock
        if ignorePostParams {
            bodyCondition = { _ in return true }
        } else {
            bodyCondition = { $0.ohhttpStubs_httpBody == urlRequest.ohhttpStubs_httpBody }
        }

        return methodCondition&&isHost(host)&&isPath(url.path)&&isQuery(url.query)&&bodyCondition
    }
}

fileprivate func isQuery(_ query: String?) -> OHHTTPStubsTestBlock {
    return {
        if $0.url?.query == query {
            return true
        }

        if let lQuery = $0.url?.query, let rQuery = query {
            return compareKeys(lQuery: lQuery, rQuery: rQuery)
        }

        return false
    }
}

fileprivate func compareKeys(lQuery: String, rQuery: String) -> Bool {
    let keys = ["collectionKey", "itemKey", "searchKey"]
    for key in keys {
        if let lIndex = lQuery.range(of: key),
           let rIndex = rQuery.range(of: key) {
            let lKeys = lQuery[lQuery.index(lIndex.upperBound, offsetBy: 1)..<lQuery.endIndex]
            let rKeys = rQuery[rQuery.index(rIndex.upperBound, offsetBy: 1)..<rQuery.endIndex]
            return lKeys.components(separatedBy: "%2C").sorted() == rKeys.components(separatedBy: "%2C").sorted()
        }
    }
    return false
}

