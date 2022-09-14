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
    private static let schemaVersion: UInt64 = 35

    static func mainConfiguration(url: URL, fileStorage: FileStorage) -> Realm.Configuration {
        var config = Realm.Configuration(fileURL: url,
                                         schemaVersion: schemaVersion,
                                         migrationBlock: createMigrationBlock(fileStorage: fileStorage),
                                         deleteRealmIfMigrationNeeded: false)
        config.objectTypes = [RCollection.self, RCreator.self, RCustomLibrary.self, RGroup.self, RItem.self, RItemField.self, RLink.self, RPageIndex.self, RPath.self, RPathCoordinate.self, RRect.self,
                              RRelation.self, RSearch.self, RCondition.self, RTag.self, RTypedTag.self, RUser.self, RWebDavDeletion.self, RVersions.self]
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
}
