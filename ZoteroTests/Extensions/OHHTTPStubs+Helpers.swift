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
import OHHTTPStubsSwift

func createStub(for request: ApiRequest, ignoreBody: Bool = false, baseUrl: URL, headers: [String: String]? = nil, statusCode: Int32 = 200, jsonResponse: Any, responseAction: (() -> Void)? = nil) {
    stub(condition: request.stubCondition(with: baseUrl, ignoreBody: ignoreBody), response: { _ -> HTTPStubsResponse in
        responseAction?()
        return HTTPStubsResponse(jsonObject: jsonResponse, statusCode: statusCode, headers: headers)
    })
}

func createStub(for request: ApiRequest, ignoreBody: Bool = false, baseUrl: URL, headers: [String: String]? = nil, statusCode: Int32 = 200, url: URL) {
    stub(condition: request.stubCondition(with: baseUrl, ignoreBody: ignoreBody), response: { _ -> HTTPStubsResponse in
        return HTTPStubsResponse(fileURL: url, statusCode: statusCode, headers: headers)
    })
}

func createStub(for request: ApiRequest, ignoreBody: Bool = false, baseUrl: URL, headers: [String: String]? = nil, statusCode: Int32 = 200, xmlResponse: String) {
    stub(condition: request.stubCondition(with: baseUrl, ignoreBody: ignoreBody), response: { _ -> HTTPStubsResponse in
        return HTTPStubsResponse(data: xmlResponse.data(using: .utf8)!, statusCode: statusCode, headers: headers)
    })
}

func createStub(for request: ApiRequest, ignoreBody: Bool = false, baseUrl: URL, responseError: Error) {
    stub(condition: request.stubCondition(with: baseUrl, ignoreBody: ignoreBody), response: { _ -> HTTPStubsResponse in
        return HTTPStubsResponse(error: responseError)
    })
}

extension ApiRequest {
    func stubCondition(with baseUrl: URL, ignoreBody: Bool = false) -> HTTPStubsTestBlock {
        guard let urlRequest = (try? Convertible(request: self, baseUrl: baseUrl, token: nil, additionalHeaders: [:]).asURLRequest()),
              let url = urlRequest.url,
              let host = url.host else {
            return { _ in false }
        }

        let methodCondition: HTTPStubsTestBlock
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

        case .options:
            methodCondition = { $0.httpMethod == "OPTIONS" }

        case .propfind:
            methodCondition = { $0.httpMethod == "PROPFIND" }

        case .mkcol:
            methodCondition = { $0.httpMethod == "MKCOL" }

        default:
            methodCondition = isMethodGET()
        }

        let bodyCondition: HTTPStubsTestBlock
        if ignoreBody {
            bodyCondition = { _ in return true }
        } else {
            bodyCondition = { $0.ohhttpStubs_httpBody == urlRequest.ohhttpStubs_httpBody }
        }

        return methodCondition && isHost(host) && isPath(url.path) && isQuery(url.query) && bodyCondition
    }
}

private func isQuery(_ query: String?) -> HTTPStubsTestBlock {
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

private func compareKeys(lQuery: String, rQuery: String) -> Bool {
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
