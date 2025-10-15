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
    case invalidRequest(String)

    var isObjectNotFound: Bool {
        switch self {
        case .objectNotFound: return true
        default: return false
        }
    }
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

protocol DbStorage: AnyObject {
    func perform(on queue: DispatchQueue, with coordinatorAction: (DbCoordinator) throws -> Void) throws
    func perform(on queue: DispatchQueue, refreshRealm: Bool, invalidateRealm: Bool, with coordinatorAction: (DbCoordinator) throws -> Void) throws
    func perform<Request>(request: Request, on queue: DispatchQueue) throws -> Request.Response where Request: DbResponseRequest
    func perform<Request>(request: Request, on queue: DispatchQueue, refreshRealm: Bool) throws -> Request.Response where Request: DbResponseRequest
    func perform<Request>(request: Request, on queue: DispatchQueue, invalidateRealm: Bool) throws -> Request.Response where Request: DbResponseRequest
    func perform<Request>(request: Request, on queue: DispatchQueue, invalidateRealm: Bool, refreshRealm: Bool) throws -> Request.Response where Request: DbResponseRequest
    func perform(request: DbRequest, on queue: DispatchQueue) throws
    func perform(writeRequests requests: [DbRequest], on queue: DispatchQueue) throws
    func clear()

    var willPerformBetaWipe: Bool { get }
}

protocol DbCoordinator {
    func perform<Request: DbResponseRequest>(request: Request) throws -> Request.Response
    func perform(request: DbRequest) throws
    func perform(writeRequests requests: [DbRequest]) throws
    func invalidate()
}
