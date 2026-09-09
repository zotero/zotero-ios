//
//  ReadAttachmentUploadsDbRequestSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 18/2/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

import RealmSwift
import Nimble
import Quick

final class ReadAttachmentUploadsDbRequestSpec: QuickSpec {
    override class func spec() {
        describe("a read attachment uploads request") {
            let libraryId: LibraryIdentifier = .custom(.myLibrary)
            var realm: Realm!
            var fileStorage: FileStorageController!

            beforeEach {
                let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
                realm = try! Realm(configuration: config)
                fileStorage = FileStorageController()

                try! realm.write {
                    let library = RCustomLibrary()
                    library.type = .myLibrary
                    realm.add(library)
                }
            }

            func createField(_ key: String, value: String) -> RItemField {
                let field = RItemField()
                field.key = key
                field.value = value
                field.changed = false
                return field
            }

            func createParent(key: String, deleted: Bool) -> RItem {
                let parent = RItem()
                parent.key = key
                parent.rawType = "journalArticle"
                parent.customLibraryKey = .myLibrary
                parent.deleted = deleted
                return parent
            }

            func createAttachment(key: String, deleted: Bool = false, parent: RItem? = nil) -> RItem {
                let item = RItem()
                item.key = key
                item.rawType = ItemTypes.attachment
                item.customLibraryKey = .myLibrary
                item.attachmentNeedsSync = true
                item.deleted = deleted
                item.parent = parent
                item.fields.append(createField(FieldKeys.Item.Attachment.linkMode, value: LinkMode.importedFile.rawValue))
                item.fields.append(createField(FieldKeys.Item.Attachment.contentType, value: "application/pdf"))
                item.fields.append(createField(FieldKeys.Item.Attachment.mtime, value: "123"))
                item.fields.append(createField(FieldKeys.Item.Attachment.md5, value: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
                item.fields.append(createField(FieldKeys.Item.Attachment.filename, value: "\(key).pdf"))
                return item
            }

            it("returns non-deleted attachments that need upload") {
                let key = "AAAAAAAA"

                try! realm.write {
                    realm.add(createAttachment(key: key))
                }

                let request = ReadAttachmentUploadsDbRequest(libraryId: libraryId, fileStorage: fileStorage)
                let uploads = try! request.process(in: realm)

                expect(uploads.map({ $0.key })).to(equal([key]))
            }

            it("does not return deleted attachments") {
                let validKey = "AAAAAAAA"
                let deletedKey = "BBBBBBBB"

                try! realm.write {
                    realm.add(createAttachment(key: validKey))
                    realm.add(createAttachment(key: deletedKey, deleted: true))
                }

                let request = ReadAttachmentUploadsDbRequest(libraryId: libraryId, fileStorage: fileStorage)
                let uploads = try! request.process(in: realm)
                let keys = Set(uploads.map({ $0.key }))

                expect(keys.contains(validKey)).to(beTrue())
                expect(keys.contains(deletedKey)).to(beFalse())
            }

            it("does not return attachments with deleted parent") {
                let validKey = "AAAAAAAA"
                let childKey = "BBBBBBBB"

                try! realm.write {
                    let deletedParent = createParent(key: "CCCCCCCC", deleted: true)
                    realm.add(deletedParent)
                    realm.add(createAttachment(key: validKey))
                    realm.add(createAttachment(key: childKey, parent: deletedParent))
                }

                let request = ReadAttachmentUploadsDbRequest(libraryId: libraryId, fileStorage: fileStorage)
                let uploads = try! request.process(in: realm)
                let keys = Set(uploads.map({ $0.key }))

                expect(keys.contains(validKey)).to(beTrue())
                expect(keys.contains(childKey)).to(beFalse())
            }
        }
    }
}
