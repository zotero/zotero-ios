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

            HStack {
                Text(L10n.Settings.General.autoemptyTitle)
                    .foregroundColor(Color(UIColor.label))

                Spacer()

                Menu(thresholdString(for: viewModel.state.autoEmptyTrashThreshold)) {
                    Button(L10n.Settings.General.afterOneDay, action: { viewModel.process(action: .setAutoEmptyTrashThreshold(1)) })
                    Button(L10n.Settings.General.afterXDays(7), action: { viewModel.process(action: .setAutoEmptyTrashThreshold(7)) })
                    Button(L10n.Settings.General.afterXDays(15), action: { viewModel.process(action: .setAutoEmptyTrashThreshold(15)) })
                    Button(L10n.Settings.General.afterXDays(30), action: { viewModel.process(action: .setAutoEmptyTrashThreshold(30)) })
                    Button(L10n.Settings.General.never, action: { viewModel.process(action: .setAutoEmptyTrashThreshold(0)) })
                }
                .foregroundColor(Color(UIColor.systemGray))

                Image(systemName: "chevron.right")
                    .foregroundColor(Color(UIColor.systemGray))
                    .font(.body.weight(.semibold))
                    .imageScale(.small)
                    .opacity(0.7)
            }
        }
        .navigationBarTitle(L10n.Settings.General.title)
    }

    private func thresholdString(for threshold: Int) -> String {
        switch threshold {
        case 0:
            return L10n.Settings.General.never

        case 1:
            return L10n.Settings.General.afterOneDay

        default:
            return L10n.Settings.General.afterXDays(threshold)
        }
    }
}

struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView()
    }
}
 
