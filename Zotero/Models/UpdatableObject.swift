//
//  UpdatableObject.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias UpdatableObject = Updatable&Object

enum UpdatableChangeType: Int, PersistableEnum {
    case sync = 0
    case user = 1
}

protocol Updatable: AnyObject {
    var rawChangedFields: Int16 { get set }
    var changeType: UpdatableChangeType { get set }
    var updateParameters: [String: Any]? { get }
    var isChanged: Bool { get }
    var selfOrChildChanged: Bool { get }

    func resetChanges()
    func markAsChanged(in database: Realm)
}

extension Updatable {
    func resetChanges() {
        guard self.isChanged else { return }
        self.rawChangedFields = 0
        self.changeType = .sync
    }

    var isChanged: Bool {
        return self.rawChangedFields > 0
    }
}

extension RCollection: Updatable {
    var updateParameters: [String: Any]? {
        guard self.isChanged else { return nil }

        var parameters: [String: Any] = ["key": self.key,
                                         "version": self.version]

        let changes = self.changedFields
        if changes.contains(.name) {
            parameters["name"] = self.name
        }
        if changes.contains(.parent) {
            if let key = self.parentKey {
                parameters["parentCollection"] = key
            } else {
                parameters["parentCollection"] = false
            }
        }

        return parameters
    }

    var selfOrChildChanged: Bool {
        return self.isChanged
    }

    func markAsChanged(in database: Realm) {
        self.changedFields = .name
        self.changeType = .user
        self.deleted = false
        self.version = 0

        if self.parentKey != nil {
            self.changedFields.insert(.parent)
        }

        self.items.forEach { item in
            item.changedFields = .collections
            item.changeType = .user
        }

        if let libraryId = self.libraryId {
            let children = database.objects(RCollection.self).filter(.parentKey(self.key, in: libraryId))
            children.forEach { child in
                child.markAsChanged(in: database)
            }
        }
    }
}

extension RSearch: Updatable {
    var updateParameters: [String: Any]? {
        guard self.isChanged else { return nil }

        var parameters: [String: Any] = ["key": self.key,
                                         "version": self.version,
                                         "dateModified": Formatter.iso8601.string(from: self.dateModified)]

        let changes = self.changedFields
        if changes.contains(.name) {
            parameters["name"] = self.name
        }
        if changes.contains(.conditions) {
            parameters["conditions"] = self.sortedConditionParameters
        }

        return parameters
    }

    private var sortedConditionParameters: [[String: Any]] {
        return self.conditions.sorted(byKeyPath: "sortId").map({ $0.updateParameters })
    }

    var selfOrChildChanged: Bool {
        return self.isChanged
    }

    func markAsChanged(in database: Realm) {
        self.changedFields = .all
        self.changeType = .user
        self.deleted = false
        self.version = 0
    }
}

extension RCondition {
    fileprivate var updateParameters: [String: Any] {
        return ["condition": self.condition,
                "operator": self.operator,
                "value": self.value]
    }
}

extension RItem: Updatable {
    var updateParameters: [String : Any]? {
        guard self.isChanged else { return nil }

        var changedPageIndex: Int?
        var changedLineWidth: Double?
        var parameters: [String: Any] = ["key": self.key,
                                         "version": self.version,
                                         "dateModified": Formatter.iso8601.string(from: self.dateModified),
                                         "dateAdded": Formatter.iso8601.string(from: self.dateAdded)]

        let changes = self.changedFields
        if changes.contains(.type) {
            parameters["itemType"] = self.rawType
        }
        if changes.contains(.trash) {
            parameters["deleted"] = self.trash
        }
        if changes.contains(.tags) {
            parameters["tags"] = Array(self.tags.map({ ["tag": ($0.tag?.name ?? ""), "type": $0.type.rawValue] }))
        }
        if changes.contains(.collections) {
            parameters["collections"] = Array(self.collections.map({ $0.key }))
        }
        if changes.contains(.relations) {
            var relations: [String: String] = [:]
            self.relations.forEach { relation in
                relations[relation.type] = relation.urlString
            }
            parameters["relations"] = relations
        }
        if changes.contains(.parent) {
            parameters["parentItem"] = self.parent?.key ?? false
        }
        if changes.contains(.creators) {
            parameters["creators"] = Array(self.creators.map({ $0.updateParameters }))
        }
        if changes.contains(.fields) {
            self.fields.filter("changed = true").forEach { field in
                switch field.key {
                case FieldKeys.Item.Attachment.md5, FieldKeys.Item.Attachment.mtime:
                    // Even though these field keys are set for the RItem object, we ignore them when submitting the attachment item itself,
                    // but they are used in file upload
                    parameters[field.key] = ""
                case FieldKeys.Item.Annotation.pageIndex:
                    changedPageIndex = Int(field.value) ?? 0
                case FieldKeys.Item.Annotation.lineWidth:
                    changedLineWidth = Double(field.value) ?? 0
                default:
                    parameters[field.key] = field.value
                }
            }
        }
        if changes.contains(.rects) || changes.contains(.paths) || changedPageIndex != nil || changedLineWidth != nil {
            let pageIndex = changedPageIndex ?? (self.fields.filter(.key(FieldKeys.Item.Annotation.pageIndex)).first.flatMap({ Int($0.value) }) ?? 0)
            let lineWidth = changedLineWidth ?? (self.fields.filter(.key(FieldKeys.Item.Annotation.lineWidth)).first.flatMap({ Double($0.value) }) ?? 0)
            parameters[FieldKeys.Item.Annotation.position] = self.createAnnotationPosition(pageIndex: pageIndex, rects: self.rects, paths: self.paths, lineWidth: lineWidth)
        }
        
        return parameters
    }

