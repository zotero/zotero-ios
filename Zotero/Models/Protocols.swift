//
//  Protocols.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol IdentifiableObject: class {
    associatedtype IdType: Hashable&Decodable

    var identifier: IdType { get set }
}

protocol VersionableObject: class {
    var version: Int { get set }
    var needsSync: Bool { get set }
}
