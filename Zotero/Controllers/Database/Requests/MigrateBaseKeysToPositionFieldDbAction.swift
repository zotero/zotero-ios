//
//  MigrateBaseKeysToPositionFieldDbAction.swift
//  Zotero
//
//  Created by Michal Rentka on 14.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MigrateBaseKeysToPositionFieldDbAction: DbRequest {
    var needsWrite: Bool {  return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.item(type: ItemTypes.annotation))
                                                .filter("SUBQUERY(fields, $field, $field.baseKey == nil AND ($field.key == %@ OR $field.key == %@)).@count > 0", FieldKeys.Item.Annotation.Position.lineWidth,
                                                        FieldKeys.Item.Annotation.Position.pageIndex)
        for item in items {
            let fields = item.fields.filter("key = %@ OR key = %@", FieldKeys.Item.Annotation.Position.lineWidth, FieldKeys.Item.Annotation.Position.pageIndex)
            for field in fields {
                field.baseKey = FieldKeys.Item.Annotation.position
            }
        }
    }
}
