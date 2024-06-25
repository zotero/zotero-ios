//
//  GeneralSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<GeneralSettingsActionHandler>

    var body: some View {
        Form {
            SettingsToggleRow(
                title: L10n.Settings.General.showSubcollectionsTitle,
                subtitle: nil,
                value: self.viewModel.binding(keyPath: \.showSubcollectionItems, action: { .setShowSubcollectionItems($0) })
            )

            SettingsToggleRow(
                title: L10n.Settings.General.showCollectionItemCounts,
                subtitle: nil,
                value: self.viewModel.binding(keyPath: \.showCollectionItemCounts, action: { .setShowCollectionItemCounts($0) })
            )

            SettingsToggleRow(
                title: L10n.Settings.General.openLinksInExternalBrowser,
                subtitle: nil,
                value: self.viewModel.binding(keyPath: \.openLinksInExternalBrowser, action: { .setOpenLinksInExternalBrowser($0) })
            )
        }
        .navigationBarTitle(L10n.Settings.General.title)
    }
}

struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView()
    }
}
