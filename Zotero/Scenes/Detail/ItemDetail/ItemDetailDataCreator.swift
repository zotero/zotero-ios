//
//  ItemDetailDataCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct ItemDetailDataCreator {
    /// Creates `ItemDetailState.Data` for given type.
    /// - parameter type: Type of item detail screen.
    /// - parameter schemaController: Schema controller.
    /// - parameter dateParser: Date parser.
    /// - parameter fileStorage: File storage.
    /// - parameter urlDetector: URL detector.
    /// - parameter doiDetector: DOI detector.
    /// - returns: Populated data for given type.
    static func createData(from type: ItemDetailState.DetailType, schemaController: SchemaController, dateParser: DateParser,
                           fileStorage: FileStorage, urlDetector: UrlDetector, doiDetector: (String) -> Bool) throws -> (data: ItemDetailState.Data, attachmentErrors: [String: Error]) {
        switch type {
        case .creation(_, let type):
            let data = try creationData(itemType: type, schemaController: schemaController, dateParser: dateParser,
                                        urlDetector: urlDetector, doiDetector: doiDetector)
            return (data, [:])
        case .preview(let item), .duplication(let item, _):
            return try itemData(item: item, schemaController: schemaController, dateParser: dateParser,
                                fileStorage: fileStorage, urlDetector: urlDetector, doiDetector: doiDetector)
        }
    }

    /// Creates data for `ItemDetailState.DetailType.creator`. When creating new item, most data is empty. Only `itemType` is set to first value
    /// and appropriate (empty) fields are added for given type.
    /// - parameter schemaController: Schema controller for fetching item type and localization.
    /// - parameter dateParser: Date parser.
    /// - parameter urlDetector: URL detector.
    /// - parameter doiDetector: DOI detector.
    /// - returns: Data for item detail state.
    private static func creationData(itemType: String, schemaController: SchemaController, dateParser: DateParser,
                                     urlDetector: UrlDetector, doiDetector: (String) -> Bool) throws -> ItemDetailState.Data {
        guard let localizedType = schemaController.localized(itemType: itemType) else {
            throw ItemDetailError.schemaNotInitialized
        }

        let (fieldIds, fields, hasAbstract) = try fieldData(for: itemType, schemaController: schemaController,
                                                            dateParser: dateParser,
                                                            urlDetector: urlDetector, doiDetector: doiDetector)
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
                                    deletedAttachments: [],
                                    deletedNotes: [],
                                    deletedTags: [],
                                    dateModified: date,
                                    dateAdded: date)
    }

    /// Creates data for `ItemDetailState.DetailType.preview`. When previewing an item, data needs to be fetched and formatted from given item.
    /// - parameter item: Item to preview.
    /// - parameter schemaController: Schema controller for fetching item type/field data and localizations.
    /// - parameter dateParser: Date parser.
    /// - parameter fileStorage: File storage for checking availability of attachments.
    /// - parameter urlDetector: URL detector.
    /// - parameter doiDetector: DOI detector.
    /// - returns: Data for item detail state.
    private static func itemData(item: RItem, schemaController: SchemaController, dateParser: DateParser, fileStorage: FileStorage,
                                 urlDetector: UrlDetector, doiDetector: (String) -> Bool) throws -> (data: ItemDetailState.Data, attachmentErrors: [String: Error]) {
        guard let localizedType = schemaController.localized(itemType: item.rawType) else {
            throw ItemDetailError.typeNotSupported
        }

        var abstract: String?
        var values: [String: String] = [:]

        item.fields.forEach { field in
            switch field.key {
            case FieldKeys.Item.abstract:
                abstract = field.value
            default:
                values[field.key] = field.value
            }
        }

        let (fieldIds, fields, _) = try fieldData(for: item.rawType, schemaController: schemaController, dateParser: dateParser,
                                                  urlDetector: urlDetector, doiDetector: doiDetector, getExistingData: { key, _ in
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
                                 .compactMap(Note.init)
        let attachments: [Attachment]
        if item.rawType == ItemTypes.attachment {
            let attachment = AttachmentCreator.attachment(for: item, fileStorage: fileStorage, urlDetector: urlDetector)
            attachments = attachment.flatMap { [$0] } ?? []
        } else {
            let mappedAttachments = item.children.filter(.items(type: ItemTypes.attachment, notSyncState: .dirty, trash: false))
                                                 .sorted(byKeyPath: "displayTitle")
                                                 .compactMap({ item -> Attachment? in
                                                     return AttachmentCreator.attachment(for: item,
                                                                                         fileStorage: fileStorage,
                                                                                         urlDetector: urlDetector)
                                                 })
            attachments = Array(mappedAttachments)
        }

        var attachmentErrors: [String: Error] = [:]

        for attachment in attachments {
            switch attachment.contentType {
            case .snapshot(let htmlFile, _, _, let location):
                // Check whether local snapshots are actually unzipped
                guard location == .local else { continue }
                if !fileStorage.has(htmlFile) {
                    attachmentErrors[attachment.key] = ItemDetailError.cantUnzipSnapshot
                }
            case .file, .url:
                continue
            }
        }

        let tags = item.tags.sorted(byKeyPath: "tag.name").map(Tag.init)
        let data =  ItemDetailState.Data(title: item.baseTitle,
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
                                         deletedAttachments: [],
                                         deletedNotes: [],
                                         deletedTags: [],
                                         dateModified: item.dateModified,
                                         dateAdded: item.dateAdded)
        return (data, attachmentErrors)
    }

    /// Creates field data for given item type with the option of setting values for given fields.
    /// - parameter itemType: Item type for which fields will be created.
    /// - parameter schemaController: Schema controller for checking field data.
    /// - parameter dateParser: Date parser.
    /// - parameter urlDetector: URL detector.
    /// - parameter doiDetector: DOI detector.
    /// - parameter getExistingData: Closure for getting available data for given field. It passes the field key and baseField and receives existing
    ///                              field name and value if available.
    /// - returns: Tuple with 3 values: field keys of new fields, actual fields, `Bool` indicating whether this item type contains an abstract.
    static func fieldData(for itemType: String, schemaController: SchemaController, dateParser: DateParser, urlDetector: UrlDetector, doiDetector: (String) -> Bool,
                          getExistingData: ((String, String?) -> (String?, String?))? = nil) throws -> ([String], [String: ItemDetailState.Field], Bool) {
        guard var fieldSchemas = schemaController.fields(for: itemType) else {
            throw ItemDetailError.typeNotSupported
        }

        var fieldKeys = fieldSchemas.map({ $0.field })
        let abstractIndex = fieldKeys.firstIndex(of: FieldKeys.Item.abstract)

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
            let isTappable = ItemDetailDataCreator.isTappable(key: key, value: value, urlDetector: urlDetector, doiDetector: doiDetector)
            var additionalInfo: [ItemDetailState.Field.AdditionalInfoKey: String]?

            if key == FieldKeys.Item.date || baseField == FieldKeys.Item.date,
               let order = dateParser.parse(string: value)?.orderWithSpaces {
                additionalInfo = [.dateOrder: order]
            }

            fields[key] = ItemDetailState.Field(key: key,
                                                baseField: baseField,
                                                name: name,
                                                value: value,
                                                isTitle: false,
                                                isTappable: isTappable,
                                                additionalInfo: additionalInfo)
        }

        return (fieldKeys, fields, (abstractIndex != nil))
    }

    /// Returns all field keys for given item type, except those that should not appear as fields in item detail.
    static func allFieldKeys(for itemType: String, schemaController: SchemaController) -> [String] {
        guard let fieldSchemas = schemaController.fields(for: itemType) else { return [] }
        var fieldKeys = fieldSchemas.map({ $0.field })
        // Remove title and abstract keys, those 2 are used separately in Data struct
        if let index = fieldKeys.firstIndex(of: FieldKeys.Item.abstract) {
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

    /// Checks whether field is tappable based on its key and value.
    /// - parameter key: Key of field.
    /// - parameter value: Value of field.
    /// - parameter urlDetector: URL detector.
    /// - parameter doiDetector: DOIs detector.
    /// - returns: True if field is tappable, false otherwise.
    static func isTappable(key: String, value: String, urlDetector: UrlDetector, doiDetector: (String) -> Bool) -> Bool {
        switch key {
        case FieldKeys.Item.doi:
            return doiDetector(value)
        case FieldKeys.Item.Attachment.url:
            return urlDetector.isUrl(string: value)
        default:
            return false
        }
    }
}
