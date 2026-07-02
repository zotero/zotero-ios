//
//  DeletableObjectSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 19/5/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick
import RealmSwift

final class DeletableObjectSpec: QuickSpec {
    override class func spec() {
        describe("a deletable object") {
            let libraryId: LibraryIdentifier = .custom(.myLibrary)
            var realm: Realm!

            beforeEach {
                let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
                realm = try! Realm(configuration: config)

                try! realm.write {
                    let library = RCustomLibrary()
                    library.type = .myLibrary
                    realm.add(library)
                }
            }

            func createUser(identifier: Int) -> RUser {
                let user = RUser()
                user.identifier = identifier
                user.name = "User \(identifier)"
                user.username = "user\(identifier)"
                return user
            }

            func createItem(key: String, rawType: String = "journalArticle", parent: RItem? = nil, user: RUser? = nil) -> RItem {
                let item = RItem()
                item.key = key
                item.rawType = rawType
                item.customLibraryKey = .myLibrary
                item.parent = parent
                item.createdBy = user
                item.lastModifiedBy = user
                return item
            }

            it("deletes users orphaned by remote item tree deletions") {
                let userId = 1
                let parentKey = "PARENT01"
                let childKey = "CHILD001"

                try! realm.write {
                    let user = createUser(identifier: userId)
                    let parent = createItem(key: parentKey, user: user)
                    let child = createItem(key: childKey, rawType: ItemTypes.note, parent: parent, user: user)

                    realm.add(user)
                    realm.add(parent)
                    realm.add(child)
                }

                try! realm.write {
                    let request = PerformItemDeletionsDbRequest(libraryId: libraryId, keys: [parentKey], conflictMode: .deleteConflicts)
                    _ = try! request.process(in: realm)
                }

                expect(realm.objects(RItem.self).filter(.key(parentKey, in: libraryId)).first).to(beNil())
                expect(realm.objects(RItem.self).filter(.key(childKey, in: libraryId)).first).to(beNil())
                expect(realm.object(ofType: RUser.self, forPrimaryKey: userId)).to(beNil())
            }

            it("keeps users still referenced after remote item tree deletions") {
                let userId = 1
                let parentKey = "PARENT01"
                let childKey = "CHILD001"
                let remainingKey = "REMAIN01"

                try! realm.write {
                    let user = createUser(identifier: userId)
                    let parent = createItem(key: parentKey, user: user)
                    let child = createItem(key: childKey, rawType: ItemTypes.note, parent: parent, user: user)
                    let remaining = createItem(key: remainingKey, user: user)

                    realm.add(user)
                    realm.add(parent)
                    realm.add(child)
                    realm.add(remaining)
                }

                try! realm.write {
                    let request = PerformItemDeletionsDbRequest(libraryId: libraryId, keys: [parentKey], conflictMode: .deleteConflicts)
                    _ = try! request.process(in: realm)
                }

                expect(realm.objects(RItem.self).filter(.key(parentKey, in: libraryId)).first).to(beNil())
                expect(realm.objects(RItem.self).filter(.key(childKey, in: libraryId)).first).to(beNil())
                expect(realm.objects(RItem.self).filter(.key(remainingKey, in: libraryId)).first).toNot(beNil())
                expect(realm.object(ofType: RUser.self, forPrimaryKey: userId)).toNot(beNil())
            }

            it("deletes remotely deleted items with only local last read changes without conflicts") {
                let itemKey = "ITEM0001"

                try! realm.write {
                    let item = createItem(key: itemKey)
                    item.lastRead = Date()
                    item.changes.append(RObjectChange.create(changes: RItemChanges.lastRead))
                    realm.add(item)
                }

                var conflicts: [(String, String)] = []
                try! realm.write {
                    let request = PerformItemDeletionsDbRequest(libraryId: libraryId, keys: [itemKey], conflictMode: .resolveConflicts)
                    conflicts = try! request.process(in: realm)
                }

                expect(conflicts).to(beEmpty())
                expect(realm.objects(RItem.self).filter(.key(itemKey, in: libraryId)).first).to(beNil())
            }

            it("deletes remotely deleted item trees with only child last read changes without conflicts") {
                let parentKey = "PARENT01"
                let childKey = "CHILD001"

                try! realm.write {
                    let parent = createItem(key: parentKey)
                    let child = createItem(key: childKey, rawType: ItemTypes.attachment, parent: parent)
                    child.lastRead = Date()
                    child.changes.append(RObjectChange.create(changes: RItemChanges.lastRead))

                    realm.add(parent)
                    realm.add(child)
                }

                var conflicts: [(String, String)] = []
                try! realm.write {
                    let request = PerformItemDeletionsDbRequest(libraryId: libraryId, keys: [parentKey], conflictMode: .resolveConflicts)
                    conflicts = try! request.process(in: realm)
                }

                expect(conflicts).to(beEmpty())
                expect(realm.objects(RItem.self).filter(.key(parentKey, in: libraryId)).first).to(beNil())
                expect(realm.objects(RItem.self).filter(.key(childKey, in: libraryId)).first).to(beNil())
            }

            it("keeps remotely deleted items with local changes other than last read as conflicts") {
                let itemKey = "ITEM0001"

                try! realm.write {
                    let item = createItem(key: itemKey)
                    item.displayTitle = "Changed Item"
                    item.lastRead = Date()
                    item.changes.append(RObjectChange.create(changes: RItemChanges.lastRead))
                    item.changes.append(RObjectChange.create(changes: RItemChanges.fields))
                    realm.add(item)
                }

                var conflicts: [(String, String)] = []
                try! realm.write {
                    let request = PerformItemDeletionsDbRequest(libraryId: libraryId, keys: [itemKey], conflictMode: .resolveConflicts)
                    conflicts = try! request.process(in: realm)
                }

                expect(conflicts.count).to(equal(1))
                expect(conflicts.first?.0).to(equal(itemKey))
                expect(conflicts.first?.1).to(equal("Changed Item"))
                expect(realm.objects(RItem.self).filter(.key(itemKey, in: libraryId)).first).toNot(beNil())
            }

            it("clears only last read changes from remotely missing item updates") {
                let lastReadKey = "LASTREAD"
                let emptyKey = "EMPTY001"
                let fieldKey = "FIELD001"
                let mixedKey = "MIXED001"

                try! realm.write {
                    let lastReadItem = createItem(key: lastReadKey)
                    lastReadItem.lastRead = Date()
                    lastReadItem.changes.append(RObjectChange.create(changes: RItemChanges.lastRead))

                    let emptyItem = createItem(key: emptyKey)
                    emptyItem.changes.append(RObjectChange.create(changes: RItemChanges()))

                    let fieldItem = createItem(key: fieldKey)
                    fieldItem.changes.append(RObjectChange.create(changes: RItemChanges.fields))

                    let mixedItem = createItem(key: mixedKey)
                    mixedItem.lastRead = Date()
                    mixedItem.changes.append(RObjectChange.create(changes: RItemChanges.lastRead))
                    mixedItem.changes.append(RObjectChange.create(changes: RItemChanges.fields))

                    realm.add(lastReadItem)
                    realm.add(emptyItem)
                    realm.add(fieldItem)
                    realm.add(mixedItem)
                }

                var clearedKeys: Set<String> = []
                try! realm.write {
                    let request = ClearLastReadOnlyItemChangesDbRequest(libraryId: libraryId, keys: [lastReadKey, emptyKey, fieldKey, mixedKey])
                    clearedKeys = try! request.process(in: realm)
                }

                expect(clearedKeys).to(equal([lastReadKey]))
                expect(realm.objects(RItem.self).filter(.key(lastReadKey, in: libraryId)).first?.changes).to(beEmpty())
                expect(realm.objects(RItem.self).filter(.key(emptyKey, in: libraryId)).first?.changes.count).to(equal(1))
                expect(realm.objects(RItem.self).filter(.key(emptyKey, in: libraryId)).first?.changedFields).to(equal(RItemChanges()))
                expect(realm.objects(RItem.self).filter(.key(fieldKey, in: libraryId)).first?.changedFields).to(equal(.fields))
                expect(realm.objects(RItem.self).filter(.key(mixedKey, in: libraryId)).first?.changedFields).to(equal([.fields, .lastRead]))
            }

            it("deletes orphaned users through generic item deletions") {
                let userId = 1
                let itemKey = "ITEM0001"

                try! realm.write {
                    let user = createUser(identifier: userId)
                    let item = createItem(key: itemKey, user: user)

                    realm.add(user)
                    realm.add(item)
                }

                try! realm.write {
                    try! DeleteObjectsDbRequest<RItem>(keys: [itemKey], libraryId: libraryId).process(in: realm)
                }

                expect(realm.objects(RItem.self).filter(.key(itemKey, in: libraryId)).first).to(beNil())
                expect(realm.object(ofType: RUser.self, forPrimaryKey: userId)).to(beNil())
            }
        }
    }
}
