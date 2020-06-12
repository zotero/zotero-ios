//
//  ItemDetailState.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack

struct ItemDetailState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let editing = Changes(rawValue: 1 << 0)
        static let type = Changes(rawValue: 1 << 1)
        static let downloadProgress = Changes(rawValue: 1 << 2)
        static let attachmentFilesRemoved = Changes(rawValue: 1 << 3)
    }

    enum DetailType {
        case creation(collectionKey: String?, type: String)
        case duplication(RItem, collectionKey: String?)
        case preview(RItem)

        var previewKey: String? {
            switch self {
            case .preview(let item):
                return item.key
            default:
                return nil
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
            case dateOrder
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
            if !self.fullName.isEmpty {
                return self.fullName
            }

            guard !self.firstName.isEmpty || !self.lastName.isEmpty else { return "" }

            var name = self.lastName
            if !self.lastName.isEmpty {
                name += ", "
            }
            return name + self.firstName
        }

        var isEmpty: Bool {
            return self.fullName.isEmpty && self.firstName.isEmpty && self.lastName.isEmpty
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

        mutating func change(namePresentation: NamePresentation) {
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
        var localizedType: String
        var creators: [UUID: Creator]
        var creatorIds: [UUID]
        var fields: [String: Field]
        var fieldIds: [String]
        var abstract: String?
        var notes: [Note]
        var attachments: [Attachment]
        var tags: [Tag]

        var dateModified: Date
        let dateAdded: Date

        var maxFieldTitleWidth: CGFloat = 0
        var maxNonemptyFieldTitleWidth: CGFloat = 0

        func databaseFields(schemaController: SchemaController) -> [Field] {
            var allFields = Array(self.fields.values)

            if let titleKey = schemaController.titleKey(for: self.type) {
                allFields.append(Field(key: titleKey,
                                       baseField: (titleKey != FieldKeys.title ? FieldKeys.title : nil),
                                       name: "",
                                       value: self.title,
                                       isTitle: true,
                                       isTappable: false))
            }

            if let abstract = self.abstract {
                allFields.append(Field(key: FieldKeys.abstract,
                                       baseField: nil,
                                       name: "",
                                       value: abstract,
                                       isTitle: false,
                                       isTappable: false))
            }


            return allFields
        }
    }

    enum Diff {
        case attachments(insertions: [Int], deletions: [Int], reloads: [Int])
        case creators(insertions: [Int], deletions: [Int], reloads: [Int])
        case notes(insertions: [Int], deletions: [Int], reloads: [Int])
        case tags(insertions: [Int], deletions: [Int], reloads: [Int])

        var insertions: [Int] {
            switch self {
            case .attachments(let insertions, _, _),
                 .creators(let insertions, _, _),
                 .notes(let insertions, _, _),
                 .tags(let insertions, _, _):
                return insertions
            }
        }

        var deletions: [Int] {
            switch self {
            case .attachments(_, let deletions, _),
                 .creators(_, let deletions, _),
                 .notes(_, let deletions, _),
                 .tags(_, let deletions, _):
                return deletions
            }
        }

        var reloads: [Int] {
            switch self {
            case .attachments(_, _, let reloads),
                 .creators(_, _, let reloads),
                 .notes(_, _, let reloads),
                 .tags(_, _, let reloads):
                return reloads
            }
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
    var diff: Diff?
    var error: ItemDetailError?
    var metadataTitleMaxWidth: CGFloat
    var openAttachment: (Attachment, Int)?
    var updateAttachmentIndex: Int?

    init(type: DetailType, library: Library, userId: Int, data: Data, error: ItemDetailError? = nil) {
        self.changes = []
        self.userId = userId
        self.library = library
        self.type = type
        self.data = data
        self.metadataTitleMaxWidth = 0
        self.error = error
        self.isSaving = false

        switch type {
        case .preview, .duplication:
            self.isEditing = type.isCreation
            if !self.isEditing {
                // Filter fieldIds to show only non-empty values
                self.data.fieldIds = ItemDetailDataCreator.filteredFieldKeys(from: self.data.fieldIds, fields: self.data.fields)
            }
        case .creation:
            self.isEditing = true
        }
    }

    init(type: DetailType, library: Library, userId: Int, error: ItemDetailError) {
        self.init(type: type,
                  library: library,
                  userId: userId,
                  data: Data(title: "", type: "", localizedType: "",
                             creators: [:], creatorIds: [],
                             fields: [:], fieldIds: [],
                             abstract: nil, notes: [],
                             attachments: [], tags: [],
                             dateModified: Date(), dateAdded: Date()),
                  error: error)
    }

    mutating func cleanup() {
        self.changes = []
        self.error = nil
        self.diff = nil
        self.openAttachment = nil
        self.updateAttachmentIndex = nil
    }
}
