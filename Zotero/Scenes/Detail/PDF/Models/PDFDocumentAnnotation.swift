//
//  PDFDocumentAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 26.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct PDFDocumentAnnotation {
    let key: String
    let type: AnnotationType
    let page: Int
    let pageLabel: String
    let rects: [CGRect]
    let paths: [[CGPoint]]
    let lineWidth: CGFloat?
    let author: String
    let isAuthor: Bool
    let color: String
    let comment: String
    let text: String?
    var fontSize: CGFloat?
    var rotation: UInt?
    let sortIndex: String
    let dateAdded: Date
    let dateModified: Date
}

extension PDFDocumentAnnotation: PDFAnnotation {
    var readerKey: PDFReaderState.AnnotationKey {
        return .init(key: self.key, type: .document)
    }

    func isAuthor(currentUserId: Int) -> Bool {
        return self.isAuthor
    }

    func author(displayName: String, username: String) -> String {
        return self.author
    }

    func editability(currentUserId: Int, library: Library) -> AnnotationEditability {
        return .notEditable
    }

    func rects(boundingBoxConverter: AnnotationBoundingBoxConverter) -> [CGRect] {
        return self.rects
    }

    func paths(boundingBoxConverter: AnnotationBoundingBoxConverter) -> [[CGPoint]] {
        return self.paths
    }

    var isSyncable: Bool {
        return false
    }

    var tags: [Tag] {
        return []
    }
}

extension PDFDocumentAnnotation {
    init?(annotation: RDocumentAnnotation, isAuthor: Bool) {
        // Some types may be cached because they are drawn, but not supported for further manipulation.
        guard let annotationType = AnnotationType(rawValue: annotation.type) else { return nil }
        let rects: [CGRect] = annotation.rects
            .map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minX), height: ($0.maxY - $0.minY)) })
        let paths: [[CGPoint]] = annotation.paths.sorted(byKeyPath: "sortIndex")
            .filter({ $0.coordinates.count % 2 == 0 })
            .map({ path -> [CGPoint] in
                let sortedCoordinates = path.coordinates.sorted(byKeyPath: "sortIndex")
                return (0..<(path.coordinates.count / 2)).map({ index -> CGPoint in
                    return CGPoint(x: sortedCoordinates[index * 2].value, y: sortedCoordinates[(index * 2) + 1].value).rounded(to: 3)
                })
            })
        self.init(
            key: annotation.key,
            type: annotationType,
            page: annotation.page,
            pageLabel: annotation.pageLabel,
            rects: rects,
            paths: paths,
            lineWidth: annotation.lineWidth.flatMap({ CGFloat($0) }),
            author: annotation.author,
            isAuthor: isAuthor,
            color: annotation.color,
            comment: annotation.comment,
            text: annotation.text,
            fontSize: annotation.fontSize.flatMap({ CGFloat($0) }),
            rotation: annotation.rotation.flatMap({ UInt($0) }),
            sortIndex: annotation.sortIndex,
            dateAdded: annotation.dateAdded,
            dateModified: annotation.dateModified
        )
    }

    init?(annotation: RDocumentAnnotation, displayName: String, username: String) {
        let isAuthor = annotation.author == displayName || annotation.author == username
        self.init(annotation: annotation, isAuthor: isAuthor)
    }
}
