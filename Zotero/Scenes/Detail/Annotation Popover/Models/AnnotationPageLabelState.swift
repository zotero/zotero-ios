//
//  AnnotationPageLabelState.swift
//  Zotero
//
//  Created by Michal Rentka on 01.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationPageLabelState: ViewModelState {
    var label: String
    var updateSubsequentPages: Bool

    func cleanup() {}
}
