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
    var rawChangedFields: UInt { get set }
    var updateParameters: [String: Any]? { get }

    func resetChanges()
}

extension Updatable {
    func resetChanges() {
        self.rawChangedFields = 0
    }
}

extension RCollection: Updatable {
    var updateParameters: [String: Any]? {
        let changes = self.changedFields

        guard !changes.isEmpty else { return nil }

        if changes.contains(.all) {
            return self.allParameters
        }

        var parameters: [String: Any] = ["key": self.key,
                                         "version": self.version]
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
        if changes.contains(.dateModified) {
            parameters["dateModified"] = Formatter.iso8601.string(from: self.dateModified)
        }
        return parameters
    }

    private var allParameters: [String: Any] {
        return ["key": self.key,
                "version": self.version,
                "dateModified": Formatter.iso8601.string(from: self.dateModified),
                "name": self.name,
                "parentCollection": (self.parent?.key ?? false)]
    }
}

extension RSearch: Updatable {
    var updateParameters: [String: Any]? {
        let changes = self.changedFields

        guard !changes.isEmpty else { return nil }

        if changes.contains(.all) {
            return self.allParameters
        }

        var parameters: [String: Any] = ["key": self.key,
                                         "version": self.version]
        if changes.contains(.name) {
            parameters["name"] = self.name
        }
        if changes.contains(.conditions) {
            parameters["conditions"] = self.sortedConditionParameters
        }
        if changes.contains(.dateModified) {
            parameters["dateModified"] = Formatter.iso8601.string(from: self.dateModified)
        }
        return parameters
    }

    private var allParameters: [String: Any] {
        return ["key": self.key,
                "version": self.version,
                "dateModified": Formatter.iso8601.string(from: self.dateModified),
                "name": self.name,
                "conditions": self.sortedConditionParameters]
    }

    private var sortedConditionParameters: [[String: Any]] {
        return self.conditions.sorted(byKeyPath: "sortId").map({ $0.allParameters })
    }
}

extension RCondition {
    fileprivate var allParameters: [String: Any] {
        return ["condition": self.condition,
                "operator": self.operator,
                "value": self.value]
    }
}
