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
                    Text("Profile")
                }
            }

            Section {
                NavigationLink(destination: GeneralSettingsView()) {
                    Text("General")
                }

                NavigationLink(destination: SyncSettingsView()) {
                    Text("Sync")
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
