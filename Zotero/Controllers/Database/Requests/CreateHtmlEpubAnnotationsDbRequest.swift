//
//  CreateHtmlEpubAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 28.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class CreateHtmlEpubAnnotationsDbRequest: CreateReaderAnnotationsDbRequest<HtmlEpubAnnotation> {
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

        // Create position fields
        for (key, value) in annotation.position {
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

    override func addTags(for annotation: HtmlEpubAnnotation, to item: RItem, database: Realm) {
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
