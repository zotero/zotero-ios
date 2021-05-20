//
//  CitationsState.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CitationsState: ViewModelState {

    var styles: Results<RStyle>?
    var stylesToken: NotificationToken?

    var remoteStyles: [CitationStyle]
    var filteredRemoteStyles: [CitationStyle]?
    var loadingRemoteStyles: Bool
    var loadingError: Error?

    init() {
        self.remoteStyles = []
        self.loadingRemoteStyles = false
    }

    func cleanup() {}
}
