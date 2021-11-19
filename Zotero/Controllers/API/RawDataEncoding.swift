//
//  RawDataEncoding.swift
//  Zotero
//
//  Created by Michal Rentka on 06.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire

/// Extenstion that allows data be sent as a request parameters
extension Data {
    /// Convert the receiver array to a `Parameters` object.
    func asParameters() -> Parameters {
        return [RawDataEncoding.parametersKey: self]
    }
}

/// Convert the parameters into a json array, and it is added as the request body.
/// The array must be sent as parameters using its `asParameters` method.
struct RawDataEncoding: ParameterEncoding {
    static let parametersKey = "dataParametersKey"

    public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        var urlRequest = try urlRequest.asURLRequest()
        if let data = parameters?[RawDataEncoding.parametersKey] as? Data {
            urlRequest.httpBody = data
        }
        return urlRequest
    }
}
