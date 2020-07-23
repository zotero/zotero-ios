//
//  RegisterView.swift
//  Zotero
//
//  Created by Michal Rentka on 17/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct RegisterView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var repeatPassword: String = ""

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 20) {
                VStack {
                    TextField(L10n.Login.email, text: self.$email)
                        .padding([.horizontal, .top])
                    Divider()
                }

                VStack {
                    SecureField(L10n.Login.password, text: self.$password)
                        .padding([.horizontal, .top])
                    Divider()
                }

                VStack {
                    SecureField(L10n.Login.repeatPassword, text: self.$repeatPassword)
                        .padding([.horizontal, .top])
                    Divider()
                }

                Button(action: {

                }) {
                    Text(L10n.Onboarding.createAccount)
                }
            }
        }
        .padding()
    }
}

struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        RegisterView()
    }
}
