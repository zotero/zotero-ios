//
//  Database.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

struct Database {
    private static let schemaVersion: UInt64 = 33

    static func mainConfiguration(url: URL, fileStorage: FileStorage) -> Realm.Configuration {
        let shouldDelete = shouldDeleteRealm(url: url)
        return Realm.Configuration(fileURL: url,
                                   schemaVersion: schemaVersion,
                                   migrationBlock: shouldDelete ? nil : createMigrationBlock(fileStorage: fileStorage),
                                   deleteRealmIfMigrationNeeded: shouldDelete)
    }

    static func bundledDataConfiguration(fileStorage: FileStorage) -> Realm.Configuration {
        let url = Files.bundledDataDbFile.createUrl()
        let shouldDelete = shouldDeleteRealm(url: url)
        return Realm.Configuration(fileURL: url,
                                   schemaVersion: schemaVersion,
                                   migrationBlock: shouldDelete ? nil : createMigrationBlock(fileStorage: fileStorage),
                                   deleteRealmIfMigrationNeeded: shouldDelete)
    }

    private static func shouldDeleteRealm(url: URL) -> Bool {
        let existingSchemaVersion = (try? schemaVersionAtURL(url)) ?? 0
        // 20 is the first beta preview build, we'll wipe DB for pre-beta users to get away without DB migration
        return existingSchemaVersion < 20
    }

    private static func createMigrationBlock(fileStorage: FileStorage) -> MigrationBlock {
        return { migration, schemaVersion in
            if schemaVersion < 21 {
                Database.migrateCollapsibleCollections(migration: migration)
            }
            if schemaVersion < 22 {
                Database.migrateCollectionParentKeys(migration: migration)
            }
            if schemaVersion < 24 {
                Database.migrateMainAttachmentDownloaded(migration: migration, fileStorage: fileStorage)
            }
            if schemaVersion < 32 {
                Database.migrateEmbeddedObjects(migration: migration)
            }
            if schemaVersion < 33 {
                Database.migrateRawValuesToEnums(migration: migration)
            }
        }
    }

    private static func migrateRawValuesToEnums(migration: Migration) {
        let migrateSyncState: (MigrationObject?, MigrationObject?) -> Void = { old, new in
            guard let rawState = old?["rawSyncState"] as? Int else { return }
            new?["syncState"] = ObjectSyncState(rawValue: rawState) ?? .synced
        }

        let migrateCustomLibraryKey: (MigrationObject?, MigrationObject?) -> Void = { old, new in
            guard let rawKey = old?["customLibraryKey"] as? Int else { return }
            new?["customLibraryKey"] = RCustomLibraryType(rawValue: rawKey) ?? .myLibrary
        }

        let migrateChangeType: (MigrationObject?, MigrationObject?) -> Void = { old, new in
            guard let rawKey = old?["rawChangeType"] as? Int else { return }
            new?["changeType"] = UpdatableChangeType(rawValue: rawKey) ?? .sync
        }

        migration.enumerateObjects(ofType: "RCustomLibrary") { old, new in
            guard let rawType = old?["rawType"] as? Int else { return }
            new?["type"] = RCustomLibraryType(rawValue: rawType) ?? .myLibrary
        }

        migration.enumerateObjects(ofType: "RGroup") { old, new in
            if let rawType = old?["rawType"] as? String {
                new?["type"] = GroupType(rawValue: rawType) ?? .private
            }
            migrateSyncState(old, new)
        }

        migration.enumerateObjects(ofType: "RCollection") { old, new in
            migrateSyncState(old, new)
            migrateCustomLibraryKey(old, new)
            migrateChangeType(old, new)
        }

        migration.enumerateObjects(ofType: "RItem") { old, new in
            migrateSyncState(old, new)
            migrateCustomLibraryKey(old, new)
            migrateChangeType(old, new)
        }

        migration.enumerateObjects(ofType: "RSearch") { old, new in
            migrateSyncState(old, new)
            migrateCustomLibraryKey(old, new)
            migrateChangeType(old, new)
        }

        migration.enumerateObjects(ofType: "RPageIndex") { old, new in
            migrateSyncState(old, new)
            migrateCustomLibraryKey(old, new)
            migrateChangeType(old, new)
        }

        migration.enumerateObjects(ofType: "RTag") { old, new in
            migrateCustomLibraryKey(old, new)
        }

        migration.enumerateObjects(ofType: "RTypedTag") { old, new in
            guard let rawType = old?["rawType"] as? Int else { return }
            new?["type"] = RTypedTag.Kind(rawValue: rawType) ?? .manual
        }
    }

