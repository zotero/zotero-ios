//
//  ItemDetailDataCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

struct ItemDetailDataCreator {
    /// Creates `ItemDetailState.Data` for given type.
    /// - parameter type: Type of item detail screen.
    /// - parameter schemaController: Schema controller.
    /// - parameter fileStorage: File storage.
    /// - returns: Populated data for given type.
    static func createData(from type: ItemDetailState.DetailType, schemaController: SchemaController, fileStorage: FileStorage) throws -> ItemDetailState.Data {
        switch type {
        case .creation:
            return try creationData(schemaController: schemaController)
        case .preview(let item), .duplication(let item, _):
            return try itemData(item: item, schemaController: schemaController, fileStorage: fileStorage)
        }
    }

    /// Creates data for `ItemDetailState.DetailType.creator`. When creating new item, most data is empty. Only `itemType` is set to first value
    /// and appropriate (empty) fields are added for given type.
    /// - parameter schemaController: Schema controller for fetching item type and localization.
    private static func creationData(schemaController: SchemaController) throws -> ItemDetailState.Data {
        guard let itemType = schemaController.itemTypes.sorted().first,
              let localizedType = schemaController.localized(itemType: itemType) else {
            throw ItemDetailError.schemaNotInitialized
        }

        let (fieldIds, fields, hasAbstract) = try fieldData(for: itemType, schemaController: schemaController)
        let date = Date()

        return ItemDetailState.Data(title: "",
                                    type: itemType,
                                    localizedType: localizedType,
                                    creators: [:],
                                    creatorIds: [],
                                    fields: fields,
                                    fieldIds: fieldIds,
                                    abstract: (hasAbstract ? "" : nil),
                                    notes: [],
                                    attachments: [],
                                    tags: [],
                                    dateModified: date,
                                    dateAdded: date)
    }

    /// Creates data for `ItemDetailState.DetailType.preview`. When previewing an item, data needs to be fetched and formatted from given item.
    /// - parameter item: Item to preview.
    /// - parameter schemaController: Schema controller for fetching item type/field data and localizations.
    /// - parameter fileStorage: File storage for checking availability of attachments.
    private static func itemData(item: RItem, schemaController: SchemaController, fileStorage: FileStorage) throws -> ItemDetailState.Data {
        guard let localizedType = schemaController.localized(itemType: item.rawType) else {
            throw ItemDetailError.typeNotSupported
        }

        var abstract: String?
        var values: [String: String] = [:]

        item.fields.forEach { field in
            switch field.key {
            case FieldKeys.abstract:
                abstract = field.value
            default:
                values[field.key] = field.value
            }
        }

        let (fieldIds, fields, _) = try fieldData(for: item.rawType, schemaController: schemaController, getExistingData: { key, _ in
            return (nil, values[key])
        })

        var creatorIds: [UUID] = []
        var creators: [UUID: ItemDetailState.Creator] = [:]
        for creator in item.creators.sorted(byKeyPath: "orderId") {
            guard let localizedType = schemaController.localized(creator: creator.rawType) else { continue }

            let creator = ItemDetailState.Creator(firstName: creator.firstName,
                                                  lastName: creator.lastName,
                                                  fullName: creator.name,
                                                  type: creator.rawType,
                                                  primary: schemaController.creatorIsPrimary(creator.rawType, itemType: item.rawType),
                                                  localizedType: localizedType)
            creatorIds.append(creator.id)
            creators[creator.id] = creator
        }

        let notes = item.children.filter(.items(type: ItemTypes.note, notSyncState: .dirty, trash: false))
                                 .sorted(byKeyPath: "displayTitle")
                                 .compactMap(ItemDetailState.Note.init)
        let attachments: [Attachment]
        if item.rawType == ItemTypes.attachment {
            let attachment = self.attachmentType(for: item, fileStorage: fileStorage).flatMap({ Attachment(item: item, type: $0) })
            attachments = attachment.flatMap { [$0] } ?? []
        } else {
            let mappedAttachments = item.children.filter(.items(type: ItemTypes.attachment, notSyncState: .dirty, trash: false))
                                                 .sorted(byKeyPath: "displayTitle")
                                                 .compactMap({ item -> Attachment? in
                                                     return attachmentType(for: item, fileStorage: fileStorage)
                                                                        .flatMap({ Attachment(item: item, type: $0) })
                                                 })
            attachments = Array(mappedAttachments)
        }

        let tags = item.tags.sorted(byKeyPath: "name").map(Tag.init)

        return ItemDetailState.Data(title: item.baseTitle,
                                    type: item.rawType,
                                    localizedType: localizedType,
                                    creators: creators,
                                    creatorIds: creatorIds,
                                    fields: fields,
                                    fieldIds: fieldIds,
                                    abstract: abstract,
                                    notes: Array(notes),
                                    attachments: attachments,
                                    tags: Array(tags),
                                    dateModified: item.dateModified,
                                    dateAdded: item.dateAdded)
    }

