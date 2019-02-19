//
//  ItemDetailStore.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift
import RxSwift

enum ItemDetailAction {
    case load
}

enum ItemDetailStoreError: Equatable {
    case typeNotSupported
}

struct ItemDetailField {
    let name: String
    let value: String
}

struct ItemDetailAttachment {
    let title: String

    init(object: RItem) {
        self.title = object.title
    }
}

struct ItemDetailState {
    let item: RItem

    fileprivate(set) var fields: [ItemDetailField]
    fileprivate(set) var attachments: [ItemDetailAttachment]
    fileprivate(set) var error: ItemDetailStoreError?

    fileprivate var version: Int

    init(item: RItem) {
        self.item = item
        self.fields = []
        self.attachments = []
        self.version = 0
    }
}

extension ItemDetailState: Equatable {
    static func == (lhs: ItemDetailState, rhs: ItemDetailState) -> Bool {
        return lhs.version == rhs.version && lhs.error == rhs.error
    }
}

class ItemDetailStore: Store {
    typealias Action = ItemDetailAction
    typealias State = ItemDetailState

    let dbStorage: DbStorage
    let itemFieldsController: ItemFieldsController

    var updater: StoreStateUpdater<ItemDetailState>

    init(initialState: ItemDetailState, dbStorage: DbStorage, itemFieldsController: ItemFieldsController) {
        self.dbStorage = dbStorage
        self.itemFieldsController = itemFieldsController
        self.updater = StoreStateUpdater(initialState: initialState)
    }

    func handle(action: ItemDetailAction) {
        switch action {
        case .load:
            self.loadData()
        }
    }

    private func loadData() {
        guard let sortedFieldNames = self.itemFieldsController.fields[self.state.value.item.rawType] else {
            self.updater.updateState { newState in
                newState.error = .typeNotSupported
            }
            return
        }

        var values: [String: String] = [:]
        self.state.value.item.fields.forEach { field in
            values[field.key] = field.value
        }
        let fields = sortedFieldNames.map { name -> ItemDetailField in
            let value = values[name] ?? ""
            return ItemDetailField(name: name, value: value)
        }

        let attachments = Array(self.state.value.item.children.sorted(byKeyPath: "title").map(ItemDetailAttachment.init))

        self.updater.updateState { newState in
            newState.attachments = attachments
            newState.fields = fields
            newState.version += 1
        }
    }
}
