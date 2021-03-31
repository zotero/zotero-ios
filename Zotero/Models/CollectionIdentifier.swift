//
//  CollectionIdentifier.swift
//  Zotero
//
//  Created by Michal Rentka on 23.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CollectionIdentifier: Identifiable, Equatable, Hashable {
    enum CustomType: Int, Equatable, Hashable, Codable {
        case all, trash, publications
    }

    case collection(String)
    case search(String)
    case custom(CustomType)

    var id: String {
        switch self {
        case .custom(let type):
            switch type {
            case .all: return "all"
            case .publications: return "publications"
            case .trash: return "trash"
            }
        case .collection(let key):
            return "c_" + key
        case .search(let key):
            return "s_" + key
        }
    }
}

extension CollectionIdentifier {
    var isCustom: Bool {
        switch self {
        case .custom: return true
        default: return false
        }
    }

    var isCollection: Bool {
        switch self {
        case .collection: return true
        default: return false
        }
    }

    var isSearch: Bool {
        switch self {
        case .search: return true
        default: return false
        }
    }

    var key: String? {
        switch self {
        case .collection(let key): return key
        case .search(let key): return key
        case .custom: return nil
        }
    }

    func isSameType(as identifier: CollectionIdentifier) -> Bool {
        switch (self, identifier) {
        case (.collection, .collection), (.search, .search), (.custom, .custom): return true
        default: return false
        }
    }
}

extension CollectionIdentifier: Codable {
    enum Error: Swift.Error {
        case unknownCollectionId
    }

    enum CodingKeys: CodingKey {
        case collection
        case custom
        case search
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .custom(let type):
            try container.encode(type, forKey: .custom)
        case .collection(let key):
            try container.encode(key, forKey: .collection)
        case .search(let key):
            try container.encode(key, forKey: .search)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let key = try? container.decode(String.self, forKey: .collection) {
            self = .collection(key)
        } else if let key = try? container.decode(String.self, forKey: .search) {
            self = .search(key)
        } else if let type = try? container.decode(CollectionIdentifier.CustomType.self, forKey: .custom) {
            self = .custom(type)
        } else {
            throw Error.unknownCollectionId
        }
    }
}
