//
//  TagView.swift
//  Zotero
//
//  Created by Michal Rentka on 28/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct TagView: View {
    let name: String
    let color: Color
    let circleFilled: Bool

    init(name: String, hex: String, scheme: ColorScheme) {
        self.name = name
        let (color, style) = TagColorGenerator.color(for: hex, scheme: scheme)
        self.color = color
        self.circleFilled = style == .filled
    }

    var body: some View {
        HStack {
            if self.circleFilled {
                Circle().foregroundColor(self.color)
                        .aspectRatio(1.0, contentMode: .fit)
                        .frame(maxHeight: 16)
            } else {
                Circle().stroke(self.color, lineWidth: 1)
                        .foregroundColor(.clear)
                        .aspectRatio(1.0, contentMode: .fit)
                        .frame(maxHeight: 16)
            }
            Text(self.name)
        }
    }
}

#if DEBUG

struct TagView_Previews: PreviewProvider {
    static var previews: some View {
        TagView(name: "Books", hex: "#a28ae5", scheme: .dark)
            .previewLayout(.fixed(width: 320, height: 44))
    }
}

#endif