    private struct KeyedLibraryId: Hashable {
        let key: String
        let customLibraryKey: Int?
        let groupKey: Int?
    }

    private struct VersionsMigration {
        let versions: Versions
        let object: MigrationObject

        init(object: MigrationObject) {
            self.object = object
            self.versions = Versions(collections: (object["collections"] as? Int) ?? -1, items: (object["items"] as? Int) ?? -1, trash: (object["trash"] as? Int) ?? -1,
                                     searches: (object["searches"] as? Int) ?? -1, deletions: (object["deletions"] as? Int) ?? -1, settings: (object["settings"] as? Int) ?? -1)
        }
    }

    private static func migrateEmbeddedObjects(migration: Migration) {
        var orphaned: [MigrationObject] = []
        let creators = self.groupedEmbeddedObjects(ofType: "RCreator", parentPropertyName: "item", orphaned: &orphaned, migration: migration)
        let links = self.groupedEmbeddedObjects(ofType: "RLink", parentPropertyName: "item", orphaned: &orphaned, migration: migration)
        let fields = self.groupedEmbeddedObjects(ofType: "RItemField", parentPropertyName: "item", orphaned: &orphaned, migration: migration)
        let relations = self.groupedEmbeddedObjects(ofType: "RRelation", parentPropertyName: "item", orphaned: &orphaned, migration: migration)

        let setObjectsToList: ([MigrationObject]?, Any?) -> Void = { objects, list in
            if let objects = objects, let list = list as? List<MigrationObject> {
                list.append(objectsIn: objects)
            }
        }

        migration.enumerateObjects(ofType: "RItem") { old, new in
            guard let old = old, let key = old["key"] as? String else { return }

            let id = KeyedLibraryId(key: key, customLibraryKey: (old["customLibraryKey"] as? Int), groupKey: (old["groupKey"] as? Int))

            setObjectsToList(creators[id], new?["creators"])
            setObjectsToList(links[id], new?["links"])
            setObjectsToList(fields[id], new?["fields"])
            setObjectsToList(relations[id], new?["relations"])
        }

        let conditions = self.groupedEmbeddedObjects(ofType: "RCondition", parentPropertyName: "search", orphaned: &orphaned, migration: migration)

        migration.enumerateObjects(ofType: "RSearch") { old, new in
            guard let old = old, let key = old["key"] as? String else { return }

            let id = KeyedLibraryId(key: key, customLibraryKey: (old["customLibraryKey"] as? Int), groupKey: (old["groupKey"] as? Int))
            setObjectsToList(conditions[id], new?["conditions"])
        }

        var versionsMigrations: [VersionsMigration] = []

        migration.enumerateObjects(ofType: "RVersions") { old, new in
            guard let new = new else { return }
            versionsMigrations.append(VersionsMigration(object: new))
        }

        let migrateVersions: (MigrationObject?) -> Void = { new in
            guard let new = new, let versionsObject = new["versions"] as? MigrationObject else { return }
            let versions = VersionsMigration(object: versionsObject).versions

            if let index = versionsMigrations.firstIndex(where: { $0.versions == versions }) {
                new["versions"] = versionsMigrations[index].object
                versionsMigrations.remove(at: index)
            }
        }

        migration.enumerateObjects(ofType: "RGroup") { old, new in
            migrateVersions(new)
        }

        migration.enumerateObjects(ofType: "RCustomLibrary") { old, new in
            migrateVersions(new)
        }

        for migration in versionsMigrations {
            orphaned.append(migration.object)
        }

        for object in orphaned {
            migration.delete(object)
        }
    }

