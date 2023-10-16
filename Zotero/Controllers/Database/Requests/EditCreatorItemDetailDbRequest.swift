//
//  EditCreatorItemDetailDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EditCreatorItemDetailDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let creator: ItemDetailState.Creator
    let orderId: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(key, in: libraryId)).first else { return }

        let rCreator: RCreator

        if let _creator = item.creators.filter("uuid == %@", creator.id).first {
            rCreator = _creator
        } else {
            rCreator = RCreator()
            rCreator.uuid = creator.id
            item.creators.append(rCreator)
        }

        rCreator.rawType = creator.type
        rCreator.orderId = orderId
        rCreator.primary = creator.primary

        switch creator.namePresentation {
        case .full:
            rCreator.name = creator.fullName
            rCreator.firstName = ""
            rCreator.lastName = ""
        case .separate:
            rCreator.name = ""
            rCreator.firstName = creator.firstName
            rCreator.lastName = creator.lastName
        }

        item.updateCreatorSummary()
        item.changes.append(RObjectChange.create(changes: RItemChanges.creators))
    }
}
