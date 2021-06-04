//
//  Parsing.swift
//  Zotero
//
//  Created by Michal Rentka on 04/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct Parsing {
    enum Error: Swift.Error {
        case incompatibleValue(String)
        case missingKey(String)
        case notArray
        case notDictionary
        case notUrl
    }

    static func parse<T>(key: String, from data: [String: Any]) throws -> T {
        guard let parsed = data[key] as? T else {
            throw Error.missingKey(key)
        }
        return parsed
    }

    /// Parses `Any` response data into `Response`s if possible.
    /// - parameter response: Data to parse.
    /// - parameter createResponse: Closure to create appropriate `Response` object from `[String: Any]`.
    /// - returns: Returns a tuple with 3 values - 1. parsed responses, 2. original json objects, 3. errors of failed parses.
    static func parse<Response>(response: Any, createResponse: ([String: Any]) throws -> Response)
                                                                throws -> (responses: [Response], originals: [[String: Any]], errors: [Swift.Error]) {
        guard let array = response as? [[String: Any]] else {
            throw Error.notArray
        }

        var responses: [Response] = []
        var objects: [[String: Any]] = []
        var errors: [Swift.Error] = []

        array.forEach { data in
            do {
                let response = try createResponse(data)
                responses.append(response)
                objects.append(data)
            } catch let error {
                DDLogError("Parsing: failed to parse \(type(of: Response.self)) - \(error)")
                errors.append(error)
            }
        }

        return (responses, objects, errors)
    }
}

extension Dictionary where Key == String {
    func apiGet<T>(key: String) throws -> T {
        return try Parsing.parse(key: key, from: self)
    }
}
