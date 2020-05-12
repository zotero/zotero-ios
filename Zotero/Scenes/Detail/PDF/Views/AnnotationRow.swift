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
    let preview: UIImage?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnnotationRowHeader(annotation: self.annotation)
            if self.annotation.type == .highlight ||
               self.annotation.type == .area {
                AnnotationDivider(selected: self.selected)
                AnnotationRowBody(annotation: self.annotation, preview: self.preview)
            }
            if self.footerVisible {
                AnnotationDivider(selected: self.selected)
                AnnotationRowFooter(annotation: self.annotation, selected: self.selected)
            }
        }
        .background(self.backgroundColor)
        .cornerRadius(8)
        .padding(1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder()
                .foregroundColor(self.borderColor)
        )
        .shadow(color: self.shadowColor, radius: 2)
        .padding(6)
    }

    private var footerVisible: Bool {
        return self.selected || !self.annotation.comment.isEmpty || !self.annotation.tags.isEmpty
    }

    private var shadowColor: Color {
        return self.selected ? Color(hex: "#6d95e0").opacity(0.5) : .clear
    }

    private var borderColor: Color {
        return Color(hex: self.selected ? "#6d95e0" : "#bcc4d2")
    }

    private var backgroundColor: Color {
        return self.selected ? Color(hex: "#e4ebf9") : Color.white
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
            Text("\(L10n.Pdf.AnnotationsSidebar.page) \(self.annotation.pageLabel)")
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
    let preview: UIImage?

    var body: some View {
        Group {
            if self.annotation.type == .highlight {
                self.annotation.text.flatMap({ Text($0) })
                    .padding(10)
            } else {
                // TODO: - Add placeholder image
                (self.preview.flatMap({ Image(uiImage: $0).resizable() }) ?? Image(systemName: "xmark.rectangle"))
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 200, alignment: .center)
                    .clipped()
            }
        }
    }
}

struct AnnotationRowFooter: View {
    let annotation: Annotation
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(self.comment)
                .padding(10)
                .foregroundColor(self.commentColor)

            if self.selected || !self.annotation.tags.isEmpty {
                AnnotationDivider(selected: self.selected)

                Group {
                    if self.annotation.tags.isEmpty {
                        Text("Add tags")
                            .foregroundColor(Color(hex: "#6d95e0"))
                    } else {
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
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.backgroundColor)
    }

    private var backgroundColor: Color {
        return self.selected ? Color(hex: "#dde6f8") : Color(hex: "#edeff3")
    }

    private var comment: String {
        return self.annotation.comment.isEmpty ? "Add comment" : self.annotation.comment
    }

    private var commentColor: Color {
        return self.annotation.comment.isEmpty ? Color(hex: "#6d95e0") : .black
    }
}

struct AnnotationDivider: View {
    let selected: Bool

    var body: some View {
        Divider().background(self.color)
    }

    private var color: Color {
        return self.selected ? Color(hex: "#6d95e0").opacity(0.4) : Color(hex: "#d7dad7")
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
                                                        Tag(name: "Random", color: "#000000")]),
                          preview: nil,
                          selected: false)
                    .frame(width: 380)


            AnnotationRow(annotation: Annotation(key: "",
                                                 type: .note,
                                                 page: 4,
                                                 pageLabel: "IV",
                                                 rects: [],
                                                 author: "Michal",
                                                 isAuthor: true,
                                                 color: "#E1AD01",
                                                 comment: "",
                                                 text: nil,
                                                 isLocked: false,
                                                 sortIndex: "",
                                                 dateModified: Date(),
                                                 tags: []),
                          preview: nil,
                          selected: false)
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
                                                 tags: []),
                          preview: nil,
                          selected: false)
                    .frame(width: 220)
        }
    }
}