    private func createAnnotationPosition(pageIndex: Int, rects: List<RRect>, paths: List<RPath>, lineWidth: Double) -> String {
        var jsonData: [String: Any] = [FieldKeys.Item.Annotation.pageIndex: pageIndex]

        if !rects.isEmpty {
            var rectArray: [[Double]] = []
            rects.forEach { rRect in
                rectArray.append([rRect.minX.rounded(to: 3), rRect.minY.rounded(to: 3), rRect.maxX.rounded(to: 3), rRect.maxY.rounded(to: 3)])
            }
            jsonData[FieldKeys.Item.Annotation.rects] = rectArray
        } else if !paths.isEmpty {
            var apiPaths: [[Double]] = []
            for path in paths.sorted(byKeyPath: "sortIndex") {
                apiPaths.append(path.coordinates.sorted(byKeyPath: "sortIndex").map({ $0.value.rounded(to: 3) }))
            }
            jsonData[FieldKeys.Item.Annotation.paths] = apiPaths
            jsonData[FieldKeys.Item.Annotation.lineWidth] = lineWidth.rounded(to: 3)
        }

        return (try? JSONSerialization.data(withJSONObject: jsonData, options: [])).flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
    }

    func resetChanges() {
        guard self.isChanged else { return }

        self.rawChangedFields = 0
        self.changeType = .sync
        self.fields.filter("changed = true").forEach { field in
            field.changed = false
        }
    }

    var selfOrChildChanged: Bool {
        if self.isChanged {
            return true
        }

        for child in self.children {
            if child.selfOrChildChanged {
                return true
            }
        }

        return false
    }

    func markAsChanged(in database: Realm) {
        self.changedFields = self.currentChanges
        self.changeType = .user
        self.deleted = false
        self.version = 0

        for field in self.fields {
            guard !field.value.isEmpty else { continue }
            field.changed = true
        }

        if self.rawType == ItemTypes.attachment && self.fields.filter(.key(FieldKeys.Item.Attachment.linkMode)).first?.value == LinkMode.importedFile.rawValue {
            self.attachmentNeedsSync = true
        }

        self.children.forEach { child in
            child.markAsChanged(in: database)
        }
    }

    private var currentChanges: RItemChanges {
        var changes: RItemChanges = [.type, .fields]
        if !self.creators.isEmpty {
            changes.insert(.creators)
        }
        if self.collections.isEmpty {
            changes.insert(.collections)
        }
        if self.parent != nil {
            changes.insert(.parent)
        }
        if !self.tags.isEmpty {
            changes.insert(.tags)
        }
        if self.trash {
            changes.insert(.trash)
        }
        if !self.relations.isEmpty {
            changes.insert(.relations)
        }
        if !self.rects.isEmpty {
            changes.insert(.rects)
        }
        if !self.paths.isEmpty {
            changes.insert(.paths)
        }
        return changes
    }
}

extension RCreator {
    fileprivate var updateParameters: [String: Any] {
        var parameters: [String: Any] = ["creatorType": self.rawType]
        if !self.name.isEmpty {
            parameters["name"] = self.name
        } else if !self.firstName.isEmpty || !self.lastName.isEmpty {
            parameters["firstName"] = self.firstName
            parameters["lastName"] = self.lastName
        }
        return parameters
    }
}

extension RPageIndex: Updatable {
    var updateParameters: [String : Any]? {
        guard let libraryId = self.libraryId else { return nil }
        
        let libraryPart: String
        switch libraryId {
        case .custom:
            libraryPart = "u"
        case .group(let groupId):
            libraryPart = "g\(groupId)"
        }

        return ["lastPageIndex_\(libraryPart)_\(self.key)": ["value": self.index]]
    }

    var selfOrChildChanged: Bool {
        return self.isChanged
    }

    func markAsChanged(in database: Realm) {}
}
