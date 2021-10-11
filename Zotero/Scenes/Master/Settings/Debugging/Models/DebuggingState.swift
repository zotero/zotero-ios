//
//  DebuggingState.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DebuggingState: ViewModelState {
    var isLogging: Bool

    init(isLogging: Bool) {
        self.isLogging = isLogging
    }

    func cleanup() {}
}
