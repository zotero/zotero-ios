//
//  DocumentWorkerControllerSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 21/2/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

@testable import Zotero

import Nimble
import Quick
import RxSwift

final class DocumentWorkerControllerSpec: QuickSpec {
    override class func spec() {
        var documentWorkerController: DocumentWorkerController!
        var disposeBag: DisposeBag!

        beforeSuite {
            documentWorkerController = DocumentWorkerController(fileStorage: TestControllers.fileStorage)
            disposeBag = DisposeBag()
        }

        describe("a Document Worker Controller") {
            context("with the JavaScriptCore shim") {
                func makeShimEngine(label: String = UUID().uuidString) throws -> DocumentWorkerJSEngine {
                    let bundle = Bundle(for: DocumentWorkerController.self)
                    guard let url = bundle.url(forResource: "document_worker_shim", withExtension: "js") else {
                        fail("document_worker_shim.js not found in app bundle")
                        throw DocumentWorkerJSEngine.EngineError.missingShim
                    }
                    let script = try String(contentsOf: url, encoding: .utf8)
                    let queue = DispatchQueue(label: "org.zotero.DocumentWorkerControllerSpec.\(label)")
                    let engine = DocumentWorkerJSEngine(bundle: bundle, queue: queue)
                    try engine.evaluate(script: script)
                    return engine
                }

                it("can evaluate the document worker shim in JavaScriptCore") {
                    let bundle = Bundle(for: DocumentWorkerController.self)
                    guard let url = bundle.url(forResource: "document_worker_shim", withExtension: "js") else {
                        fail("document_worker_shim.js not found in app bundle")
                        return
                    }
                    guard let script = try? String(contentsOf: url, encoding: .utf8) else {
                        fail("document_worker_shim.js could not be read")
                        return
                    }

                    var didPostMessage = false

                    let queue = DispatchQueue(label: "org.zotero.DocumentWorkerControllerSpec.queue")
                    let engine = DocumentWorkerJSEngine(bundle: bundle, queue: queue)
                    engine.onPostMessage = { _, _ in
                        didPostMessage = true
                    }

                    expect { try engine.evaluate(script: script) }.toNot(throwError())
                    expect(try? engine.evaluate(script: "self === globalThis")?.toBool()).to(beTrue())
                    _ = try? engine.evaluate(script: "self.postMessage({ hello: 'world' })")
                    expect(didPostMessage).to(beTrue())
                }

                it("provides console methods") {
                    let engine = try! makeShimEngine()
                    let script = """
                    typeof console.log === 'function' &&
                      typeof console.warn === 'function' &&
                      typeof console.error === 'function'
                    """

                    expect(try? engine.evaluate(script: script)?.toBool()).to(beTrue())
                    expect { try engine.evaluate(script: "console.log('log'); console.warn('warn'); console.error('error');") }.toNot(throwError())
                }

                it("provides crypto random values") {
                    let engine = try! makeShimEngine()
                    let script = """
                    (function () {
                      var arr = new Uint8Array(16);
                      crypto.getRandomValues(arr);
                      for (var i = 0; i < arr.length; i++) {
                        if (arr[i] !== 0) { return true; }
                      }
                      return false;
                    })()
                    """

                    expect(try? engine.evaluate(script: script)?.toBool()).to(beTrue())
                }

                it("provides UUID generation") {
                    let engine = try! makeShimEngine()
                    let script = """
                    (function () {
                      var uuid = crypto.randomUUID();
                      return typeof uuid === 'string' &&
                        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uuid);
                    })()
                    """

                    expect(try? engine.evaluate(script: script)?.toBool()).to(beTrue())
                }

                it("provides base64 helpers") {
                    let engine = try! makeShimEngine()
                    let script = """
                    atob(btoa('hello')) === 'hello' &&
                      atob(btoa('')) === '' &&
                      atob(btoa('abc123!@#')) === 'abc123!@#'
                    """

                    expect(try? engine.evaluate(script: script)?.toBool()).to(beTrue())
                }

                it("provides TextDecoder") {
                    let engine = try! makeShimEngine()
                    let script = """
                    (function () {
                      var utf8 = new TextDecoder('utf-8').decode(new Uint8Array([72, 101, 108, 108, 111]));
                      var latin1 = new TextDecoder('iso-8859-1').decode(new Uint8Array([72, 233]));
                      var utf16 = new TextDecoder('utf-16le').decode(new Uint8Array([72, 0, 105, 0]));
                      return utf8 === 'Hello' && latin1 === 'H\\u00e9' && utf16 === 'Hi';
                    })()
                    """

                    expect(try? engine.evaluate(script: script)?.toBool()).to(beTrue())
                }

                it("provides timers") {
                    let engine = try! makeShimEngine()

                    expect { try engine.evaluate(script: "var __timerCalled = false; setTimeout(function () { __timerCalled = true; }, 0);") }.toNot(throwError())
                    expect { try? engine.evaluate(script: "__timerCalled")?.toBool() }
                        .toEventually(equal(true), timeout: .seconds(2))
                }

                it("provides AbortController") {
                    let engine = try! makeShimEngine()
                    let script = """
                    (function () {
                      var ac = new AbortController();
                      if (ac.signal.aborted) { return false; }
                      ac.abort('done');
                      return ac.signal.aborted && ac.signal.reason === 'done';
                    })()
                    """

                    expect(try? engine.evaluate(script: script)?.toBool()).to(beTrue())
                }

                it("provides MessageChannel") {
                    let engine = try! makeShimEngine()
                    let script = """
                    (function () {
                      var received = null;
                      var ch = new MessageChannel();
                      ch.port2.onmessage = function (event) { received = event.data; };
                      ch.port1.postMessage('test-message');
                      return received === 'test-message';
                    })()
                    """

                    expect(try? engine.evaluate(script: script)?.toBool()).to(beTrue())
                }

                it("provides Blob-backed object URLs") {
                    let engine = try! makeShimEngine()
                    let script = """
                    var __blobFetchResult = false;
                    var __blobFetchError = null;
                    (function () {
                      var blob = new Blob([new Uint8Array([37, 80, 68, 70])], { type: 'application/pdf' });
                      var url = URL.createObjectURL(blob);
                      fetch(url)
                        .then(function (response) { return response.arrayBuffer(); })
                        .then(function (buffer) {
                          var bytes = new Uint8Array(buffer);
                          URL.revokeObjectURL(url);
                          __blobFetchResult = bytes[0] === 37 && bytes[1] === 80 && bytes[2] === 68 && bytes[3] === 70;
                        })
                        .catch(function (error) { __blobFetchError = String(error); });
                    })();
                    """

                    expect { try engine.evaluate(script: script) }.toNot(throwError())
                    expect { try? engine.evaluate(script: "__blobFetchResult")?.toBool() }
                        .toEventually(equal(true), timeout: .seconds(2))
                }
            }

            context("with a valid PDF URL") {
                let fileName = "bitcoin"
                let fileExtension = "pdf"
                let contentType = "application/pdf"
                let key = "aaaaaaaa"
                let fileURL = Bundle(for: Self.self).url(forResource: fileName, withExtension: fileExtension)!
                let data = try! Data(contentsOf: fileURL)
                let libraryId = LibraryIdentifier.custom(.myLibrary)
                let file = Files.attachmentFile(in: libraryId, key: key, filename: fileName, contentType: contentType) as! FileData
                try! TestControllers.fileStorage.write(data, to: file, options: .atomic)
                expect(TestControllers.fileStorage.has(file)).to(beTrue())

                it("can extract recognizer data") {
                    let work: DocumentWorkerController.Work = .recognizer
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheData: false, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(10)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
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
                    let work: DocumentWorkerController.Work = .fullText(pages: nil)
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheData: false, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
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
                    let work: DocumentWorkerController.Work = .fullText(pages: [0])
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheData: false, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
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
                    let work: DocumentWorkerController.Work = .fullText(pages: [0, 1])
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheData: false, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
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
            }

            context("with a valid CMap PDF URL") {
                let fileName = "cmap"
                let fileExtension = "pdf"
                let contentType = "application/pdf"
                let key = "bbbbbbbb"
                let fileURL = Bundle(for: Self.self).url(forResource: fileName, withExtension: fileExtension)!
                let data = try! Data(contentsOf: fileURL)
                let libraryId = LibraryIdentifier.custom(.myLibrary)
                let file = Files.attachmentFile(in: libraryId, key: key, filename: fileName, contentType: contentType) as! FileData
                try! TestControllers.fileStorage.write(data, to: file, options: .atomic)
                expect(TestControllers.fileStorage.has(file)).to(beTrue())

                it("can extract full text") {
                    let work: DocumentWorkerController.Work = .fullText(pages: nil)
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheData: false, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
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
                    process(updates: emittedUpdates, jsonFileName: "cmap_pdf_full_text")
                }
            }

            context("with a valid Font Data PDF URL") {
                let fileName = "font_data"
                let fileExtension = "pdf"
                let contentType = "application/pdf"
                let key = "cccccccc"
                let fileURL = Bundle(for: Self.self).url(forResource: fileName, withExtension: fileExtension)!
                let data = try! Data(contentsOf: fileURL)
                let libraryId = LibraryIdentifier.custom(.myLibrary)
                let file = Files.attachmentFile(in: libraryId, key: key, filename: fileName, contentType: contentType) as! FileData
                try! TestControllers.fileStorage.write(data, to: file, options: .atomic)
                expect(TestControllers.fileStorage.has(file)).to(beTrue())

                it("can extract full text") {
                    let work: DocumentWorkerController.Work = .fullText(pages: nil)
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheData: false, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
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
                    process(updates: emittedUpdates, jsonFileName: "font_data_pdf_full_text")
                }
            }
            func process(updates: [DocumentWorkerController.Update.Kind], jsonFileName: String) {
                for (index, update) in updates.enumerated() {
                    switch update {
                    case .inProgress:
                        expect(index).to(equal(0))

                    case .extractedData(let data):
                        expect(index).to(equal(1))
                        let url = Bundle(for: Self.self).url(forResource: jsonFileName, withExtension: "json")!
                        let expectedData = try! Data(contentsOf: url)
                        let expectedJSONData = try! JSONSerialization.jsonObject(with: expectedData, options: .allowFragments) as! [String: Any]
                        compareJSONObjects(actual: data, expected: expectedJSONData, context: jsonFileName)

                    default:
                        fail("unexpected update \(index): \(update)")
                    }
                }

                func compareJSONObjects(actual: [String: Any], expected: [String: Any], context: String) {
                    let actualKeys = actual.keys
                    let expectedKeys = expected.keys
                    expect(Set(actualKeys)).to(equal(Set(expectedKeys)))
                    for key in expectedKeys {
                        switch key {
                        case "metadata":
                            expect(actual[key] as? [String: String]).to(equal(expected[key] as? [String: String]))

                        case "text":

                            expect((actual[key] as? String)?.replacingOccurrences(of: "\n", with: " ")).to(equal((expected[key] as? String)?.replacingOccurrences(of: "\n", with: " ")))

                        default:
                            expect(actual[key] as? AnyHashable).to(equal(expected[key] as? AnyHashable))
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
