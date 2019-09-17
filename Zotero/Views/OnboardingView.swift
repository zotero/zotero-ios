//
//  OnboardingView.swift
//  Zotero
//
//  Created by Michal Rentka on 17/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct OnboardingView: View {
    private let spacing: CGFloat = 20

    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                HStack(spacing: self.spacing) {
                    NavigationLink(destination: LoginView()) {
                        OnboardingButton(title: "Sign in",
                                         width: (proxy.size.width - self.spacing) / 2.0)
                    }

                    NavigationLink(destination: RegisterView()) {
                        OnboardingButton(title: "Create account",
                                         width: (proxy.size.width - self.spacing) / 2.0)
                    }
                }
            }
            .padding()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct OnboardingButton: View {
    let title: String
    let width: CGFloat?

    var body: some View {
        Text(self.title)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding()
            .frame(width: self.width)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .foregroundColor(.red)
            )
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
