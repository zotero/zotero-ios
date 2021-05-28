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

    var isObjectNotFound: Bool {
        switch self {
        case .objectNotFound: return true
        default: return false
        }
    }
}

protocol DbRequest {
    var needsWrite: Bool { get }
    var ignoreNotificationTokens: [NotificationToken]? { get }

    func process(in database: Realm) throws
}

protocol DbResponseRequest {
    associatedtype Response

    var needsWrite: Bool { get }
    var ignoreNotificationTokens: [NotificationToken]? { get }

    func process(in database: Realm) throws -> Response
}

protocol DbCoordinator {
    func perform<Request: DbResponseRequest>(request: Request) throws -> Request.Response
    func perform(request: DbRequest) throws
    func perform(requests: [DbRequest]) throws
}

protocol DbStorage: AnyObject {
    func createCoordinator() throws -> DbCoordinator
    func clear()

    var willPerformBetaWipe: Bool { get }
}
