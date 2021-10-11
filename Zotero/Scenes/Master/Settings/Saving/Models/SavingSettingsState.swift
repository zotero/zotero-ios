//
//  SavingSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SavingSettingsState: ViewModelState {
    var includeTags: Bool {
        get {
            return Defaults.shared.shareExtensionIncludeTags
        }

        set {
            Defaults.shared.shareExtensionIncludeTags = newValue
        }
    }
    var includeAttachment: Bool {
        get {
            return Defaults.shared.shareExtensionIncludeAttachment
        }

        set {
            Defaults.shared.shareExtensionIncludeAttachment = newValue
        }
    }

    func cleanup() {}
}
