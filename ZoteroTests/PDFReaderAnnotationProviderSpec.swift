//
//  PDFReaderAnnotationProviderSpec.swift
//  ZoteroTests
//
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

@testable import Zotero

import Nimble
import PSPDFKit
import Quick
import RealmSwift

final class PDFReaderAnnotationProviderSpec: QuickSpec {
    override class func spec() {
        describe("PDF reader annotation insertion") {
            let attachmentKey = "AAAAAAAA"
            let libraryId: LibraryIdentifier = .custom(.myLibrary)
            let annotationKey = "BBBBBBBB"
            var realm: Realm!
            var dbStorage: DbStorage!
            var document: Document!
            var provider: PDFReaderAnnotationProvider!

            beforeEach {
                let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
                realm = try! Realm(configuration: config)
                dbStorage = RealmDbStorage(config: config)
                try! realm.write {
                    let attachment = RItem()
                    attachment.key = attachmentKey
                    attachment.rawType = ItemTypes.attachment
                    attachment.customLibraryKey = .myLibrary
                    attachment.syncState = .synced
                    realm.add(attachment)
                }

                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400))
                let data = renderer.pdfData { context in
                    context.beginPage()
                    context.beginPage()
                }
                document = Document(dataProviders: [DataContainerProvider(data: data)])
                let documentProvider = document.documentProviders.first!
                provider = PDFReaderAnnotationProvider(
                    documentProvider: documentProvider,
                    fileAnnotationProvider: documentProvider.annotationManager.fileAnnotationProvider!,
                    dbStorage: dbStorage,
                    dbQueue: DispatchQueue(label: "PDFReaderAnnotationProviderSpec.\(UUID().uuidString)"),
                    attachmentKey: attachmentKey,
                    libraryId: libraryId,
                    userId: 1,
                    username: "test",
                    documentPageCount: document.pageCount,
                    metadataEditable: true,
                    boundingBoxConverter: document,
                    appearance: .light
                )
                documentProvider.annotationManager.annotationProviders = [provider]
                provider.loadDocumentAnnotationsDatabaseCache(documentMD5: nil)
            }

            afterEach {
                provider = nil
                document = nil
                dbStorage = nil
                realm = nil
            }

            it("keeps an incoming object when the page subsequently loads the same database key") {
                storeAnnotation(key: annotationKey)
                storeAnnotation(key: "CCCCCCCC")
                expect(provider.hasLoadedAnnotationsForPage(at: 0)).to(beFalse())
                let incoming = incomingAnnotation(key: annotationKey)
                let added = provider.add([incoming], options: [.suppressNotifications: true])

                let pageAnnotations = provider.annotationsForPage(at: 0) ?? []
                expect(added?.count).to(equal(1))
                expect(pageAnnotations.filter { $0.key == annotationKey }.count).to(equal(1))
                expect(pageAnnotations.filter { $0.key == "CCCCCCCC" }.count).to(equal(1))
                expect(provider.annotationIfLoaded(with: annotationKey) === incoming).to(beTrue())
                expect(incoming.document === document).to(beTrue())
                expect(provider.hasLoadedAnnotationsForPage(at: 0)).to(beTrue())
                expect(provider.hasLoadedAnnotationsForPage(at: 1)).to(beFalse())
            }

            it("keeps the page-loaded object when the incoming callback arrives afterwards") {
                storeAnnotation(key: annotationKey)
                let loaded = provider.annotationsForPage(at: 0)?.first { $0.key == annotationKey }
                expect(loaded).notTo(beNil())
                let incoming = incomingAnnotation(key: annotationKey)

                let added = provider.add([incoming], options: [.suppressNotifications: true])

                expect(added?.isEmpty).to(beTrue())
                expect(provider.annotationIfLoaded(with: annotationKey) === loaded).to(beTrue())
                expect((provider.annotationsForPage(at: 0) ?? []).filter { $0.key == annotationKey }.count).to(equal(1))
            }

            it("allows a removed key to be inserted again") {
                let original = incomingAnnotation(key: annotationKey)
                _ = provider.add([original], options: [.suppressNotifications: true])
                _ = provider.remove([original], options: [.suppressNotifications: true])
                let restored = incomingAnnotation(key: annotationKey)

                let added = provider.add([restored], options: [.suppressNotifications: true])

                expect(added?.count).to(equal(1))
                expect(provider.annotationIfLoaded(with: annotationKey) === restored).to(beTrue())
                expect((provider.annotationsForPage(at: 0) ?? []).filter { $0.key == annotationKey }.count).to(equal(1))
            }

            it("keeps a local annotation reindexed by its assigned key when the database supplies the same key") {
                let local = PSPDFKit.NoteAnnotation(contents: "test")
                local.pageIndex = 0
                local.boundingBox = CGRect(x: 10, y: 20, width: 20, height: 20)
                _ = provider.add([local], options: [.suppressNotifications: true])
                let uuid = local.uuid
                local.key = annotationKey
                provider.reindex(annotation: local, previousKey: uuid)
                let incoming = incomingAnnotation(key: annotationKey)

                let added = provider.add([incoming], options: [.suppressNotifications: true])

                expect(added?.isEmpty).to(beTrue())
                expect(provider.annotationIfLoaded(with: annotationKey) === local).to(beTrue())
                expect(provider.annotationIfLoaded(at: 0, with: annotationKey) === local).to(beTrue())
                expect(provider.annotationIfLoaded(with: uuid)).to(beNil())
            }

            func incomingAnnotation(key: String) -> PSPDFKit.Annotation {
                let annotation = PSPDFKit.NoteAnnotation(contents: "test")
                annotation.key = key
                annotation.source = .database
                annotation.baseColor = "#ffd400"
                annotation.color = .yellow
                annotation.pageIndex = 0
                annotation.boundingBox = CGRect(x: 10, y: 20, width: 20, height: 20)
                return annotation
            }

            func storeAnnotation(key: String) {
                try! realm.write {
                    let item = RItem()
                    item.key = key
                    item.rawType = ItemTypes.annotation
                    item.annotationType = AnnotationType.note.rawValue
                    item.parent = realm.objects(RItem.self).filter(.key(attachmentKey)).first!
                    item.customLibraryKey = .myLibrary
                    item.syncState = .synced
                    item.annotationSortIndex = "00000|000000|00020"
                    for (key, value) in [
                        (FieldKeys.Item.Annotation.Position.pageIndex, "0"),
                        (FieldKeys.Item.Annotation.pageLabel, "1"),
                        (FieldKeys.Item.Annotation.color, "#ffd400"),
                        (FieldKeys.Item.Annotation.comment, "test")
                    ] {
                        let field = RItemField()
                        field.key = key
                        field.value = value
                        item.fields.append(field)
                    }
                    let rect = RRect()
                    rect.minX = 10
                    rect.minY = 20
                    rect.maxX = 30
                    rect.maxY = 40
                    item.rects.append(rect)
                    realm.add(item)
                }
            }
        }
    }
}
