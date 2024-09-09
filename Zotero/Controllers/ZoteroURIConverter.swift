//
//  ZoteroURIConverter.swift
//  Zotero
//
//  Created by Michal Rentka on 04.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class ZoteroURIConverter {
    func convert(uri: String) -> (String, LibraryIdentifier)? {
        guard let components = URLComponents(string: uri) else { return nil }
        let pathComponents = components.path.components(separatedBy: "/")
        guard pathComponents.count == 5 else { return nil }
        switch pathComponents[1] {
        case "users":
            return (pathComponents[4], .custom(.myLibrary))

        case "groups":
            guard let groupId = Int(pathComponents[2]) else { return nil }
            return (pathComponents[4], .group(groupId))

        default:
            return nil
        }
    }
}
