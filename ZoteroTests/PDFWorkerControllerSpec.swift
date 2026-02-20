//
//  PDFWorkerControllerSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 21/2/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

@testable import Zotero

import Nimble
import Quick
import RxSwift

class WebViewProviderViewController: UIViewController { }

extension WebViewProviderViewController: WebViewProvider {
    func addWebView(configuration: WKWebViewConfiguration?) -> WKWebView {
        let webView: WKWebView = configuration.flatMap({ WKWebView(frame: .zero, configuration: $0) }) ?? WKWebView()
        webView.isHidden = true
        view.insertSubview(webView, at: 0)
        return webView
    }
}

final class PDFWorkerControllerSpec: QuickSpec {
    override class func spec() {
        var webViewProviderViewController: WebViewProviderViewController!
        var pdfWorkerController: PDFWorkerController!
        var disposeBag: DisposeBag!

        beforeSuite {
            webViewProviderViewController = WebViewProviderViewController()
            webViewProviderViewController.loadViewIfNeeded()
            pdfWorkerController = PDFWorkerController(fileStorage: TestControllers.fileStorage)
            pdfWorkerController.webViewProvider = webViewProviderViewController
            disposeBag = DisposeBag()
        }

        describe("a PDF Worker Controller") {
            context("with a valid PDF URL") {
                let fileΝame = "bitcoin"
                let fileExtension = "pdf"
                let contentType = "application/pdf"
                let key = "aaaaaaaa"
                let fileURL = Bundle(for: Self.self).url(forResource: fileΝame, withExtension: fileExtension)!
                let data = try! Data(contentsOf: fileURL)
                let libraryId = LibraryIdentifier.custom(.myLibrary)
                let file = Files.attachmentFile(in: libraryId, key: key, filename: fileΝame, contentType: contentType) as! FileData
                try! TestControllers.fileStorage.write(data, to: file, options: .atomic)
                expect(TestControllers.fileStorage.has(file)).to(beTrue())

                it("can extract recognizer data") {
                    let work: PDFWorkerController.Work = .recognizer
                    let worker = PDFWorkerController.Worker(file: file, priority: .default)
                    var emittedUpdates: [PDFWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(10)) { completion in
                        pdfWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(2), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "bitcoin_pdf_recognizer_data")
                }

                it("can extract full text") {
                    let work: PDFWorkerController.Work = .fullText(pages: nil)
                    let worker = PDFWorkerController.Worker(file: file, priority: .default)
                    var emittedUpdates: [PDFWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        pdfWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(2), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "bitcoin_pdf_full_text")
                }

                it("can extract text from a single page") {
                    let work: PDFWorkerController.Work = .fullText(pages: [0])
                    let worker = PDFWorkerController.Worker(file: file, priority: .default)
                    var emittedUpdates: [PDFWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        pdfWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(2), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "bitcoin_pdf_page_0_text")
                }

                it("can extract text from two pages") {
                    let work: PDFWorkerController.Work = .fullText(pages: [0, 1])
                    let worker = PDFWorkerController.Worker(file: file, priority: .default)
                    var emittedUpdates: [PDFWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        pdfWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(2), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "bitcoin_pdf_pages_0_1_text")
                }

                func process(updates: [PDFWorkerController.Update.Kind], jsonFileName: String) {
                    for (index, update) in updates.enumerated() {
                        switch update {
                        case .inProgress:
                            expect(index).to(equal(0))

                        case .extractedData(let data):
                            expect(index).to(equal(1))
                            let url = Bundle(for: Self.self).url(forResource: jsonFileName, withExtension: "json")!
                            let expectedData = try! Data(contentsOf: url)
                            let expectedJSONData = try! JSONSerialization.jsonObject(with: expectedData, options: .allowFragments) as! [String: Any]
                            expect(data as? [String: AnyHashable]).to(equal(expectedJSONData as! [String: AnyHashable]))

                        default:
                            fail("unexpected update \(index): \(update)")
                        }
                    }
                }
            }
        }

        afterSuite {
            try? TestControllers.fileStorage.remove(Files.downloads)
        }
    }
}
