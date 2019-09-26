//
//  CollectionRow.swift
//  Zotero
//
//  Created by Michal Rentka on 20/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionRow: View {
    static let levelOffset: CGFloat = 20.0
    let data: Collection

    var body: some View {
        HStack {
            Image(self.data.iconName)
                .renderingMode(.template)
                .foregroundColor(.blue)
            Text(self.data.name)
                .foregroundColor(.black)
                .lineLimit(1)
        }
    }
}

#if DEBUG

struct CollectionRow_Previews: PreviewProvider {
    static var previews: some View {
        List {
            CollectionRow(data: Collection(custom: .all))
            CollectionRow(data: Collection(custom: .publications))
            CollectionRow(data: Collection(custom: .trash))
        }
    }
}

#endif
