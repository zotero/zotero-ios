//
//  LoginState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct LoginState: ViewModelState {
    enum TextField {
        case username, password
    }

    var username: String
    var password: String
    var isLoading: Bool
    var selectedTextField: TextField?
    var error: LoginError?

    init() {
        self.username = ""
        self.password = ""
        self.isLoading = false
        // TODO: - solve crash on ipad (crashes on becomeFirstResponder in SelectableTextField)
        self.selectedTextField = UIDevice.current.userInterfaceIdiom == .pad ? nil : .username
        self.error = nil
    }

    func cleanup() {}
}