    /// Creates field data for given item type with the option of setting values for given fields.
    /// - parameter itemType: Item type for which fields will be created.
    /// - parameter schemaController: Schema controller for checking field data.
    /// - parameter getExistingData: Closure for getting available data for given field. It passes the field key and baseField and receives existing
    ///                              field name and value if available.
    /// - returns: Tuple with 3 values: field keys of new fields, actual fields, Bool indicating whether this item type contains an abstract.
    static func fieldData(for itemType: String, schemaController: SchemaController,
                          getExistingData: ((String, String?) -> (String?, String?))? = nil) throws -> ([String], [String: ItemDetailState.Field], Bool) {
        guard var fieldSchemas = schemaController.fields(for: itemType) else {
            throw ItemDetailError.typeNotSupported
        }

        var fieldKeys = fieldSchemas.map({ $0.field })
        let abstractIndex = fieldKeys.firstIndex(of: FieldKeys.abstract)

        // Remove title and abstract keys, those 2 are used separately in Data struct
        if let index = abstractIndex {
            fieldKeys.remove(at: index)
            fieldSchemas.remove(at: index)
        }
        if let key = schemaController.titleKey(for: itemType), let index = fieldKeys.firstIndex(of: key) {
            fieldKeys.remove(at: index)
            fieldSchemas.remove(at: index)
        }

        var fields: [String: ItemDetailState.Field] = [:]
        for (offset, key) in fieldKeys.enumerated() {
            let baseField = fieldSchemas[offset].baseField
            let (existingName, existingValue) = (getExistingData?(key, baseField) ?? (nil, nil))

            let name = existingName ?? schemaController.localized(field: key) ?? ""
            let value = existingValue ?? ""

            fields[key] = ItemDetailState.Field(key: key,
                                                baseField: baseField,
                                                name: name,
                                                value: value,
                                                isTitle: false)
        }

        return (fieldKeys, fields, (abstractIndex != nil))
    }

    /// Returns attachment content type type based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - returns: Attachment content type if recognized. Nil otherwise.
    private static func attachmentType(for item: RItem, fileStorage: FileStorage) -> Attachment.ContentType? {
        let contentType = item.fields.filter(.key(FieldKeys.contentType)).first?.value ?? ""
        if !contentType.isEmpty { // File attachment
            if let ext = contentType.extensionFromMimeType,
               let libraryId = item.libraryObject?.identifier {
                let filename = item.fields.filter(.key(FieldKeys.filename)).first?.value ?? (item.displayTitle + "." + ext)
                let file = Files.objectFile(for: .item, libraryId: libraryId, key: item.key, ext: ext)
                let isLocal = fileStorage.has(file)
                return .file(file: file, filename: filename, isLocal: isLocal)
            } else {
                DDLogError("Attachment: mimeType/extension unknown (\(contentType)) for item (\(item.key))")
                return nil
            }
        } else { // Some other attachment (url, etc.)
            if let urlString = item.fields.filter("key = %@", "url").first?.value,
               let url = URL(string: urlString) {
                return .url(url)
            } else {
                DDLogError("Attachment: unknown attachment, fields: \(item.fields.map({ $0.key }))")
                return nil
            }
        }
    }

    /// Returns all field keys for given item type, except those that should not appear as fields in item detail.
    static func allFieldKeys(for itemType: String, schemaController: SchemaController) -> [String] {
        guard let fieldSchemas = schemaController.fields(for: itemType) else { return [] }
        var fieldKeys = fieldSchemas.map({ $0.field })
        // Remove title and abstract keys, those 2 are used separately in Data struct
        if let index = fieldKeys.firstIndex(of: FieldKeys.abstract) {
            fieldKeys.remove(at: index)
        }
        if let key = schemaController.titleKey(for: itemType), let index = fieldKeys.firstIndex(of: key) {
            fieldKeys.remove(at: index)
        }
        return fieldKeys
    }

    /// Returns filtered, sorted array of keys for fields that have non-empty values.
    static func filteredFieldKeys(from fieldKeys: [String], fields: [String: ItemDetailState.Field]) -> [String] {
        var newFieldKeys: [String] = []
        fieldKeys.forEach { key in
            if !(fields[key]?.value ?? "").isEmpty {
                newFieldKeys.append(key)
            }
        }
        return newFieldKeys
    }
}
