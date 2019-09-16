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
        // TODO: - fix
        Text("")
//            HStack(spacing: 5) {
//                ForEach(self.colors, id: \.self) { color in
//                    Circle()
//                        .stroke(style: StrokeStyle(lineWidth: 1))
//                        .frame(maxHeight: 20)
//                        .aspectRatio(1, contentMode: .fit)
//                        .background(Color.green)
//                }
//            }
    }
}

struct TagCirclesView_Previews: PreviewProvider {
    static var previews: some View {
        TagCirclesView(colors: ["#123321", "#ff112d", "#ee1289"])
            .previewLayout(.fixed(width: 320, height: 44))
    }
}
