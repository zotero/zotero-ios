//
//  TagCirclesView.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct TagCirclesView: View {
    @Environment(\.colorScheme) var colorScheme

    let colors: [String]
    let height: CGFloat

    var body: some View {
        ZStack {
            ForEach(self.colors.indices) { index in
                Circle()
                    .foregroundColor(TagColorGenerator.color(for: self.colors[index], scheme: self.colorScheme))
                    .overlay(
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1))
                            .foregroundColor(.white)
                    )
                    .frame(width: self.height, height: self.height)
                    .position(self.position(at: index))
            }
        }
        .frame(width: self.containerWidth(count: self.colors.count), height: self.height)
    }

    private func containerWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let circleWidth = self.height
        return circleWidth + (CGFloat(count - 1) * (circleWidth / 2.0))
    }

    private func position(at index: Int) -> CGPoint {
        let width = self.height
        return CGPoint(x: (CGFloat(index + 1) * (width / 2.0)),
                       y: self.height / 2.0)
    }
}

struct TagCirclesView_Previews: PreviewProvider {
    static var previews: some View {
        TagCirclesView(colors: ["#123321", "#ff112d", "#ee1289"], height: 44)
    }
}
