//
//  GeneralSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct GeneralSettingsState: ViewModelState {
    var showSubcollectionItems: Bool {
        get {
            return Defaults.shared.showSubcollectionItems
        }

        set {
            Defaults.shared.showSubcollectionItems = newValue
        }
    }

    var showCollectionItemCounts: Bool {
        get {
            return Defaults.shared.showCollectionItemCounts
        }

        set {
            Defaults.shared.showCollectionItemCounts = newValue
        }
    }

    var openLinksInExternalBrowser: Bool {
        get {
            return Defaults.shared.openLinksInExternalBrowser
        }

        set {
            Defaults.shared.openLinksInExternalBrowser = newValue
        }
    }

    func cleanup() {}
}
