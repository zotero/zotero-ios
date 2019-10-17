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
        GeometryReader { proxy in
            HStack {
                Image(self.data.iconName)
                    .renderingMode(.template)
                    .foregroundColor(.blue)
                Text(self.data.name)
                    .foregroundColor(.black)
                    .lineLimit(1)
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.leading, self.inset(for: self.data.level))
        }
    }

    private func inset(for level: Int) -> CGFloat {
        // When this view is embedded in UIHostingController and used in UITableViewCell, the padding is actually just 10, so we multiply it by 2
        // to get the same offset as separator
        let offset = CollectionRow.levelOffset * 2
        return offset + (CGFloat(level) * offset)
    }
}

#if DEBUG

struct CollectionRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CollectionRow(data: Collection(custom: .all))
            CollectionRow(data: Collection(custom: .publications))
            CollectionRow(data: Collection(custom: .trash))
        }
    }
}

#endif
