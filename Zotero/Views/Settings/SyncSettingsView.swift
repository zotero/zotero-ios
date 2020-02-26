//
//  SyncSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private(set) var store: SettingsStore

    var body: some View {
        Form {
            Section {
                if self.store.state.isSyncing {
                    Button(action: self.store.cancelSync) {
                        Text("Cancel ongoing sync")
                    }
                } else {
                    Button(action: self.store.startSync) {
                        Text("Sync with zotero.org")
                    }
                }
            }
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
        let controllers = Controllers()
        return SyncSettingsView().environmentObject(SettingsStore(sessionController: controllers.sessionController,
                                                                  syncScheduler: controllers.userControllers!.syncScheduler))
    }
}
