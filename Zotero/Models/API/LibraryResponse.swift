//
//  LibraryResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LibraryResponse: Decodable {
    let id: Int
    let name: String
    let type: String
    let links: LinksResponse

    var libraryId: Int {
        if self.libraryType == .user {
            return RLibrary.myLibraryId
        }
        return self.id
    }

    var libraryType: LibraryType? {
        switch self.type {
        case "user":
            return .user
        case "group":
            return .group
        default:
            return nil
        }
    }
}
