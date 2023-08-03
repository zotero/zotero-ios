//
//  DatabaseAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 26.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import RxSwift

struct DatabaseAnnotation {
    let item: RItem

    var key: String {
        return self.item.key
    }

    var _type: AnnotationType? {
        guard let rawValue = self.item.fieldValue(for: FieldKeys.Item.Annotation.type) else {
            DDLogError("DatabaseAnnotation: \(self.key) missing annotation type!")
            return nil
        }
        guard let type = AnnotationType(rawValue: rawValue) else {
            DDLogWarn("DatabaseAnnotation: \(self.key) unknown annotation type \(rawValue)")
            return nil
        }
        return type
    }

    var _page: Int? {
        guard let rawValue = self.item.fieldValue(for: FieldKeys.Item.Annotation.Position.pageIndex) else {
            DDLogError("DatabaseAnnotation: \(self.key) missing page!")
            return nil
        }
        guard let page = Int(rawValue) else {
            DDLogError("DatabaseAnnotation: \(self.key) page incorrect format \(rawValue)")
            // Page is not an int, try double or fail
            return Double(rawValue).flatMap(Int.init)
        }
        return page
    }

    var _pageLabel: String? {
        guard let label = self.item.fieldValue(for: FieldKeys.Item.Annotation.pageLabel) else {
            DDLogError("DatabaseAnnotation: \(self.key) missing page label!")
            return nil
        }
        return label
    }

    var lineWidth: CGFloat? {
        return (self.item.fields.filter(.key(FieldKeys.Item.Annotation.Position.lineWidth)).first?.value).flatMap(Double.init).flatMap(CGFloat.init)
    }

    func isAuthor(currentUserId: Int) -> Bool {
        return self.item.libraryId == .custom(.myLibrary) ? true : self.item.createdBy?.identifier == currentUserId
    }

    func author(displayName: String, username: String) -> String {
        if let authorName = item.fields.filter(.key(FieldKeys.Item.Annotation.authorName)).first?.value {
            return authorName
        }

        if let createdBy = self.item.createdBy {
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
        guard let color = self.item.fieldValue(for: FieldKeys.Item.Annotation.color) else {
            DDLogError("DatabaseAnnotation: \(self.key) missing color!")
            return nil
        }
        return color
    }

    var comment: String {
        return self.item.fieldValue(for: FieldKeys.Item.Annotation.comment) ?? ""
    }

    var text: String? {
        return self.item.fields.filter(.key(FieldKeys.Item.Annotation.text)).first?.value
    }

    var fontSize: UInt? {
        return (self.item.fields.filter(.key(FieldKeys.Item.Annotation.Position.fontSize)).first?.value).flatMap(UInt.init)
    }

    var rotation: UInt? {
        guard let rotation = (self.item.fields.filter(.key(FieldKeys.Item.Annotation.Position.rotation)).first?.value).flatMap(Double.init) else { return nil }
        return UInt(round(rotation))
    }

    var sortIndex: String {
        return self.item.annotationSortIndex
    }

    var dateModified: Date {
        return self.item.dateModified
    }

    var tags: [Tag] {
        return self.item.tags.map({ Tag(tag: $0) })
    }

    func editability(currentUserId: Int, library: Library) -> AnnotationEditability {
        switch library.identifier {
        case .custom:
            return library.metadataEditable ? .editable : .notEditable

        case .group:
            if !library.metadataEditable {
                return .notEditable
            }
            return self.isAuthor(currentUserId: currentUserId) ? .editable : .deletable
        }
    }

    func rects(boundingBoxConverter: AnnotationBoundingBoxConverter) -> [CGRect] {
        guard let page = self._page else { return [] }
        return self.item.rects.map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minX), height: ($0.maxY - $0.minY)) })
                              .compactMap({ boundingBoxConverter.convertFromDb(rect: $0, page: PageIndex(page))?.rounded(to: 3) })
    }

    func paths(boundingBoxConverter: AnnotationBoundingBoxConverter) -> [[CGPoint]] {
        guard let page = self._page else { return [] }
        let pageIndex = PageIndex(page)
        var paths: [[CGPoint]] = []
        for path in self.item.paths.sorted(byKeyPath: "sortIndex") {
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

    init(item: RItem) {
        self.item = item
    }
}

extension DatabaseAnnotation: Annotation {
    var readerKey: PDFReaderState.AnnotationKey {
        return .init(key: self.key, type: .database)
    }

    var type: AnnotationType {
        return self._type ?? .note
    }

    var page: Int {
        return self._page ?? 0
    }

    var pageLabel: String {
        return self._pageLabel ?? ""
    }
    
    var color: String {
        return self._color ?? "#000000"
    }

    var isSyncable: Bool {
        return true
    }
}

extension RItem {
    fileprivate func fieldValue(for key: String) -> String? {
        let value = self.fields.filter(.key(key)).first?.value
        if value == nil {
            DDLogError("DatabaseAnnotation: missing value for `\(key)`")
        }
        return value
    }
}
