//
//  LibraryResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LibraryResponse: Codable {
    let id: Int
    let name: String
    let type: String
    let links: LinksResponse?

    init(id: Int, name: String, type: String, links: LinksResponse?) {
        self.id = id
        self.name = name
        self.type = type
        self.links = links
    }

    init(libraryId: LibraryIdentifier) {
        self.name = ""
        self.links = nil

        switch libraryId {
        case .custom:
            self.id = 0
            self.type = "user"
        case .group(let id):
            self.id = id
            self.type = "group"
        }
    }

    var libraryId: LibraryIdentifier? {
        switch self.type {
        case "user":
            return .custom(.myLibrary)
        case "group":
            return .group(self.id)
        default:
            return nil
        }
    }
}
