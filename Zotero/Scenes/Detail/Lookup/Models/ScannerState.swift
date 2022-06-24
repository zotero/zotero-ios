//
//  ScannerState.swift
//  Zotero
//
//  Created by Michal Rentka on 16.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ScannerState: ViewModelState {
    var barcodes: Set<String>

    init() {
        self.barcodes = []
    }

    func cleanup() {}
}
