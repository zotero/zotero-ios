//
//  RStyle.swift
//  Zotero
//
//  Created by Michal Rentka on 18.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RStyle: Object {
    @Persisted(primaryKey: true) var identifier: String
    @Persisted var title: String
    @Persisted var href: String
    @Persisted var updated: Date
    @Persisted var filename: String
    @Persisted var dependency: RStyle?
    @Persisted var installed: Bool
    @Persisted var supportsBibliography: Bool
    @Persisted var isNoteStyle: Bool
    @Persisted var defaultLocale: String
    @Persisted(originProperty: "dependency") var dependent: LinkingObjects<RStyle>
}

extension RStyle: Identifiable {
    var id: String { return self.identifier }
}
