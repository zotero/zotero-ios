//
//  SettingsListView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SettingsListView: View {
    weak var coordinatorDelegate: MasterSettingsCoordinatorDelegate?

    var body: some View {
        Form {
            Section {
                NavigationLink(destination: ProfileView()) {
                    Text(L10n.Settings.profile)
                }
            }

            Section {
//                NavigationLink(destination: GeneralSettingsView()) {
//                    Text(L10n.Settings.general)
//                }

//                NavigationLink(destination: SyncSettingsView()) {
//                    Text(L10n.Settings.sync)
//                }

//                NavigationLink(destination: TranslatorsSettingsView()) {
//                    Text(L10n.Settings.translators)
//                }

                FakeNavigationLink(title: L10n.aboutBeta) {
                    self.coordinatorDelegate?.showAboutBeta()
                }

                NavigationLink(destination: DebugSettingsView()) {
                    Text(L10n.Settings.debug)
                }

                NavigationLink(destination: SavingSettingsView()) {
                    Text(L10n.Settings.Saving.title)
                }

                NavigationLink(destination: StorageSettingsView()) {
                    Text(L10n.Settings.storage)
                }

                FakeNavigationLink(title: L10n.privacyPolicy) {
                    self.coordinatorDelegate?.showPrivacyPolicy()
                }
            }
        }
    }
}

struct FakeNavigationLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action, label: {
            HStack {
                Text(self.title)
                    .foregroundColor(.black)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Font.system(size: 14, weight: .bold, design: .default))
                    .foregroundColor(Color(UIColor.systemGray4))
            }
        })
    }
}

struct SettingsListView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsListView()
    }
}
