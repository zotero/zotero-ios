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
