//
//  LibraryObject.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum LibraryIdentifier: Equatable, Hashable {
    case custom(RCustomLibraryType)
    case group(Int)
}

extension LibraryIdentifier: Codable {
    enum CodingKeys: CodingKey {
        case custom
        case group
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .custom(let type):
            try container.encode(type, forKey: .custom)
        case .group(let id):
            try container.encode(id, forKey: .group)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            let customType = try container.decode(RCustomLibraryType.self, forKey: .custom)
            self = .custom(customType)
        } catch {
            let groupId = try container.decode(Int.self, forKey: .group)
            self = .group(groupId)
        }
    }
}

enum LibraryObject {
    case custom(RCustomLibrary)
    case group(RGroup)
}

extension LibraryObject {
    var identifier: LibraryIdentifier {
        switch self {
        case .custom(let object):
            return .custom(object.type)
        case .group(let object):
            return .group(object.identifier)
        }
    }
}
