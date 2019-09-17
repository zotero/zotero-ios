//
//  LoginView.swift
//  Zotero
//
//  Created by Michal Rentka on 17/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                TextField("Email", text: self.$email)
                    .padding()
                SecureField("Password", text: self.$password)
                    .padding()
                Button(action: {

                }) {
                    OnboardingButton(title: "Sign in",
                                     width: proxy.size.width)
                }
            }
        }
        .padding()
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
