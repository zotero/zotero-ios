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
                value: viewModel.binding(keyPath: \.showSubcollectionItems, action: { .setShowSubcollectionItems($0) })
            )

            SettingsToggleRow(
                title: L10n.Settings.General.showCollectionItemCounts,
                subtitle: nil,
                value: viewModel.binding(keyPath: \.showCollectionItemCounts, action: { .setShowCollectionItemCounts($0) })
            )

            SettingsToggleRow(
                title: L10n.Settings.General.openLinksInExternalBrowser,
                subtitle: nil,
                value: viewModel.binding(keyPath: \.openLinksInExternalBrowser, action: { .setOpenLinksInExternalBrowser($0) })
            )

            Picker(L10n.Settings.General.autoemptyTitle, selection: viewModel.binding(get: \.autoEmptyTrashThreshold, action: { .setAutoEmptyTrashThreshold($0) })) {
                Text(L10n.Settings.General.afterXDays(1)).tag(1)
                Text(L10n.Settings.General.afterXDays(7)).tag(7)
                Text(L10n.Settings.General.afterXDays(15)).tag(15)
                Text(L10n.Settings.General.afterXDays(30)).tag(30)
                Text(L10n.Settings.General.never).tag(0)
            }
        }
        .navigationBarTitle(L10n.Settings.General.title)
    }
}
