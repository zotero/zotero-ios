//
//  CreateOrEditHtmlEpubAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 28.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class CreateOrEditHtmlEpubAnnotationsDbRequest: CreateOrEditReaderAnnotationsDbRequest<HtmlEpubAnnotation> {
    override func addFields(for annotation: HtmlEpubAnnotation, to item: RItem, database: Realm) {
        super.addFields(for: annotation, to: item, database: database)

        for field in FieldKeys.Item.Annotation.extraHtmlEpubFields(for: annotation.type) {
            let value: String

            switch field.key {
            case FieldKeys.Item.Annotation.pageLabel:
                value = annotation.pageLabel

            default:
                continue
            }

            let rField = RItemField()
            rField.key = field.key
            rField.baseKey = field.baseKey
            rField.changed = true
            rField.value = value
            item.fields.append(rField)
        }

        // Create position fields. `rects` and `nextPageRects` are not fields - a PDF source position (standalone reading mode)
        // keeps them in separate lists, which `addAdditionalProperties(for:to:changes:database:)` fills.
        let rectKeys: Set<String> = [FieldKeys.Item.Annotation.Position.rects, FieldKeys.Item.Annotation.Position.nextPageRects]
        for (key, value) in annotation.position where !rectKeys.contains(key) {
            let rField = RItemField()
            rField.key = key
            rField.value = positionValueToString(value)
            rField.baseKey = FieldKeys.Item.Annotation.position
            rField.changed = true
            item.fields.append(rField)
        }

        func positionValueToString(_ value: Any) -> String {
            if let string = value as? String {
                return string
            }
            if let dictionary = value as? [AnyHashable: Any] {
                return (try? JSONSerialization.data(withJSONObject: dictionary)).flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
            }
            return "\(value)"
        }
    }

    /// Stores the `rects` and `nextPageRects` of a PDF source position (standalone reading mode) in the item's rect lists, where
    /// the rest of the app and the sync expect them. A highlight or underline which continues on the next page has its rects on the
    /// next page in `nextPageRects`. Annotations of HTML/EPUB documents are anchored by selectors and have no rects, so this is a no-op
    /// for them.
    override func addAdditionalProperties(for annotation: HtmlEpubAnnotation, to item: RItem, changes: inout RItemChanges, database: Realm) {
        store(rects: annotation.position[FieldKeys.Item.Annotation.Position.rects], in: item.rects)
        store(rects: annotation.position[FieldKeys.Item.Annotation.Position.nextPageRects], in: item.nextPageRects)

        func store(rects value: Any?, in itemRects: List<RRect>) {
            if !itemRects.isEmpty {
                database.delete(itemRects)
                changes.insert(.rects)
            }

            guard let rects = value as? [[Double]], !rects.isEmpty else { return }

            for rect in rects {
                guard rect.count == 4 else { continue }
                let rRect = RRect()
                rRect.minX = rect[0]
                rRect.minY = rect[1]
                rRect.maxX = rect[2]
                rRect.maxY = rect[3]
                itemRects.append(rRect)
            }
            changes.insert(.rects)
        }
    }

    override func addTags(for annotation: HtmlEpubAnnotation, to item: RItem, database: Realm) {
        super.addTags(for: annotation, to: item, database: database)

        let allTags = database.objects(RTag.self)
        for tag in annotation.tags {
            guard let rTag = allTags.filter(.name(tag.name)).first else { continue }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
        }
    }
}
