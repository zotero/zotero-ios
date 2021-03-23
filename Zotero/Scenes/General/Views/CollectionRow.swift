//
//  CollectionRow.swift
//  Zotero
//
//  Created by Michal Rentka on 20/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CollectionRow: View {
    @Environment(\.colorScheme) var colorScheme

    static let levelOffset: CGFloat = 16.0
    let data: Collection

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 16) {
                Image(self.data.iconName)
                    .renderingMode(.template)
                    .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                Text(self.data.name)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 10)
    }

    static func inset(for level: Int, baseOffset: CGFloat) -> CGFloat {
        let offset = CollectionRow.levelOffset
        return baseOffset + offset + (CGFloat(level) * offset)
    }

    private var badgeBackgroundColor: Color {
        return Color.gray.opacity(self.colorScheme == .dark ? 0.5 : 0.2)
    }
}

#if DEBUG

struct CollectionRow_Previews: PreviewProvider {
    static var previews: some View {
        List {
            CollectionRow(data: Collection(custom: .all, itemCount: 48))
            CollectionRow(data: Collection(custom: .publications, itemCount: 2))
            CollectionRow(data: Collection(custom: .trash, itemCount: 4))
        }
    }
}

#endif
