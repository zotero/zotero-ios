//
//  LibraryObject.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift
import RxSwift

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

extension LibraryObject {
    func observe(changes changed: @escaping (Library) -> Void) -> (Library, NotificationToken?) {
        switch self {
        case .custom(let library): // No need to observe main library
            return (Library(customLibrary: library), nil)

        case .group(let group):
            let token = group.observe(keyPaths: RGroup.observableKeypathsForAccessRights, on: .main) { (change: ObjectChange<RGroup>) in
                switch change {
                case .change(let group, _):
                    changed(Library(group: group))

                case .deleted, .error:
                    break
                }
            }
            return (Library(group: group), token)
        }
    }
}
