//
//  SavingSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 09.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SavingSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<SettingsActionHandler>

    var body: some View {
        Form {
            SettingsToggleRow(title: L10n.Settings.Saving.filesTitle, subtitle: L10n.Settings.Saving.filesMessage,
                              value: self.viewModel.binding(keyPath: \.includeAttachment, action: { .setIncludeAttachment($0) }))
            SettingsToggleRow(title: L10n.Settings.Saving.tagsTitle, subtitle: L10n.Settings.Saving.tagsMessage,
                              value: self.viewModel.binding(keyPath: \.includeTags, action: { .setIncludeTags($0) }))
        }
        .navigationBarTitle(L10n.Settings.Saving.title)
    }
}

struct SavingSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SavingSettingsView()
    }
}
