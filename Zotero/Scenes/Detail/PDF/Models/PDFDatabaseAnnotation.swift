//
//  PDFDatabaseAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 26.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import RxSwift

struct PDFDatabaseAnnotation {
    let item: RItem
    let type: AnnotationType

    init?(item: RItem) {
        guard let type = AnnotationType(rawValue: item.annotationType) else {
            DDLogWarn("PDFDatabaseAnnotation: \(item.key) unknown annotation type \(item.annotationType)")
            return nil
        }
        guard AnnotationsConfig.supported.contains(type.kind) else {
            DDLogWarn("PDFDatabaseAnnotation: \(item.key) unsupported annotation type \(type)")
            return nil
        }
        self.item = item
        self.type = type
    }

    var key: String {
        return item.key
    }

    var _page: Int? {
        guard let rawValue = item.fieldValue(for: FieldKeys.Item.Annotation.Position.pageIndex) else {
            DDLogError("PDFDatabaseAnnotation: \(key) missing page!")
            return nil
        }
        guard let page = Int(rawValue) else {
            DDLogError("PDFDatabaseAnnotation: \(key) page incorrect format \(rawValue)")
            // Page is not an int, try double or fail
            return Double(rawValue).flatMap(Int.init)
        }
        return page
    }

    var _pageLabel: String? {
        guard let label = item.fieldValue(for: FieldKeys.Item.Annotation.pageLabel) else {
            DDLogError("PDFDatabaseAnnotation: \(key) missing page label!")
            return nil
        }
        return label
    }

    var lineWidth: CGFloat? {
        return (item.fields.filter(.key(FieldKeys.Item.Annotation.Position.lineWidth)).first?.value).flatMap(Double.init).flatMap(CGFloat.init)
    }

    func isAuthor(currentUserId: Int) -> Bool {
        if item.libraryId == .custom(.myLibrary) {
            return true
        }
        guard let user = item.createdBy else {
            DDLogWarn("PDFDatabaseAnnotation: isAuthor for currentUserId: \(currentUserId) encountered nil user")
            return false
        }
        return user.identifier == currentUserId
    }

    func author(displayName: String, username: String) -> String {
        if let authorName = item.fields.filter(.key(FieldKeys.Item.Annotation.authorName)).first?.value {
            return authorName
        }

        if let createdBy = item.createdBy {
            if !createdBy.name.isEmpty {
                return createdBy.name
            }

            if !createdBy.username.isEmpty {
                return createdBy.username
            }
        }

        if !displayName.isEmpty {
            return displayName
        }

        if !username.isEmpty {
            return username
        }

        return L10n.unknown
    }

    var _color: String? {
        guard let color = item.fieldValue(for: FieldKeys.Item.Annotation.color) else {
            DDLogError("PDFDatabaseAnnotation: \(key) missing color!")
            return nil
        }
        return color
    }

    var comment: String {
        return item.fieldValue(for: FieldKeys.Item.Annotation.comment) ?? ""
    }

    var text: String? {
        return item.fields.filter(.key(FieldKeys.Item.Annotation.text)).first?.value
    }

    var fontSize: CGFloat? {
        return (item.fields.filter(.key(FieldKeys.Item.Annotation.Position.fontSize)).first?.value).flatMap(Double.init).flatMap(CGFloat.init)
    }

    var rotation: UInt? {
        guard let rotation = (item.fields.filter(.key(FieldKeys.Item.Annotation.Position.rotation)).first?.value).flatMap(Double.init) else { return nil }
        return UInt(round(rotation))
    }

    var sortIndex: String {
        return item.annotationSortIndex
    }

    var dateModified: Date {
        return item.dateModified
    }

    var tags: [Tag] {
        return item.tags.map({ Tag(tag: $0) })
    }

    func editability(currentUserId: Int, library: Library) -> AnnotationEditability {
        switch library.identifier {
        case .custom:
            return library.metadataEditable ? .editable : .notEditable

        case .group:
            if !library.metadataEditable {
                return .notEditable
            }
            return isAuthor(currentUserId: currentUserId) ? .editable : .notEditable
        }
    }

    func rects(boundingBoxConverter: AnnotationBoundingBoxConverter) -> [CGRect] {
        guard let page = _page else { return [] }
        return item.rects
            .map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minX), height: ($0.maxY - $0.minY)) })
            .compactMap({ boundingBoxConverter.convertFromDb(rect: $0, page: PageIndex(page))?.rounded(to: 3) })
    }

    func paths(boundingBoxConverter: AnnotationBoundingBoxConverter) -> [[CGPoint]] {
        guard let page = _page else { return [] }
        let pageIndex = PageIndex(page)
        var paths: [[CGPoint]] = []
        for path in item.paths.sorted(byKeyPath: "sortIndex") {
            guard path.coordinates.count % 2 == 0 else { continue }
            let sortedCoordinates = path.coordinates.sorted(byKeyPath: "sortIndex")
            let lines = (0..<(path.coordinates.count / 2)).compactMap({ idx -> CGPoint? in
                let point = CGPoint(x: sortedCoordinates[idx * 2].value, y: sortedCoordinates[(idx * 2) + 1].value)
                return boundingBoxConverter.convertFromDb(point: point, page: pageIndex)?.rounded(to: 3)
            })
            paths.append(lines)
        }
        return paths
    }
}

extension PDFDatabaseAnnotation: PDFAnnotation {
    var readerKey: PDFReaderState.AnnotationKey {
        return .init(key: key, type: .database)
    }

    var page: Int {
        return _page ?? 0
    }

    var pageLabel: String {
        return _pageLabel ?? ""
    }
    
    var color: String {
        return _color ?? "#000000"
    }

    var isSyncable: Bool {
        return true
    }
}

extension RItem {
    fileprivate func fieldValue(for key: String) -> String? {
        let value = fields.filter(.key(key)).first?.value
        if value == nil {
            DDLogError("PDFDatabaseAnnotation: missing value for `\(key)`")
        }
        return value
    }
}
