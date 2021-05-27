//
//  ItemDetailState.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

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

        var isCreation: Bool {
            switch self {
            case .preview:
                return false
            case .creation, .duplication:
                return true
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
        var isTappable: Bool
        var additionalInfo: [AdditionalInfoKey: String]?

        var id: String { return self.key }

        static func ==(lhs: Field, rhs: Field) -> Bool {
            return lhs.key == rhs.key && lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(self.key)
            hasher.combine(self.value)
        }
    }

    struct Creator: Identifiable, Equatable, Hashable {
        enum NamePresentation: Equatable {
            case separate, full

            mutating func toggle() {
                self = self == .full ? .separate : .full
            }
        }

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

        let id: UUID

        init(firstName: String, lastName: String, fullName: String, type: String, primary: Bool, localizedType: String) {
            self.id = UUID()
            self.type = type
            self.primary = primary
            self.localizedType = localizedType
            self.fullName = fullName
            self.firstName = firstName
            self.lastName = lastName
            self.namePresentation = fullName.isEmpty ? .separate : .full
        }

        init(type: String, primary: Bool, localizedType: String) {
            self.id = UUID()
            self.type = type
            self.primary = primary
            self.localizedType = localizedType
            self.fullName = ""
            self.firstName = ""
            self.lastName = ""
            self.namePresentation = .full
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
            hasher.combine(self.type)
            hasher.combine(self.primary)
            hasher.combine(self.fullName)
            hasher.combine(self.firstName)
            hasher.combine(self.lastName)
        }
    }

    struct Data: Equatable {
        var title: String
        var type: String
        var isAttachment: Bool
        var localizedType: String
        var creators: [UUID: Creator]
        var creatorIds: [UUID]
        var fields: [String: Field]
        var fieldIds: [String]
        var abstract: String?
        var notes: [Note]
        var attachments: [Attachment]
        var tags: [Tag]

        var deletedAttachments: Set<String>
        var deletedNotes: Set<String>
        var deletedTags: Set<String>

        var dateModified: Date
        let dateAdded: Date

        var maxFieldTitleWidth: CGFloat = 0
        var maxNonemptyFieldTitleWidth: CGFloat = 0

        var mainAttachmentIndex: Int? {
            return self.attachments.firstIndex(where: {
                switch $0.type {
                case .file(_, let contentType, let location, _):
                    return location != .remoteMissing && contentType == "application/pdf"
                case .url:
                    return false
                }
            })
        }

        func databaseFields(schemaController: SchemaController) -> [Field] {
            var allFields = Array(self.fields.values)

            if let titleKey = schemaController.titleKey(for: self.type) {
                allFields.append(Field(key: titleKey,
                                       baseField: (titleKey != FieldKeys.Item.title ? FieldKeys.Item.title : nil),
                                       name: "",
                                       value: self.title,
                                       isTitle: true,
                                       isTappable: false))
            }

            if let abstract = self.abstract {
                allFields.append(Field(key: FieldKeys.Item.abstract,
                                       baseField: nil,
                                       name: "",
                                       value: abstract,
                                       isTitle: false,
                                       isTappable: false))
            }


            return allFields
        }

        static var empty: Data {
            let date = Date()
            return Data(title: "", type: "", isAttachment: false, localizedType: "", creators: [:], creatorIds: [], fields: [:], fieldIds: [], abstract: nil, notes: [], attachments: [], tags: [],
                        deletedAttachments: [], deletedNotes: [], deletedTags: [], dateModified: date, dateAdded: date, maxFieldTitleWidth: 0, maxNonemptyFieldTitleWidth: 0)
        }
    }

    let library: Library
    let userId: Int

    var changes: Changes
    var isEditing: Bool
    var isSaving: Bool
    var type: DetailType
    var data: Data
    var snapshot: Data?
    var promptSnapshot: Data?
    var updatedSection: ItemDetailTableViewHandler.Section?
    var sectionNeedsReload: Bool
    var error: ItemDetailError?
    var metadataTitleMaxWidth: CGFloat
    var updateAttachmentIndex: Int?
    var isLoadingData: Bool
    var observationToken: NotificationToken?

    @UserDefault(key: "ItemDetailAbstractCollapsedKey", defaultValue: false)
    var abstractCollapsed: Bool

    init(type: DetailType, library: Library, userId: Int) {
        self.changes = []
        self.userId = userId
        self.library = library
        self.type = type
        self.data = .empty
        self.metadataTitleMaxWidth = 0
        self.error = nil
        self.isSaving = false
        self.isLoadingData = true
        self.sectionNeedsReload = true

        switch type {
        case .preview, .duplication:
            self.isEditing = type.isCreation
        case .creation:
            self.isEditing = true
        }
    }

    mutating func cleanup() {
        self.changes = []
        self.error = nil
        self.updateAttachmentIndex = nil
        self.updatedSection = nil
    }
}
