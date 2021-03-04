//
//  DbStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum DbError: Error {
    case objectNotFound
    case primaryKeyUnavailable
    case primaryKeyWrongType
    case invalidRequest(String)
}

protocol DbRequest {
    var needsWrite: Bool { get }

    func process(in database: Realm) throws
}

protocol DbResponseRequest {
    associatedtype Response

    var needsWrite: Bool { get }

    func process(in database: Realm) throws -> Response
}

protocol DbCoordinator {
    func perform<Request: DbResponseRequest>(request: Request) throws -> Request.Response
    func perform(request: DbRequest) throws
    func perform(requests: [DbRequest]) throws
}

extension DbCoordinator {
    func performInAutoreleasepoolIfNeeded<Result>(invoking body: () throws -> Result) rethrows -> Result {
        if Thread.isMainThread {
            return try body()
        }
        return try autoreleasepool {
            return try body()
        }
    }
}

protocol DbStorage: class {
    func createCoordinator() throws -> DbCoordinator
    func clear()
}
