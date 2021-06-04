//
//  CitationStylesSearchState.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CitationStylesSearchState: ViewModelState {
    var styles: [RemoteCitationStyle]
    var filtered: [RemoteCitationStyle]?
    var loading: Bool
    var error: Error?

    init() {
        self.styles = []
        self.loading = false
    }

    func cleanup() {}
}
