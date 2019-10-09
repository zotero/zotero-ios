//
//  ItemsSortType.swift
//  Zotero
//
//  Created by Michal Rentka on 09/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ItemsSortType {
    enum Field {
        case title
    }
    
    var field: Field
    var ascending: Bool
}

extension ItemsSortType: SortType {
    var descriptors: [SortDescriptor] {
        switch self.field {
        case .title:
            return [SortDescriptor(keyPath: "title", ascending: self.ascending)]
        }
    }
}
