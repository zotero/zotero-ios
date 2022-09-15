//
//  RObjectChange.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RObjectChange: EmbeddedObject {
    /// Unique identifier for these changes
    @Persisted var uuid: String
    /// Raw value for OptionSet of changes for parent object, indicates which local changes need to be synced to backend
    @Persisted var rawChanges: Int16

    static func create<Changes: OptionSet>(changes: Changes) -> RObjectChange where Changes.RawValue == Int16 {
        let objectChange = RObjectChange()
        objectChange.uuid = UUID().uuidString
        objectChange.rawChanges = changes.rawValue
        return objectChange
    }
}
