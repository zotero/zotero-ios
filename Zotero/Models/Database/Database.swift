//
//  Database.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift
import Network

struct Database {
    private static let schemaVersion: UInt64 = 39

    static func mainConfiguration(url: URL, fileStorage: FileStorage) -> Realm.Configuration {
        var config = Realm.Configuration(fileURL: url,
                                         schemaVersion: schemaVersion,
                                         migrationBlock: createMigrationBlock(fileStorage: fileStorage),
                                         deleteRealmIfMigrationNeeded: false)
        config.objectTypes = [RCollection.self, RCreator.self, RCustomLibrary.self, RGroup.self, RItem.self, RItemField.self, RLink.self, RPageIndex.self, RPath.self, RPathCoordinate.self, RRect.self,
                              RRelation.self, RSearch.self, RCondition.self, RTag.self, RTypedTag.self, RUser.self, RWebDavDeletion.self, RVersions.self, RObjectChange.self]
        return config
    }

    static func bundledDataConfiguration(fileStorage: FileStorage) -> Realm.Configuration {
        let url = Files.bundledDataDbFile.createUrl()
        var config = Realm.Configuration(fileURL: url,
                                         schemaVersion: schemaVersion,
                                         migrationBlock: createMigrationBlock(fileStorage: fileStorage),
                                         deleteRealmIfMigrationNeeded: false)
        config.objectTypes = [RTranslatorMetadata.self, RStyle.self]
        return config
    }

    private static func createMigrationBlock(fileStorage: FileStorage) -> MigrationBlock {
        return { migration, schemaVersion in
            if schemaVersion < 35 {
                // Migrate to new object change model.
                self.migrateObjectChange(migration: migration)
            }
            if schemaVersion < 36 {
                self.migrateTagNames(migration: migration)
            }
            if schemaVersion < 37 {
                self.extractItemHtmlFreeContent(migration: migration)
            }
            if schemaVersion < 39 {
                self.addUuidsToCreators(migration: migration)
            }
        }
    }

    private static func addUuidsToCreators(migration: Migration) {
        migration.enumerateObjects(ofType: RCreator.className()) { _, newObject in
            newObject?["uuid"] = UUID().uuidString
        }
    }

    private static func extractItemHtmlFreeContent(migration: Migration) {
        migration.enumerateObjects(ofType: RItem.className()) { oldObject, newObject in
            guard let rawType = oldObject?["rawType"] as? String, let fields = oldObject?["fields"] as? List<MigrationObject> else { return }

            let content: String

            switch rawType {
            case ItemTypes.note:
                guard let _content = fields.first(where: { $0["key"] as? String == FieldKeys.Item.note })?["value"] as? String, !_content.isEmpty else { return }
                content = _content.strippedHtmlTags

            case ItemTypes.annotation:
                guard let _content = fields.first(where: { $0["key"] as? String == FieldKeys.Item.Annotation.comment })?["value"] as? String, !_content.isEmpty else { return }
                content = _content.strippedRichTextTags

            default:
                return
            }

            newObject?["htmlFreeContent"] = content
        }
    }

    private static func migrateObjectChange(migration: Migration) {
        let migrationBlock: MigrationObjectEnumerateBlock = { oldObject, newObject in
            if let oldValue = oldObject?["rawChangedFields"] as? Int16, oldValue > 0 {
                let objectData: [String: Any] = ["identifier": UUID().uuidString, "rawChanges": oldValue]
                newObject?.setValue([objectData], forKey: "changes")
            }
        }

        migration.enumerateObjects(ofType: RItem.className(), migrationBlock)
        migration.enumerateObjects(ofType: RCollection.className(), migrationBlock)
        migration.enumerateObjects(ofType: RSearch.className(), migrationBlock)
        migration.enumerateObjects(ofType: RPageIndex.className(), migrationBlock)
    }

    private static func migrateTagNames(migration: Migration) {
        migration.enumerateObjects(ofType: RTag.className()) { oldObject, newObject in
            if let name = oldObject?["name"] as? String, !name.isEmpty {
                newObject?["sortName"] = RTag.sortName(from: name)
                newObject?["order"] = 0
            }
        }
    }

    /// Realm results observer returns modifications from old array, so if there is a need to retrieve updated objects from updated `Results`
    /// we need to correct modifications array to include proper index after deletions/insertions are performed.
    static func correctedModifications(from modifications: [Int], insertions: [Int], deletions: [Int]) -> [Int] {
        guard !modifications.isEmpty && (!insertions.isEmpty || !deletions.isEmpty) else { return modifications }

        var correctedModifications = modifications

        /// `modifications` array contains indices from previous results state. So if there is a deletion and modifications at the same time,
        /// the modification index may end up being out of bounds.
        /// Example: there are 3 results, there is a deletion at index 0 and other objects are modified
        ///          deletions = [0], modifications = [1, 2] - 2 is out of bounds, so results[2] crashes
        deletions.forEach { deletion in
            if let deletionIdx = modifications.firstIndex(where: { $0 > deletion }) {
                for idx in deletionIdx..<modifications.count {
                    correctedModifications[idx] -= 1
                }
            }
        }

        /// Same as above, but with insertion. In this case it doesn't crash, but incorrect indices are taken.
        /// Example: there are 2 results, there is an insertion at index 0 and other objects are modified
        ///          insertions = [0], modifications = [0, 1] - index 0 is taken twice and index 2 is missing
        let modifications = correctedModifications
        insertions.forEach { insertion in
            if let insertionIdx = modifications.firstIndex(where: { $0 >= insertion }) {
                for idx in insertionIdx..<modifications.count {
                    correctedModifications[idx] += 1
                }
            }
        }

        return correctedModifications
    }
}
