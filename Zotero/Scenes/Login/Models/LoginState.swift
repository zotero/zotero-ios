//
//  LoginState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LoginState: ViewModelState {
    var username: String
    var password: String
    var isLoading: Bool
    var error: LoginError?

    func cleanup() {}
}
