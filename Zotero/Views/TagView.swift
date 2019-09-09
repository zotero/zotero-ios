//
//  TagView.swift
//  Zotero
//
//  Created by Michal Rentka on 28/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct TagView: View {
    let color: Color?
    let name: String

    var body: some View {
        HStack {
            self.color.flatMap {
                Circle().foregroundColor($0)
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
        TagView(color: .red, name: "Books")
            .previewLayout(.fixed(width: 320, height: 44))
    }
}

#endif
