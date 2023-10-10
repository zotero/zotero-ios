//
//  LibraryResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LibraryResponse {
    let id: Int
    let name: String
    let type: String
    let links: LinksResponse?

    init(response: [String: Any]) throws {
        self.id = try response.apiGet(key: "id", errorLogMessage: "LibraryResponse missing key \"id\"")
        self.name = try response.apiGet(key: "name", errorLogMessage: "LibraryResponse missing key \"name\"")
        self.type = try response.apiGet(key: "type", errorLogMessage: "LibraryResponse missing key \"type\"")
        self.links = try (response["links"] as? [String: Any]).flatMap({ try LinksResponse(response: $0) })
    }

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
