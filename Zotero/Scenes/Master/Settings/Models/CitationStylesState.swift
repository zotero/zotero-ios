//
//  CitationStylesState.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CitationStylesState: ViewModelState {
    enum Error: Swift.Error {
        case loading(Swift.Error)
        case addition(name: String, error: Swift.Error)
        case deletion(name: String, error: Swift.Error)
    }

    var styles: [CitationStyle] = []
    var error: Error?

    func cleanup() {}
}
