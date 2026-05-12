//
//  DefaultAnnotationPageLabelSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 29/4/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import Nimble
import Quick
import RealmSwift

final class DefaultAnnotationPageLabelSpec: QuickSpec {
    override class func spec() {
        describe("a default annotation page label computation") {
            let attachmentKey = "AAAAAAAA"
            let libraryId: LibraryIdentifier = .custom(.myLibrary)
            var realm: Realm!
            var dbStorage: DbStorage!

            beforeEach {
                let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
                realm = try! Realm(configuration: config)
                dbStorage = RealmDbStorage(config: config)

                try! realm.write {
                    realm.add(createAttachment(key: attachmentKey))
                }
            }

            it("computes a default page label when there are no annotations") {
                let result = computeDefaultAnnotationPageLabel()
                expect(result).to(equal(.commonPageOffset(offset: 1)))
                expect(result.label(for: 0)).to(equal("1"))
                expect(result.label(for: 1)).to(equal("2"))
                expect(result.label(for: 10)).to(equal("11"))
            }

            it("computes a common page offset") {
                try! realm.write {
                    let attachment = realm.objects(RItem.self).filter(.key(attachmentKey)).first!
                    realm.add(createAnnotation(key: "BBBBBBBB", parent: attachment, page: 0, pageLabel: "5"))
                    realm.add(createAnnotation(key: "CCCCCCCC", parent: attachment, page: 1, pageLabel: "6"))
                    realm.add(createAnnotation(key: "DDDDDDDD", parent: attachment, page: 2, pageLabel: "7"))
                }

                let result = computeDefaultAnnotationPageLabel()
                expect(result).to(equal(.commonPageOffset(offset: 5)))
                expect(result.label(for: 0)).to(equal("5"))
                expect(result.label(for: 1)).to(equal("6"))
                expect(result.label(for: 2)).to(equal("7"))
                expect(result.label(for: 10)).to(equal("15"))
            }

            it("computes a label by page") {
                try! realm.write {
                    let attachment = realm.objects(RItem.self).filter(.key(attachmentKey)).first!
                    realm.add(createAnnotation(key: "BBBBBBBB", parent: attachment, page: 0, pageLabel: "ii"))
                    realm.add(createAnnotation(key: "CCCCCCCC", parent: attachment, page: 0, pageLabel: "i"))
                    realm.add(createAnnotation(key: "DDDDDDDD", parent: attachment, page: 1, pageLabel: "2"))
                }

                let result = computeDefaultAnnotationPageLabel()
                expect(result).to(equal(.labelPerPage(labelsByPage: [0: "i", 1: "2"])))
                expect(result.label(for: 0)).to(equal("i"))
                expect(result.label(for: 1)).to(equal("2"))
                expect(result.label(for: 2)).to(equal("3"))
            }

            it("ignores dirty, deleted, unsupported, empty, and dash page labels") {
                try! realm.write {
                    let attachment = realm.objects(RItem.self).filter(.key(attachmentKey)).first!
                    realm.add(createAnnotation(key: "BBBBBBBB", parent: attachment, page: 0, pageLabel: "1"))
                    realm.add(createAnnotation(key: "CCCCCCCC", parent: attachment, page: 1, pageLabel: "2"))
                    realm.add(createAnnotation(key: "DDDDDDDD", parent: attachment, page: 2, pageLabel: "99", deleted: true))
                    realm.add(createAnnotation(key: "EEEEEEEE", parent: attachment, page: 2, pageLabel: "99", syncState: .dirty))
                    realm.add(createAnnotation(key: "FFFFFFFF", parent: attachment, page: 2, pageLabel: "99", annotationType: "unsupported"))
                    realm.add(createAnnotation(key: "GGGGGGGG", parent: attachment, page: 2, pageLabel: ""))
                    realm.add(createAnnotation(key: "HHHHHHHH", parent: attachment, page: 2, pageLabel: "-"))
                }

                let result = computeDefaultAnnotationPageLabel()
                expect(result).to(equal(.commonPageOffset(offset: 1)))
                expect(result.label(for: 0)).to(equal("1"))
                expect(result.label(for: 1)).to(equal("2"))
                expect(result.label(for: 2)).to(equal("3"))
            }

            func computeDefaultAnnotationPageLabel() -> DefaultAnnotationPageLabel {
                return DefaultAnnotationPageLabel.read(
                    attachmentKey: attachmentKey,
                    libraryId: libraryId,
                    dbStorage: dbStorage,
                    queue: .main
                )
            }

            func createAttachment(key: String) -> RItem {
                let item = RItem()
                item.key = key
                item.rawType = ItemTypes.attachment
                item.customLibraryKey = .myLibrary
                item.deleted = false
                item.syncState = .synced
                return item
            }

            func createAnnotation(
                key: String,
                parent: RItem,
                page: Int,
                pageLabel: String,
                deleted: Bool = false,
                syncState: ObjectSyncState = .synced,
                annotationType: String = AnnotationType.highlight.rawValue
            ) -> RItem {
                let item = RItem()
                item.key = key
                item.rawType = ItemTypes.annotation
                item.parent = parent
                item.customLibraryKey = .myLibrary
                item.deleted = deleted
                item.syncState = syncState
                item.annotationType = annotationType
                item.annotationSortIndex = String(format: "%05d|000000|00000", page)
                item.fields.append(createField(FieldKeys.Item.Annotation.Position.pageIndex, value: "\(page)"))
                item.fields.append(createField(FieldKeys.Item.Annotation.pageLabel, value: pageLabel))
                return item

                func createField(_ key: String, value: String) -> RItemField {
                    let field = RItemField()
                    field.key = key
                    field.value = value
                    field.changed = false
                    return field
                }
            }
        }
    }
}
