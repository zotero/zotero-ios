//
//  CreatePDFAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 31.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

class CreatePDFAnnotationsDbRequest: CreateReaderAnnotationsDbRequest<PDFDocumentAnnotation> {
    unowned let boundingBoxConverter: AnnotationBoundingBoxConverter

    init(
        attachmentKey: String,
        libraryId: LibraryIdentifier,
        annotations: [PDFDocumentAnnotation],
        userId: Int,
        schemaController: SchemaController,
        boundingBoxConverter: AnnotationBoundingBoxConverter
    ) {
        self.boundingBoxConverter = boundingBoxConverter
        super.init(attachmentKey: attachmentKey, libraryId: libraryId, annotations: annotations, userId: userId, schemaController: schemaController)
    }

    override func addFields(for annotation: PDFDocumentAnnotation, to item: RItem, database: Realm) {
        super.addFields(for: annotation, to: item, database: database)

        for field in FieldKeys.Item.Annotation.extraPDFFields(for: annotation.type) {
            let rField = RItemField()
            rField.key = field.key
            rField.baseKey = field.baseKey
            rField.changed = true

            switch field.key {
            case FieldKeys.Item.Annotation.Position.pageIndex where field.baseKey == FieldKeys.Item.Annotation.position:
                rField.value = "\(annotation.page)"

            case FieldKeys.Item.Annotation.Position.lineWidth where field.baseKey == FieldKeys.Item.Annotation.position:
                rField.value = annotation.lineWidth.flatMap({ "\(Decimal($0).rounded(to: 3))" }) ?? ""

            case FieldKeys.Item.Annotation.pageLabel:
                rField.value = annotation.pageLabel

            case FieldKeys.Item.Annotation.Position.rotation where field.baseKey == FieldKeys.Item.Annotation.position:
                rField.value = "\(annotation.rotation ?? 0)"

            case FieldKeys.Item.Annotation.Position.fontSize where field.baseKey == FieldKeys.Item.Annotation.position:
                rField.value = "\(annotation.fontSize ?? 0)"

            default:
                DDLogWarn("CreatePDFAnnotationsDbRequest: unknown field, assigning empty value - \(field.key)")
                rField.value = ""
            }

            item.fields.append(rField)
        }
    }

    override func addAdditionalProperties(for annotation: PDFDocumentAnnotation, fromRestore: Bool, to item: RItem, changes: inout RItemChanges, database: Realm) {
        add(rects: annotation.rects, fromRestore: fromRestore, to: item, changes: &changes, database: database)
        add(paths: annotation.paths, fromRestore: fromRestore, to: item, changes: &changes, database: database)
    }

    private func add(rects: [CGRect], fromRestore: Bool, to item: RItem, changes: inout RItemChanges, database: Realm) {
        if fromRestore {
            item.rects.removeAll()
            changes.insert(.rects)
        }
        guard !rects.isEmpty, let annotation = PDFDatabaseAnnotation(item: item) else { return }

        let page = UInt(annotation.page)

        for rect in rects {
            let dbRect = boundingBoxConverter.convertToDb(rect: rect, page: page) ?? rect
            
            let rRect = RRect()
            rRect.minX = Double(dbRect.minX)
            rRect.minY = Double(dbRect.minY)
            rRect.maxX = Double(dbRect.maxX)
            rRect.maxY = Double(dbRect.maxY)
            item.rects.append(rRect)
        }
        changes.insert(.rects)
    }

    private func add(paths: [[CGPoint]], fromRestore: Bool, to item: RItem, changes: inout RItemChanges, database: Realm) {
        if fromRestore {
            item.paths.removeAll()
            changes.insert(.paths)
        }
        guard !paths.isEmpty, let annotation = PDFDatabaseAnnotation(item: item) else { return }

        let page = UInt(annotation.page)

        for (idx, path) in paths.enumerated() {
            let rPath = RPath()
            rPath.sortIndex = idx

            for (idy, point) in path.enumerated() {
                let dbPoint = boundingBoxConverter.convertToDb(point: point, page: page) ?? point

                let rXCoordinate = RPathCoordinate()
                rXCoordinate.value = Double(dbPoint.x)
                rXCoordinate.sortIndex = idy * 2
                rPath.coordinates.append(rXCoordinate)

                let rYCoordinate = RPathCoordinate()
                rYCoordinate.value = Double(dbPoint.y)
                rYCoordinate.sortIndex = (idy * 2) + 1
                rPath.coordinates.append(rYCoordinate)
            }

            item.paths.append(rPath)
        }

        changes.insert(.paths)
    }
}
