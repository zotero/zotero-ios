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
