//
//  RItemLocaleController.swift
//  Zotero
//
//  Created by Michal Rentka on 07/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

class RItemLocaleController {
    @UserDefault(key: "LastLocalization", defaultValue: nil)
    private var previousLocale: String?

    private let schemaController: SchemaController
    private let dbStorage: DbStorage

    init(schemaController: SchemaController, dbStorage: DbStorage) {
        self.schemaController = schemaController
        self.dbStorage = dbStorage
    }

    func loadLocale() {
        let localeId = Locale.autoupdatingCurrent.identifier

        guard self.previousLocale != localeId else { return }
        self.updateItems(with: localeId)
        self.previousLocale = localeId
    }

    private func updateItems(with localeId: String) {
        guard let locale = self.schemaController.locale(for: localeId) else {
            DDLogError("RItemLocaleController: missing locale for \(localeId)")
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let `self` = self else { return }

            do {
                try self.dbStorage.createCoordinator().perform(request: UpdateItemLocaleDbRequest(locale: locale))
            } catch let error {
                DDLogError("RItemLocaleController: could not update locale - \(error)")
            }
        }
    }

    func storeLocale() {
        self.previousLocale = Locale.autoupdatingCurrent.identifier
    }
}
