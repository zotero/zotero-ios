//
//  TagCirclesView.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct TagCirclesView: View {
    let colors: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(self.colors, id: \.self) { color in
                Circle()
                    .aspectRatio(1, contentMode: .fit)
                    .foregroundColor(Color(hex: color))
                    .overlay(
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1))
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

struct TagCirclesView_Previews: PreviewProvider {
    static var previews: some View {
        TagCirclesView(colors: ["#123321", "#ff112d", "#ee1289"])
    }
}
