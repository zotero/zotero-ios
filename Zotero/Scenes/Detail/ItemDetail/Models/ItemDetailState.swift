//
//  ItemDetailState.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import OrderedCollections

import CocoaLumberjackSwift
import RealmSwift

struct ItemDetailState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let editing = Changes(rawValue: 1 << 0)
        static let type = Changes(rawValue: 1 << 1)
        static let reloadedData = Changes(rawValue: 1 << 3)
        static let item = Changes(rawValue: 1 << 4)
    }

    enum DetailType {
        case creation(type: String, child: Attachment?, collectionKey: String?)
        case duplication(itemKey: String, collectionKey: String?)
        case preview(key: String)

        var previewKey: String? {
            switch self {
            case .preview(let key): return key
            case .duplication, .creation: return nil
            }
        }
    }

    struct Field: Identifiable, Equatable, Hashable {
        enum AdditionalInfoKey: Hashable {
            case dateOrder, formattedDate, formattedEditDate
        }

        let key: String
        let baseField: String?
        var name: String
        var value: String
        let isTitle: Bool
        let isEditable: Bool
        var isTappable: Bool
        var additionalInfo: [AdditionalInfoKey: String]?

        var id: String { return self.key }

        static func == (lhs: Field, rhs: Field) -> Bool {
            return lhs.key == rhs.key && lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(self.key)
            hasher.combine(self.value)
        }
    }

    struct Creator: Identifiable, Equatable, Hashable {
        enum NamePresentation: Int, Codable {
            case separate, full

            mutating func toggle() {
                self = self == .full ? .separate : .full
            }
        }

        let id: String
        var type: String
        var primary: Bool
        var localizedType: String
        var fullName: String
        var firstName: String
        var lastName: String
        var namePresentation: NamePresentation {
            willSet {
                self.change(namePresentation: newValue)
            }
        }

        var name: String {
            switch self.namePresentation {
            case .full:
                return self.fullName

            case .separate:
                if self.lastName.isEmpty {
                    return self.firstName
                }
                if self.firstName.isEmpty {
                    return self.lastName
                }
                return self.lastName + ", " + self.firstName
            }
        }

        var isEmpty: Bool {
            switch self.namePresentation {
            case .full:
                return self.fullName.isEmpty

            case .separate:
                return self.firstName.isEmpty && self.lastName.isEmpty
            }
        }

        init(uuid: String, firstName: String, lastName: String, fullName: String, type: String, primary: Bool, localizedType: String) {
            self.id = uuid
            self.type = type
            self.primary = primary
            self.localizedType = localizedType
            self.fullName = fullName
            self.firstName = firstName
            self.lastName = lastName
            self.namePresentation = fullName.isEmpty ? .separate : .full
        }

        init(type: String, primary: Bool, localizedType: String, namePresentation: NamePresentation) {
            self.id = UUID().uuidString
            self.type = type
            self.primary = primary
            self.localizedType = localizedType
            self.fullName = ""
            self.firstName = ""
            self.lastName = ""
            self.namePresentation = namePresentation
        }

        private mutating func change(namePresentation: NamePresentation) {
            guard namePresentation != self.namePresentation else { return }

            switch namePresentation {
            case .full:
                self.fullName = self.firstName + (self.firstName.isEmpty ? "" : " ") + self.lastName
                self.firstName = ""
                self.lastName = ""
                
            case .separate:
                if self.fullName.isEmpty {
                    self.firstName = ""
                    self.lastName = ""
                    return
                }

                if !self.fullName.contains(" ") {
                    self.lastName = self.fullName
                    self.firstName = ""
                    return
                }

                let components = self.fullName.components(separatedBy: " ")
                self.firstName = components.dropLast().joined(separator: " ")
                self.lastName = components.last ?? ""
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(type)
            hasher.combine(primary)
            hasher.combine(fullName)
            hasher.combine(firstName)
            hasher.combine(lastName)
        }
    }

    struct Data: Equatable {
        var title: String
        var attributedTitle: NSAttributedString
        var type: String
        var localizedType: String
        var creators: OrderedDictionary<String, Creator>
        var fields: OrderedDictionary<String, Field>
        var abstract: String?

        var dateModified: Date
        let dateAdded: Date

        var isAttachment: Bool {
            return type == ItemTypes.attachment
        }

        func databaseFields(schemaController: SchemaController) -> [Field] {
            var allFields = Array(fields.values)

            if let titleKey = schemaController.titleKey(for: type) {
                allFields.append(Field(
                    key: titleKey,
                    baseField: (titleKey != FieldKeys.Item.title ? FieldKeys.Item.title : nil),
                    name: "",
                    value: title,
                    isTitle: true,
                    isEditable: !isAttachment,
                    isTappable: false
                ))
            }

            if let abstract {
                allFields.append(Field(
                    key: FieldKeys.Item.abstract,
                    baseField: nil,
                    name: "",
                    value: abstract,
                    isTitle: false,
                    isEditable: isAttachment,
                    isTappable: false
                ))
            }

            return allFields
        }

        static var empty: Data {
            let date = Date()
            return Data(
                title: "",
                attributedTitle: .init(string: ""),
                type: "",
                localizedType: "",
                creators: [:],
                fields: [:],
                abstract: nil,
                dateModified: date,
                dateAdded: date
            )
        }
    }

    enum TableViewReloadType {
        case row(ItemDetailCollectionViewHandler.Row)
        case rows([ItemDetailCollectionViewHandler.Row])
        case section(ItemDetailCollectionViewHandler.Section)
    }

    let key: String
    let userId: Int

    var library: Library
    var type: DetailType
    var changes: Changes
    var isEditing: Bool
    var isSaving: Bool
    var data: Data
    var snapshot: Data?
    var promptSnapshot: Data?
    var visibleFieldIds: OrderedSet<String>
    var notes: [Note]
    var attachments: [Attachment]
    var tags: [Tag]
    var reload: TableViewReloadType?
    var error: ItemDetailError?
    var metadataTitleMaxWidth: CGFloat
    var updateAttachmentKey: String?
    var isLoadingData: Bool
    var observationToken: NotificationToken?
    var libraryToken: NotificationToken?
    var attachmentToOpen: String?
    // Identifiers of items which are currently being processed in background and should be disabled in UI
    var backgroundProcessedItems: Set<String>
    // Child key which should be initially shown on screen
    var preScrolledChildKey: String?
    var hideController: Bool
    var titleFont: UIFont {
        return .preferredFont(forTextStyle: .title1)
    }

    @UserDefault(key: "ItemDetailAbstractCollapsedKey", defaultValue: false)
    var abstractCollapsed: Bool

    var mainAttachmentKey: String? {
        let url = self.data.fields[FieldKeys.Item.url]?.value
        return AttachmentCreator.mainPdfAttachment(from: self.attachments, parentUrl: url)?.key
    }

    init(type: DetailType, libraryId: LibraryIdentifier, preScrolledChildKey: String?, userId: Int) {
        switch type {
        case .preview(let key):
            self.key = key
            self.isEditing = false

        case .creation, .duplication:
            self.key = KeyGenerator.newKey
            self.isEditing = true
        }

        self.type = type
        self.userId = userId
        self.changes = []
        self.data = .empty
        self.visibleFieldIds = []
        self.attachments = []
        self.notes = []
        self.tags = []
        self.metadataTitleMaxWidth = 0
        self.error = nil
        self.isSaving = false
        self.backgroundProcessedItems = []
        self.isLoadingData = true
        self.preScrolledChildKey = preScrolledChildKey
        self.hideController = false

        switch libraryId {
        case .custom:
            library = Library(identifier: libraryId, name: L10n.Libraries.myLibrary, metadataEditable: true, filesEditable: true)

        case .group:
            library = Library(identifier: libraryId, name: L10n.unknown, metadataEditable: false, filesEditable: false)
        }
    }

    mutating func cleanup() {
        self.changes = []
        self.error = nil
        self.updateAttachmentKey = nil
        self.reload = nil
    }
}
