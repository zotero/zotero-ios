//
//  CollectionDifference+Separated.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

typealias SeparatedCollectionDifference = (insertions: [Int], deletions: [Int])

extension CollectionDifference {
    var separated: SeparatedCollectionDifference {
        var insertions: [Int] = []
        var deletions: [Int] = []
        self.forEach { change in
            switch change {
            case .insert(let offset, _, _):
                insertions.append(offset)

            case .remove(let offset, _, _):
                deletions.append(offset)
            }
        }
        return (insertions, deletions)
    }
}
