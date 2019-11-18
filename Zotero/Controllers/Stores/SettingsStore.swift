//
//  SettingsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

class SettingsStore: ObservableObject {
    struct State {
        var askForSyncPermission: Bool {
            didSet {
                Defaults.shared.askForSyncPermission = self.askForSyncPermission
            }
        }

        init() {
            self.askForSyncPermission = Defaults.shared.askForSyncPermission
        }
    }

    @Published var state: State

    private let apiClient: ApiClient
    private let secureStorage: SecureStorage
    private let dbStorage: DbStorage

    init(apiClient: ApiClient, secureStorage: SecureStorage, dbStorage: DbStorage) {
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.dbStorage = dbStorage
        self.state = State()
    }

    func logout() {
        do {
            Defaults.shared.reset()
            try self.dbStorage.createCoordinator().perform(request: DeleteAllDbRequest())
            self.secureStorage.apiToken = nil
            self.apiClient.set(authToken: nil)
            NotificationCenter.default.post(name: .sessionChanged, object: nil)
        } catch let error {
            // TODO: - Handle error
        }
    }
}
