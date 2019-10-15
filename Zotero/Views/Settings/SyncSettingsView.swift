//
//  SyncSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(title: "User Permission",
                                  subtitle: "Ask for user permission for each write action",
                                  value: self.$store.state.askForSyncPermission)
            }
        }
    }
}

struct SyncSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SyncSettingsView()
            .environmentObject(SettingsStore())
    }
}
