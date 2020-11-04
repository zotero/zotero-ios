//
//  StorageSettingsEmptyView.swift
//  Zotero
//
//  Created by Michal Rentka on 04/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct StorageSettingsEmptyView: View {
    var body: some View {
        Text(L10n.Errors.Settings.storage)
    }
}

struct StorageSettingsEmptyView_Previews: PreviewProvider {
    static var previews: some View {
        StorageSettingsEmptyView()
    }
}
