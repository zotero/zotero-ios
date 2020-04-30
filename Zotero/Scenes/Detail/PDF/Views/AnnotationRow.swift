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
        VStack(alignment: .leading, spacing: 0) {
            AnnotationRowHeader(annotation: self.annotation)
            Divider()
            if self.annotation.type == .highlight ||
               self.annotation.type == .area {
                AnnotationRowBody(annotation: self.annotation)
                Divider()
            }
            if !self.annotation.comment.isEmpty || !self.annotation.tags.isEmpty {
                AnnotationRowFooter(annotation: self.annotation)
            }
        }
        .background(Color.white)
        .cornerRadius(8)
        .padding(1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder()
                .foregroundColor(Color(hex: "#bcc4d2"))
        )
        .padding(6)
    }
}

struct AnnotationRowHeader: View {
    let annotation: Annotation

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Rectangle()
                .foregroundColor(Color(hex: self.annotation.color))
                .cornerRadius(4)
                .frame(width: 15, height: 15)
            Text("Page \(self.annotation.pageLabel)")
                .fontWeight(.bold)
                .font(.system(size: 12))

            Spacer()

            Text(self.annotation.author)
                .foregroundColor(.gray)

            Spacer()
            Spacer()

            if self.annotation.isLocked {
                Image(systemName: "lock")
                    .foregroundColor(.gray)
            }
        }
        .padding(10)
    }
}

struct AnnotationRowBody: View {
    let annotation: Annotation

    var body: some View {
        Group {
            if self.annotation.type == .highlight {
                self.annotation.text.flatMap({ Text($0) })
            } else {
                // TODO: - Show image
                Image(systemName: "xmark.rectangle")
            }
        }
        .padding(10)
    }
}

struct AnnotationRowFooter: View {
    let annotation: Annotation

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(self.annotation.comment)
                    .padding(10)

                if !self.annotation.tags.isEmpty {
                    Divider()

                    HStack {
                        ForEach(self.annotation.tags) { tag in
                            HStack(spacing: 0) {
                                Text(tag.name)
                                    .foregroundColor(Color(hex: tag.color))
                                if tag.name != self.annotation.tags.last?.name {
                                    Text(",")
                                }
                            }
                        }
                    }
                    .padding(10)
                }
            }
            Spacer()
        }
        .background(Color(hex: "#edeff3"))
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
    }
}
