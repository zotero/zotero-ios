//
//  AnnotationsFilterState.swift
//  Zotero
//
//  Created by Michal Rentka on 01.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationsFilterState: ViewModelState {
    var colors: [String]
    var tags: [Tag]

    init(filter: AnnotationsFilter?) {
        self.colors = filter?.colors ?? []
        self.tags = filter?.tags ?? []
    }

    func cleanup() {}
}
