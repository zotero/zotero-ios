//
//  JsonAndUrlEncoding.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire

/// Convert the parameters into a json array, and it is added as the request body.
/// The array must be sent as parameters using its `asParameters` method.
struct JsonAndUrlEncoding: ParameterEncoding {
    static let jsonKey = "jsonKey"
    static let urlKey = "urlKey"

    /// The options for writing the parameters as JSON data.
    public let options: JSONSerialization.WritingOptions

    /// Creates a new instance of the encoding using the given options
    ///
    /// - parameter options: The options used to encode the json. Default is `[]`
    ///
    /// - returns: The new instance
    public init(options: JSONSerialization.WritingOptions = []) {
        self.options = options
    }

    public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        var urlRequest = try urlRequest.asURLRequest()

        guard let parameters = parameters else {
            return urlRequest
        }

        if let json = parameters[JsonAndUrlEncoding.json] {
            
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: array, options: self.options)

            if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            urlRequest.httpBody = data
        } catch {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: error))
        }

        return urlRequest
    }
}
