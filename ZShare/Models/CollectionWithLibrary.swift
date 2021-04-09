//
//  CollectionWithLibrary.swift
//  ZShare
//
//  Created by Michal Rentka on 31.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionWithLibrary: Identifiable, Equatable, Hashable {
    let collection: Collection?
    let library: Library

    var id: Int {
        var hasher = Hasher()
        if let id = self.collection?.identifier {
            hasher.combine(id)
        }
        hasher.combine(self.library.identifier)
        return hasher.finalize()
    }
}
