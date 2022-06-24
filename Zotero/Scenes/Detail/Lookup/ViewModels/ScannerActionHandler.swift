//
//  ScannerActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

final class ScannerActionHandler: ViewModelActionHandler {
    typealias State = ScannerState
    typealias Action = ScannerAction


    func process(action: ScannerAction, in viewModel: ViewModel<ScannerActionHandler>) {
        switch action {
        case .setBarcodes(let barcodes):
            self.update(viewModel: viewModel) { state in
                for barcode in barcodes {
                    state.barcodes.insert(barcode)
                }
            }
        }
    }
}
