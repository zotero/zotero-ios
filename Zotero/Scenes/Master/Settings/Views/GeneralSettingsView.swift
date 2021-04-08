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
            SettingsToggleRow(title: L10n.Settings.General.showSubcollectionsTitle,
                              subtitle: L10n.Settings.General.showSubcollectionsSubtitle,
                              value: self.viewModel.binding(keyPath: \.showSubcollectionItems, action: { .setShowSubcollectionItems($0) }))
        }
        .navigationBarTitle(L10n.Settings.General.title)
    }
}

struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView()
    }
}
