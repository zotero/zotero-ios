//
//  AnnotationRow.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

struct AnnotationRow: View {
    let annotation: Annotation

    var body: some View {
        VStack {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Rectangle()
                    .foregroundColor(Color(hex: self.annotation.color))
                    .cornerRadius(4)
                    .frame(width: 20, height: 20)
                Text("Page \(self.annotation.pageLabel)")
                    .fontWeight(.bold)

                Spacer()

                Text(self.annotation.author)
                    .alignmentGuide(., computeValue: <#T##(ViewDimensions) -> CGFloat#>)

                Spacer()

                if self.annotation.isLocked {
                    Image(systemName: "lock")
                        .foregroundColor(.gray)
                }
            }

            // Body


            // Footer
        }
        .padding()
    }
}

struct AnnotationRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AnnotationRow(annotation: Annotation(key: "",
                                                 type: .highlight,
                                                 page: 2,
                                                 pageLabel: "2",
                                                 rects: [],
                                                 author: "Michal",
                                                 isAuthor: true,
                                                 color: "#E1AD01",
                                                 comment: "My comment",
                                                 text: "Some highlighted text",
                                                 isLocked: true,
                                                 sortIndex: "",
                                                 dateModified: Date(),
                                                 tags: [Tag(name: "Preview", color: "#123321"),
                                                        Tag(name: "Random", color: "#000000")]))
                    .frame(width: 380)


            AnnotationRow(annotation: Annotation(key: "",
                                                 type: .note,
                                                 page: 4,
                                                 pageLabel: "IV",
                                                 rects: [],
                                                 author: "Michal",
                                                 isAuthor: true,
                                                 color: "#E1AD01",
                                                 comment: "My comment",
                                                 text: nil,
                                                 isLocked: false,
                                                 sortIndex: "",
                                                 dateModified: Date(),
                                                 tags: []))
                    .frame(width: 380)


            AnnotationRow(annotation: Annotation(key: "",
                                                 type: .area,
                                                 page: 14,
                                                 pageLabel: "14",
                                                 rects: [],
                                                 author: "Michal",
                                                 isAuthor: true,
                                                 color: "#E1AD01",
                                                 comment: "My comment",
                                                 text: nil,
                                                 isLocked: true,
                                                 sortIndex: "",
                                                 dateModified: Date(),
                                                 tags: []))
                    .frame(width: 380)
        }
        .background(Color.black.opacity(0.2))
    }
}
