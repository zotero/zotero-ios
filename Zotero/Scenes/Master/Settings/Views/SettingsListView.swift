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
                Button(action: {
                    self.coordinatorDelegate?.showAboutBeta()
                }, label: {
                    Text(L10n.aboutBeta)
                        .foregroundColor(Color(self.textColor))
                })
            }

            Section {
                NavigationLink(destination: ProfileView()) {
                    Text(L10n.Settings.account)
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

                NavigationLink(destination: SavingSettingsView()) {
                    Text(L10n.Settings.Saving.title)
                }

                NavigationLink(destination: StorageSettingsView()) {
                    Text(L10n.Settings.storage)
                }

                NavigationLink(destination: DebugSettingsView()) {
                    Text(L10n.Settings.debug)
                }
            }

            Section {
                Button(action: {
                    self.coordinatorDelegate?.showPrivacyPolicy()
                }, label: {
                    Text(L10n.privacyPolicy)
                        .foregroundColor(Color(self.textColor))
                })
            }
        }
    }

    private var textColor: UIColor {
        return UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        })
    }
}

struct SettingsListView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsListView()
    }
}
