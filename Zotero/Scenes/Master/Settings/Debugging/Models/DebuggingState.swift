//
//  DebuggingState.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct DebuggingState: ViewModelState {
    var isLogging: Bool
    var fileMonitor: FileMonitor?
    var numberOfLines: Int
    var disposeBag: DisposeBag?

    init(isLogging: Bool) {
        self.isLogging = isLogging
        self.numberOfLines = 0
    }

    func cleanup() {}
}
