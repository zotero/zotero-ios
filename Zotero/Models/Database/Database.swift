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
    private static let schemaVersion: UInt64 = 34

    static func mainConfiguration(url: URL, fileStorage: FileStorage) -> Realm.Configuration {
        let shouldDelete = shouldDeleteRealm(url: url)
        var config = Realm.Configuration(fileURL: url,
                                         schemaVersion: schemaVersion,
                                         migrationBlock: shouldDelete ? nil : createMigrationBlock(fileStorage: fileStorage),
                                         deleteRealmIfMigrationNeeded: shouldDelete)
        config.objectTypes = [RCollection.self, RCreator.self, RCustomLibrary.self, RGroup.self, RItem.self, RItemField.self, RLink.self, RPageIndex.self, RPath.self, RPathCoordinate.self, RRect.self,
                              RRelation.self, RSearch.self, RCondition.self, RTag.self, RTypedTag.self, RUser.self, RWebDavDeletion.self, RVersions.self]
        return config
    }

    static func bundledDataConfiguration(fileStorage: FileStorage) -> Realm.Configuration {
        let url = Files.bundledDataDbFile.createUrl()
        let shouldDelete = shouldDeleteRealm(url: url)
        var config = Realm.Configuration(fileURL: url,
                                         schemaVersion: schemaVersion,
                                         migrationBlock: shouldDelete ? nil : createMigrationBlock(fileStorage: fileStorage),
                                         deleteRealmIfMigrationNeeded: shouldDelete)
        config.objectTypes = [RTranslatorMetadata.self, RStyle.self]
        return config
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
        let migrateSyncState: (String, MigrationObject?, MigrationObject?) -> Void = { type, old, new in
            guard let rawState = old?.safeGet(key: "rawSyncState", in: migration.oldSchema[type]) as? Int else { return }
            new?.safeSet(key: "syncState", value: (ObjectSyncState(rawValue: rawState) ?? .synced), in: migration.newSchema[type])
        }

        let migrateCustomLibraryKey: (String, MigrationObject?, MigrationObject?) -> Void = { type, old, new in
            guard let rawKey = old?.safeGet(key: "customLibraryKey", in: migration.oldSchema[type]) as? Int else { return }
            new?.safeSet(key: "customLibraryKey", value: (RCustomLibraryType(rawValue: rawKey) ?? .myLibrary), in: migration.newSchema[type])
        }

        let migrateChangeType: (String, MigrationObject?, MigrationObject?) -> Void = { type, old, new in
            guard let rawKey = old?.safeGet(key: "rawChangeType", in: migration.oldSchema[type]) as? Int else { return }
            new?.safeSet(key: "changeType", value: (UpdatableChangeType(rawValue: rawKey) ?? .sync), in: migration.newSchema[type])
        }

        migration.enumerateObjects(ofType: RCustomLibrary.className()) { old, new in
            guard let rawType = old?.safeGet(key: "rawType", in: migration.oldSchema[RCustomLibrary.className()]) as? Int else { return }
            new?.safeSet(key: "type", value: (RCustomLibraryType(rawValue: rawType) ?? .myLibrary), in: migration.newSchema[RCustomLibrary.className()])
        }

        migration.enumerateObjects(ofType: RGroup.className()) { old, new in
            if let rawType = old?.safeGet(key: "rawType", in: migration.oldSchema[RGroup.className()]) as? String {
                new?.safeSet(key: "type", value: (GroupType(rawValue: rawType) ?? .private), in: migration.newSchema[RGroup.className()])
            }
            migrateSyncState(RGroup.className(), old, new)
        }

        migration.enumerateObjects(ofType: RCollection.className()) { old, new in
            migrateSyncState(RCollection.className(), old, new)
            migrateCustomLibraryKey(RCollection.className(), old, new)
            migrateChangeType(RCollection.className(), old, new)
        }

        migration.enumerateObjects(ofType: RItem.className()) { old, new in
            migrateSyncState(RItem.className(), old, new)
            migrateCustomLibraryKey(RItem.className(), old, new)
            migrateChangeType(RItem.className(), old, new)
        }

        migration.enumerateObjects(ofType: RSearch.className()) { old, new in
            migrateSyncState(RSearch.className(), old, new)
            migrateCustomLibraryKey(RSearch.className(), old, new)
            migrateChangeType(RSearch.className(), old, new)
        }

        migration.enumerateObjects(ofType: RPageIndex.className()) { old, new in
            migrateSyncState(RPageIndex.className(), old, new)
            migrateCustomLibraryKey(RPageIndex.className(), old, new)
            migrateChangeType(RPageIndex.className(), old, new)
        }

        migration.enumerateObjects(ofType: RTag.className()) { old, new in
            migrateCustomLibraryKey(RTag.className(), old, new)
        }

        migration.enumerateObjects(ofType: RTypedTag.className()) { old, new in
            guard let rawType = old?.safeGet(key: "rawType", in: migration.oldSchema[RTypedTag.className()]) as? Int else { return }
            new?.safeSet(key: "type", value: (RTypedTag.Kind(rawValue: rawType) ?? .manual), in: migration.newSchema[RTypedTag.className()])
        }
    }

    private struct KeyedLibraryId: Hashable {
        let key: String
        let customLibraryKey: Int?
        let groupKey: Int?

        init(key: String, groupKey: Any?) {
            self.key = key
            if let groupKey = groupKey as? Int {
                self.groupKey = groupKey
                self.customLibraryKey = nil
            } else {
                self.customLibraryKey = RCustomLibraryType.myLibrary.rawValue
                self.groupKey = nil
            }
        }
    }

    private struct RectMigration: Equatable, Hashable {
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double

        init(object: MigrationObject, isNewSchema: Bool, migration: Migration) {
            let schema = (isNewSchema ? migration.newSchema : migration.oldSchema)[RRect.className()]
            self.minX = (object.safeGet(key: "minX", in: schema) as? Double) ?? -1
            self.minY = (object.safeGet(key: "minY", in: schema) as? Double) ?? -1
            self.maxX = (object.safeGet(key: "maxX", in: schema) as? Double) ?? -1
            self.maxY = (object.safeGet(key: "maxY", in: schema) as? Double) ?? -1
        }
    }

    /// Migrate some Realm `Object`s to `EmbeddedObject`, which makes them directly dependent on their parent. Migration of `RCreator`, `RLink`, `RItemField`, `RCondition` and `RRelation` is simple,
    /// because they had links to their parents. Migration of `RVersion` and `RRect` is a bit more complicated, because these objects are not linked to their parent, only their parents have them
    /// stored in a list. So if some object is missing a link to their parent we'll get the message "At least one object does not have a backlink (data would get lost)". Since there is no identifier
    /// or attribute which can identify these objects, we compare based on their values and delete the ones that are not found in parent objects.
    private static func migrateEmbeddedObjects(migration: Migration) {
        DDLogInfo("Migrate embedded objects")
        // Just delete these, they shouldn't be in use yet
        migration.deleteData(forType: RPath.className())
        migration.deleteData(forType: RPathCoordinate.className())

        self.migrateVersions(migration: migration)
        self.migrateLinkedChildren(ofType: RItemField.className(), parentType: RItem.className(), oldLinkPropertyName: "item", newListPropertyName: "fields", migration: migration)
        self.migrateLinkedChildren(ofType: RCreator.className(), parentType: RItem.className(), oldLinkPropertyName: "item", newListPropertyName: "creators", migration: migration)
        self.migrateLinkedChildren(ofType: RLink.className(), parentType: RItem.className(), oldLinkPropertyName: "item", newListPropertyName: "links", migration: migration)
        self.migrateLinkedChildren(ofType: RRelation.className(), parentType: RItem.className(), oldLinkPropertyName: "item", newListPropertyName: "relations", migration: migration)
        self.migrateLinkedChildren(ofType: RCondition.className(), parentType: RSearch.className(), oldLinkPropertyName: "search", newListPropertyName: "conditions", migration: migration)
        self.migrateRects(migration: migration)
    }

    private static func migrateRects(migration: Migration) {
        var (groupedNewRects, allCount, availableCount) = self.groupedRects(migration: migration)

        var migratedCount = 0
        migration.enumerateObjects(ofType: RItem.className()) { old, new in
            guard let old = old, let new = new else { return }

            var rectObjects: [MigrationObject] = []

            if let list = old.safeDynamicList(key: "rects", in: migration.oldSchema[RItem.className()]) {
                for oldRectObject in list {
                    let rect = RectMigration(object: oldRectObject, isNewSchema: false, migration: migration)
                    if var objects = groupedNewRects[rect], !objects.isEmpty {
                        rectObjects.append(objects.removeFirst())

                        if objects.isEmpty {
                            groupedNewRects[rect] = nil
                        } else {
                            groupedNewRects[rect] = objects
                        }
                    }
                }
            } else {
                DDLogError("RItem missing rects")
            }

            new.safeDynamicList(key: "rects", in: migration.newSchema[RItem.className()])?.removeAll()
            if !rectObjects.isEmpty {
                migratedCount += rectObjects.count
                new.safeDynamicList(key: "rects", in: migration.newSchema[RItem.className()])?.append(objectsIn: rectObjects)
            }
        }

        var deletions = 0
        for object in groupedNewRects.values.flatMap({ $0 }) {
            deletions += 1
            migration.delete(object)
        }

        if allCount != availableCount || (migratedCount + deletions) != availableCount {
            DDLogError("Rects migration: all: \(allCount), \(availableCount); migrated: \(migratedCount); deletions: \(deletions)")
        } else {
            DDLogInfo("Rects migration: all: \(allCount); migrated: \(migratedCount); deletions: \(deletions)")
        }
    }

    private static func groupedRects(migration: Migration) -> ([RectMigration: [MigrationObject]], Int, Int) {
        var map: [RectMigration: [MigrationObject]] = [:]
        var allCount = 0
        var availableCount = 0
        migration.enumerateObjects(ofType: RRect.className()) { old, new in
            allCount += 1
            guard let new = new else { return }
            availableCount += 1

            let rect = RectMigration(object: new, isNewSchema: true, migration: migration)
            if var existing = map[rect] {
                existing.append(new)
                map[rect] = existing
            } else {
                map[rect] = [new]
            }
        }
        return (map, allCount, availableCount)
    }

    private struct VersionsMigration {
        let versions: Versions
        let object: MigrationObject

        init(object: MigrationObject, isNewSchema: Bool, migration: Migration) {
            self.object = object

            let schema = (isNewSchema ? migration.newSchema : migration.oldSchema)[RVersions.className()]
            self.versions = Versions(collections: (object.safeGet(key: "collections", in: schema) as? Int) ?? -1,
                                     items: (object.safeGet(key: "items", in: schema) as? Int) ?? -1,
                                     trash: (object.safeGet(key: "trash", in: schema) as? Int) ?? -1,
                                     searches: (object.safeGet(key: "searches", in: schema) as? Int) ?? -1,
                                     deletions: (object.safeGet(key: "deletions", in: schema) as? Int) ?? -1,
                                     settings: (object.safeGet(key: "settings", in: schema) as? Int) ?? -1)
        }
    }

    private static func migrateVersions(migration: Migration) {
        var versionsMigrations: [VersionsMigration] = []

        var allCount = 0
        var availableCount = 0
        migration.enumerateObjects(ofType: RVersions.className()) { old, new in
            allCount += 1
            guard let new = new else { return }
            availableCount += 1
            versionsMigrations.append(VersionsMigration(object: new, isNewSchema: true, migration: migration))
        }

        var allMigrated = 0
        var availableMigrated = 0
        let migrateVersions: (String, MigrationObject?) -> Void = { type, new in
            allMigrated += 1
            guard let new = new else { return }
            guard let versionsObject = new.safeGet(key: "versions", in: migration.newSchema[type]) as? MigrationObject else {
                DDLogError("\(type) missing versions")
                return
            }
            availableMigrated += 1

            let versions = VersionsMigration(object: versionsObject, isNewSchema: true, migration: migration).versions

            if let index = versionsMigrations.firstIndex(where: { $0.versions == versions }) {
                new.safeSet(key: "versions", value: versionsMigrations[index].object, in: migration.newSchema[type])
                versionsMigrations.remove(at: index)
            }
        }

        migration.enumerateObjects(ofType: RGroup.className()) { old, new in
            migrateVersions(RGroup.className(), new)
        }

        migration.enumerateObjects(ofType: RCustomLibrary.className()) { old, new in
            migrateVersions(RCustomLibrary.className(), new)
        }

        var deletions = 0
        for versionsMigration in versionsMigrations {
            deletions += 1
            migration.delete(versionsMigration.object)
        }

        if allCount != availableCount || allMigrated != availableMigrated || (availableMigrated + deletions) != availableCount {
            DDLogError("Versions migration: all: \(allCount), \(availableCount); migrated: \(allMigrated), \(availableMigrated); deleted: \(deletions)")
        } else {
            DDLogInfo("Versions migration: all: \(availableCount); migrated: \(availableMigrated); deleted: \(deletions)")
        }
    }

    private static func migrateLinkedChildren(ofType type: String, parentType: String, oldLinkPropertyName: String, newListPropertyName: String, migration: Migration) {
        var grouped: [KeyedLibraryId: [MigrationObject]] = [:]
        var orphaned: [MigrationObject] = []

        var allCount = 0
        var availableCount = 0
        migration.enumerateObjects(ofType: type) { old, new in
            allCount += 1
            guard let new = new else { return }
            availableCount += 1

            guard let parent = old?.safeGet(key: oldLinkPropertyName, in: migration.oldSchema[type]) as? MigrationObject, let key = parent.safeGet(key: "key", in: migration.oldSchema[parentType]) as? String else {
                orphaned.append(new)
                return
            }

            let id = KeyedLibraryId(key: key, groupKey: parent.safeGet(key: "groupKey", in: migration.oldSchema[parentType]))

            if var objects = grouped[id] {
                objects.append(new)
                grouped[id] = objects
            } else {
                grouped[id] = [new]
            }
        }

        var migrated = 0
        migration.enumerateObjects(ofType: parentType) { old, new in
            guard let key = new?.safeGet(key: "key", in: migration.newSchema[parentType]) as? String else {
                DDLogError("\(parentType) missing key")
                return
            }

            let id = KeyedLibraryId(key: key, groupKey: old?.safeGet(key: "groupKey", in: migration.oldSchema[parentType]))

            guard let objects = grouped[id] else { return }

            grouped[id] = nil

            if let list = new?.safeDynamicList(key: newListPropertyName, in: migration.newSchema[parentType]) {
                migrated += objects.count
                list.append(objectsIn: objects)
            }
        }

        var deleted = 0
        for object in orphaned {
            deleted += 1
            migration.delete(object)
        }

        if allCount != availableCount || (migrated + deleted) != availableCount {
            DDLogError("\(type) migration: all: \(allCount), \(availableCount); migrated: \(migrated); deleted: \(deleted)")
        } else {
            DDLogInfo("\(type) migration: all: \(allCount); migrated: \(migrated); deleted: \(deleted)")
        }
    }

    private static func migrateCollapsibleCollections(migration: Migration) {
        migration.enumerateObjects(ofType: RCollection.className()) { old, new in
            if let new = new {
                new.safeSet(key: "collapsed", value: true, in: migration.newSchema[RCollection.className()])
            }
        }
    }

    private static func migrateCollectionParentKeys(migration: Migration) {
        migration.enumerateObjects(ofType: RCollection.className()) { old, new in
            let parent = old?.safeGet(key: "parent", in: migration.oldSchema[RCollection.className()]) as? MigrationObject
            let key = parent?.safeGet(key: "key", in: migration.oldSchema[RCollection.className()]) as? String
            new?.safeSet(key: "parentKey", value: key, in: migration.newSchema[RCollection.className()])
        }
    }

    private static func migrateMainAttachmentDownloaded(migration: Migration, fileStorage: FileStorage) {
        let attachmentMap = self.createAttachmentFileMap(fileStorage: fileStorage)
        migration.enumerateObjects(ofType: RItem.className(), { old, new in
            if let rawType = old?.safeGet(key: "rawType", in: migration.oldSchema[RItem.className()]) as? String, rawType == ItemTypes.attachment,
               let key = old?.safeGet(key: "key", in: migration.oldSchema[RItem.className()]) as? String {
                let libraryId: LibraryIdentifier
                if let groupId = old?.safeGet(key: "groupKey", in: migration.oldSchema[RItem.className()]) as? Int {
                    libraryId = .group(groupId)
                } else {
                    libraryId = .custom(.myLibrary)
                }
                new?.safeSet(key: "fileDownloaded", value: (attachmentMap[libraryId]?.contains(key) == true), in: migration.newSchema[RItem.className()])
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
        guard let downloadContents = (try? fileStorage.contentsOfDirectory(at: Files.downloads))?.filter({ $0.name.isEmpty && $0.mimeType.isEmpty }) else { return [:] }

        let libraryIdsAndFiles = downloadContents.compactMap({ file in file.relativeComponents.last?.libraryIdFromFolderName.flatMap({ ($0, file) }) })

        var attachmentMap: [LibraryIdentifier: Set<String>] = [:]
        for (libraryId, file) in libraryIdsAndFiles {
            guard let files: [File] = try? fileStorage.contentsOfDirectory(at: file) else { continue }
            var keys: Set<String> = []
            for file in files {
                guard !file.name.isEmpty else { continue }
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

extension DynamicObject {
    fileprivate func safeGet(key: String, in schema: ObjectSchema?) -> Any? {
        guard let schema = schema else {
            DDLogError("Database: trying to get '\(key)' but missing schema.")
            return nil
        }
        guard schema.properties.contains(where: { $0.name == key }) else {
            DDLogError("Database: trying to get '\(key)' but it's not in schema.")
            return nil
        }
        return self[key]
    }

    fileprivate func safeSet(key: String, value: Any?, in schema: ObjectSchema?) {
        guard let schema = schema else {
            DDLogError("Database: trying to get list '\(key)' but missing schema.")
            return
        }
        guard let property = schema.properties.first(where: { $0.name == key }) else {
            DDLogError("Database: trying to get list '\(key)' but it's not in schema.")
            return
        }
        guard value != nil || property.isOptional else {
            DDLogError("Database: trying to set nil to property \(property.name) which is not optional.")
            return
        }
        self[key] = value
    }

    fileprivate func safeDynamicList(key: String, in schema: ObjectSchema?) -> List<DynamicObject>? {
        guard let schema = schema else {
            DDLogError("Database: trying to set '\(key)' but missing schema.")
            return nil
        }
        guard schema.properties.contains(where: { $0.name == key }) else {
            DDLogError("Database: trying to set '\(key)' but it's not in schema.")
            return nil
        }
        return self.dynamicList(key)
    }
}