    private static func groupedEmbeddedObjects(ofType type: String, parentPropertyName: String, orphaned: inout [MigrationObject], migration: Migration) -> [KeyedLibraryId: [MigrationObject]] {
        var objects: [KeyedLibraryId: [MigrationObject]] = [:]

        migration.enumerateObjects(ofType: type) { old, new in
            guard let old = old, let new = new else { return }

            guard let parent = old[parentPropertyName] as? MigrationObject else {
                orphaned.append(new)
                return
            }

            guard let key = parent["key"] as? String else { return }

            let itemId = KeyedLibraryId(key: key, customLibraryKey: (parent["customLibraryKey"] as? Int), groupKey: (parent["groupKey"] as? Int))

            if var itemObjects = objects[itemId] {
                itemObjects.append(new)
                objects[itemId] = itemObjects
            } else {
                objects[itemId] = [new]
            }
        }

        return objects
    }

    private static func migrateCollapsibleCollections(migration: Migration) {
        migration.enumerateObjects(ofType: "RCollection") { old, new in
            if let new = new {
                new["collapsed"] = true
            }
        }
    }

    private static func migrateCollectionParentKeys(migration: Migration) {
        migration.enumerateObjects(ofType: "RCollection") { old, new in
            let parentKey = old?.value(forKeyPath: "parent.key") as? String
            new?["parentKey"] = parentKey
        }
    }

    private static func migrateMainAttachmentDownloaded(migration: Migration, fileStorage: FileStorage) {
        let attachmentMap = self.createAttachmentFileMap(fileStorage: fileStorage)
        migration.enumerateObjects(ofType: "RItem", { old, new in
            if let rawType = old?.value(forKey: "rawType") as? String, rawType == ItemTypes.attachment,
               let key = old?.value(forKey: "key") as? String {
                let libraryId: LibraryIdentifier
                if let groupId = old?.value(forKey: "groupKey") as? Int {
                    libraryId = .group(groupId)
                } else {
                    libraryId = .custom(.myLibrary)
                }
                new?["fileDownloaded"] = attachmentMap[libraryId]?.contains(key) == true
            }
        })
    }

    /// Realm results observer returns modifications from old array, so if there is a need to retrieve updated objects from updated `Results`
    /// we need to correct modifications array to include proper index after deletions/insertions are performed.
    static func correctedModifications(from modifications: [Int], insertions: [Int], deletions: [Int]) -> [Int] {
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
        /// Example: there are 2 results, there is an insertion at index 0 and ther objects are modified
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

    /// Creates map of attachment keys from each library which are stored locally.
    private static func createAttachmentFileMap(fileStorage: FileStorage) -> [LibraryIdentifier: Set<String>] {
        guard let downloadContents = (try? fileStorage.contentsOfDirectory(at: Files.downloads))?.filter({ $0.isDirectory }) else { return [:] }

        let libraryIdsAndFiles = downloadContents.compactMap({ file in file.relativeComponents.last?.libraryIdFromFolderName.flatMap({ ($0, file) }) })

        var attachmentMap: [LibraryIdentifier: Set<String>] = [:]
        for (libraryId, file) in libraryIdsAndFiles {
            guard let files: [File] = try? fileStorage.contentsOfDirectory(at: file) else { continue }
            var keys: Set<String> = []
            for file in files {
                guard !file.isDirectory else { continue }
                keys.insert(file.name)
            }
            attachmentMap[libraryId] = keys
        }
        return attachmentMap
    }
}

extension String {
    fileprivate var libraryIdFromFolderName: LibraryIdentifier? {
        if self == "custom_my_library" {
            return .custom(.myLibrary)
        }

        guard self.count > 6,
              self[self.startIndex..<self.index(self.startIndex, offsetBy: 5)] == "group",
              let groupId = Int(self[self.index(self.startIndex, offsetBy: 6)..<self.endIndex]) else { return nil }
        return .group(groupId)
    }
}
