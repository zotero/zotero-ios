//
//  DbStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

protocol DbRequest {
    func process(in database: Realm) throws
}

protocol DbResponseRequest {
    associatedtype Response

    func process(in database: Realm) -> Response
}

protocol DbCoordinator {
    func perform<Request: DbResponseRequest>(request: Request) -> Request.Response
    func perform<Request: DbRequest>(request: Request) throws
}

protocol DbStorage: class {
    func createCoordinator() throws -> DbCoordinator
}
