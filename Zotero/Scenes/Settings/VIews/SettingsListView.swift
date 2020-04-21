//
//  SettingsListView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SettingsListView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink(destination: ProfileView()) {
                    Text(L10n.Settings.profile)
                }
            }

            Section {
                NavigationLink(destination: GeneralSettingsView()) {
                    Text(L10n.Settings.general)
                }

                NavigationLink(destination: SyncSettingsView()) {
                    Text(L10n.Settings.sync)
                }

                NavigationLink(destination: TranslatorsSettingsView()) {
                    Text(L10n.Settings.translators)
                }

                NavigationLink(destination: DebugSettingsView()) {
                    Text(L10n.Settings.debug)
                }
            }
        }
    }
}

struct SettingsListView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsListView()
    }
}
