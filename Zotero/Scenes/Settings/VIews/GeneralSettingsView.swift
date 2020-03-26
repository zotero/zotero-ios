//
//  GeneralSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        Form {
            SettingsToggleRow(title: "Item count",
                              subtitle: "Show item count for all collections.",
                              value: self.viewModel.binding(keyPath: \.showCollectionItemCount, action: { .setShowCollectionItemCounts($0) }))
        }
    }
}

struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView()
    }
}
