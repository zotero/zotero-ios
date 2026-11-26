//
//  PDFAnnotationReconciliationSpec.swift
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

final class PDFAnnotationReconciliationSpec: QuickSpec {
    override class func spec() {
        describe("PDF annotation reconciliation") {
            var realm: Realm!
            var document: Document!
            var item: RItem!

            beforeEach {
                realm = try! Realm(configuration: .init(inMemoryIdentifier: UUID().uuidString))
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400))
                document = Document(dataProviders: [DataContainerProvider(data: renderer.pdfData { $0.beginPage() })])
                try! realm.write {
                    item = RItem()
                    item.key = "BBBBBBBB"
                    item.rawType = ItemTypes.annotation
                    item.annotationType = AnnotationType.note.rawValue
                    item.customLibraryKey = .myLibrary
                    item.changeType = .user
                    item.annotationSortIndex = "00000|000000|00020"
                    for (key, value) in [
                        (FieldKeys.Item.Annotation.Position.pageIndex, "0"),
                        (FieldKeys.Item.Annotation.pageLabel, "1"),
                        (FieldKeys.Item.Annotation.color, "#ff6666"),
                        (FieldKeys.Item.Annotation.comment, "saved text"),
                        (FieldKeys.Item.Annotation.Position.fontSize, "18"),
                        (FieldKeys.Item.Annotation.Position.rotation, "90")
                    ] {
                        let field = RItemField()
                        field.key = key
                        field.value = value
                        item.fields.append(field)
                    }
                    let rect = RRect()
                    rect.minX = 30
                    rect.minY = 40
                    rect.maxX = 130
                    rect.maxY = 100
                    item.rects.append(rect)
                    realm.add(item)
                }
            }

            afterEach {
                item = nil
                document = nil
                realm = nil
            }

            it("applies only properties that differ from the database and is a no-op on the next echo") {
                let annotation = PDFDatabaseAnnotation(item: item)!
                let native = PSPDFKit.NoteAnnotation(contents: annotation.comment)
                native.baseColor = "#ffd400"
                native.pageIndex = 0
                // Position already matches the database, only the color was changed by another reader.
                native.boundingBox = annotation.boundingBox(boundingBoxConverter: document)
                let changes = PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document)

                expect(changes).to(equal(.color))
                expect(native.baseColor).to(equal(annotation.color))
                expect(PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document).isEmpty).to(beTrue())
            }

            it("reconciles free text contents, font and rotation and is a no-op on the next echo") {
                try! realm.write { item.annotationType = AnnotationType.freeText.rawValue }
                let annotation = PDFDatabaseAnnotation(item: item)!
                let native = PSPDFKit.FreeTextAnnotation(contents: "old text")
                native.pageIndex = 0
                native.baseColor = annotation.color
                native.fontSize = 12
                native.boundingBox = CGRect(x: 10, y: 10, width: 80, height: 40)
                document.add(annotations: [native], options: [.suppressNotifications: true])

                let changes = PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document)
                expect(changes.contains([.contents, .fontSize, .rotation])).to(beTrue())
                expect(native.contents).to(equal(annotation.comment))
                expect(native.fontSize).to(equal(CGFloat(18)))
                expect(native.rotation).to(equal(UInt(90)))
                // Stored bounding box is not rotated.
                expect(AnnotationConverter.rects(from: native)?.first?.rounded(to: 3)).to(equal(annotation.boundingBox(boundingBoxConverter: document)))
                expect(PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document).isEmpty).to(beTrue())
            }

            it("moves a rotated free text without changing its rotation and is a no-op on the next echo") {
                try! realm.write { item.annotationType = AnnotationType.freeText.rawValue }
                // Converted the same way as when loaded from the database, so that the rotated geometry matches a real reader.
                let native = AnnotationConverter.annotation(
                    from: PDFDatabaseAnnotation(item: item)!,
                    source: .database,
                    type: .zotero,
                    appearance: .light,
                    currentUserId: 1,
                    libraryId: .custom(.myLibrary),
                    metadataEditable: true,
                    displayName: "",
                    username: "",
                    boundingBoxConverter: document
                ) as! PSPDFKit.FreeTextAnnotation
                document.add(annotations: [native], options: [.suppressNotifications: true])
                // Moved by another reader.
                try! realm.write {
                    let rect = item.rects.first!
                    rect.minX = 50
                    rect.minY = 70
                    rect.maxX = 150
                    rect.maxY = 130
                }
                let annotation = PDFDatabaseAnnotation(item: item)!

                let changes = PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document)
                // Conversion also fits the font size to the stored bounding box, which doesn't fit the test text, so font size may be reconciled too.
                expect(changes.contains(.boundingBox)).to(beTrue())
                expect(changes.contains(.rotation)).to(beFalse())
                expect(native.rotation).to(equal(UInt(90)))
                // Stored bounding box is not rotated.
                expect(AnnotationConverter.rects(from: native)?.first?.rounded(to: 3)).to(equal(annotation.boundingBox(boundingBoxConverter: document)))
                expect(PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document).isEmpty).to(beTrue())
            }

            it("compares ink line width rounded, same as when stored") {
                try! realm.write {
                    item.annotationType = AnnotationType.ink.rawValue
                    let field = RItemField()
                    field.key = FieldKeys.Item.Annotation.Position.lineWidth
                    field.value = "1.5"
                    item.fields.append(field)
                }
                let annotation = PDFDatabaseAnnotation(item: item)!
                let native = PSPDFKit.InkAnnotation(lines: [])
                native.pageIndex = 0
                native.baseColor = annotation.color
                native.contents = annotation.comment
                native.lineWidth = 1.5004

                expect(PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document).isEmpty).to(beTrue())
                expect(native.lineWidth).to(equal(1.5004))
            }

            it("preserves the active comment while still applying other incoming properties") {
                let annotation = PDFDatabaseAnnotation(item: item)!
                let native = PSPDFKit.NoteAnnotation(contents: "currently typing")
                native.pageIndex = 0
                native.baseColor = "#ffd400"
                native.boundingBox = annotation.boundingBox(boundingBoxConverter: document)

                let changes = PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document, includeContents: false)
                expect(changes).to(equal(.color))
                expect(native.contents).to(equal("currently typing"))
                let afterEditing = PDFReaderActionHandler.reconcileProperties(of: native, with: annotation, appearance: .light, boundingBoxConverter: document)
                expect(afterEditing).to(equal(.contents))
                expect(native.contents).to(equal(annotation.comment))
            }
        }
    }
}
