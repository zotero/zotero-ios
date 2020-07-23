//
//  ActivityIndicatorView.swift
//  Zotero
//
//  Created by Michal Rentka on 18/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ActivityIndicatorView: UIViewRepresentable {
    let style: UIActivityIndicatorView.Style
    let color: UIColor?
    @Binding var isAnimating: Bool

    init(style: UIActivityIndicatorView.Style, color: UIColor? = nil, isAnimating: Binding<Bool>) {
        self.style = style
        self.color = color
        self._isAnimating = isAnimating
    }

    func makeUIView(context: UIViewRepresentableContext<ActivityIndicatorView>) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: self.style)
        if let color = self.color {
            view.color = color
        }
        return view
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: UIViewRepresentableContext<ActivityIndicatorView>) {
        self.isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
}

struct ActivityIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityIndicatorView(style: .medium, color: .white, isAnimating: .constant(true))
    }
}
