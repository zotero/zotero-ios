//
//  ProfileView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private(set) var store: SettingsStore
    @Environment(\.dbStorage) private var dbStorage: DbStorage

    var body: some View {
        Form {
            Section {
                Text(self.username)
            }

            Section {
                Button(action: self.store.logout) {
                    Text("Log out")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var username: String {
        return (try? self.dbStorage.createCoordinator().perform(request: ReadUserDbRequest()))?.name ?? "Missing username"
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
