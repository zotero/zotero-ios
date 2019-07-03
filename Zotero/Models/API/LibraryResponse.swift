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
