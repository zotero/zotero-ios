//
//  AppStore.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum AppAction {
    case change(AppState)
}

enum AppState {
    case onboarding, main
}

class AppStore: OldStore {
    typealias Action = AppAction
    typealias State = AppState

    let updater: StoreStateUpdater<AppState>
    let apiClient: ApiClient

    init(apiClient: ApiClient, secureStorage: SecureStorage) {
        self.apiClient = apiClient
        let authToken = ApiConstants.authToken ?? secureStorage.apiToken
        let state: AppState = authToken == nil ? .onboarding : .main
        self.updater = StoreStateUpdater(initialState: state)
    }

    func handle(action: AppAction) {
        switch action {
        case .change(let new):
            self.updater.updateState { newState in
                newState = new
            }
        }
    }
}
