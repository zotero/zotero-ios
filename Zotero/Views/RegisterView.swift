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
            VStack(spacing: 8) {
                TextField("Email", text: self.$email)
                    .padding()
                SecureField("Password", text: self.$password)
                    .padding()
                SecureField("Repeat password", text: self.$repeatPassword)
                    .padding()
                Button(action: {

                }) {
                    OnboardingButton(title: "Create account",
                                     width: proxy.size.width)
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
