//
//  ManualLookupState.swift
//  Zotero
//
//  Created by Michal Rentka on 23.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ManualLookupState: ViewModelState {
    var scannedText: String?
    let restoreLookupState: Bool

    init(restoreLookupState: Bool) {
        self.restoreLookupState = restoreLookupState
    }

    mutating func cleanup() {
        self.scannedText = nil
    }
}
