//
//  OnboardingButton.swift
//  Zotero
//
//  Created by Michal Rentka on 18/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct OnboardingButton: View {
    let title: String
    let width: CGFloat?
    let isLoading: Bool

    var body: some View {
        Group {
            if self.isLoading {
                ActivityIndicatorView(style: .medium, isAnimating: .constant(true)).foregroundColor(.white)
            } else {
                Text(self.title)
                .fontWeight(.semibold)
            }
        }
        .foregroundColor(.white)
        .padding()
        .frame(width: self.width)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(.red)
        )
    }
}

struct OnboardingButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            OnboardingButton(title: "Test button", width: 300, isLoading: false)
            OnboardingButton(title: "Test button", width: 300, isLoading: true)
        }
    }
}
