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

protocol Updatable: class {
    var rawChangedFields: Int16 { get set }
    var updateParameters: [String: Any]? { get }
    var isChanged: Bool { get }

    func resetChanges()
}

extension Updatable {
    func resetChanges() {
        if self.isChanged {
            self.rawChangedFields = 0
        }
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
            if let key = self.parent?.key {
                parameters["parentCollection"] = key
            } else {
                parameters["parentCollection"] = false
            }
        }

        return parameters
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
            parameters["tags"] = Array(self.tags.map({ ["tag": $0.name] }))
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
                if field.key == FieldKeys.md5 || field.key == FieldKeys.mtime {
                    // Even though these field keys are set for the RItem object, we ignore them when submitting the attachment item itself,
                    // but they are used in file upload
                    parameters[field.key] = ""
                } else {
                    parameters[field.key] = field.value
                }
            }
        }
        
        return parameters
    }

    func resetChanges() {
        self.rawChangedFields = 0
        self.fields.filter("changed = true").forEach { field in
            field.changed = false
        }
    }
}

extension RCreator {
    fileprivate var updateParameters: [String: Any] {
        var parameters: [String: Any] = ["creatorType": self.rawType]
        if !self.name.isEmpty {
            parameters["name"] = self.name
        }
        if !self.firstName.isEmpty || !self.lastName.isEmpty {
            parameters["firstName"] = self.firstName
            parameters["lastName"] = self.lastName
        }
        return parameters
    }
}
