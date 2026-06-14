//
//  DocumentWorkerControllerSpec.swift
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

final class DocumentWorkerControllerSpec: QuickSpec {
    override class func spec() {
        var documentWorkerController: DocumentWorkerController!
        var webViewProvider: TestDocumentWorkerWebViewProvider!
        var disposeBag: DisposeBag!

        beforeSuite {
            documentWorkerController = DocumentWorkerController(fileStorage: TestControllers.fileStorage)
            webViewProvider = TestDocumentWorkerWebViewProvider()
            documentWorkerController.webViewProvider = webViewProvider
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

                it("provides TextEncoder") {
                    let engine = try! makeShimEngine()
                    let script = """
                    (function () {
                      var encoded = new TextEncoder().encode('Hello \\u20ac \\ud83d\\ude00');
                      var decoded = new TextDecoder('utf-8').decode(encoded);
                      var number = new TextDecoder('utf-8').decode(new TextEncoder().encode(0));
                      var loneSurrogate = new TextDecoder('utf-8').decode(new TextEncoder().encode('\\ud800'));
                      return encoded instanceof Uint8Array &&
                        decoded === 'Hello \\u20ac \\ud83d\\ude00' &&
                        number === '0' &&
                        loneSurrogate === '\\ufffd';
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
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheInput: false, isOneOff: true, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .queued, .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(3), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "bitcoin_pdf_recognizer_data")
                }

                it("can extract full text") {
                    let work: DocumentWorkerController.Work = .fullText(pages: nil)
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheInput: false, isOneOff: true, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .queued, .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(3), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "bitcoin_pdf_full_text")
                }

                it("can extract text from a single page") {
                    let work: DocumentWorkerController.Work = .fullText(pages: [0])
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheInput: false, isOneOff: true, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .queued, .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(3), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "bitcoin_pdf_page_0_text")
                }

                it("can extract text from two pages") {
                    let work: DocumentWorkerController.Work = .fullText(pages: [0, 1])
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheInput: false, isOneOff: true, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .queued, .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(3), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "bitcoin_pdf_pages_0_1_text")
                }
            }

            context("with the WebView handler") {
                func makeWebViewDocumentWorkerHandler(
                    temporaryDirectory: File,
                    nativeONNXModelDataProvider: DocumentWorkerWebViewHandler.NativeONNXModelDataProvider? = nil
                ) -> DocumentWorkerWebViewHandler {
                    let configuration = WKWebViewConfiguration()
                    configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
                    let webView = webViewProvider.addWebView(configuration: configuration)
                    return DocumentWorkerWebViewHandler(
                        webView: webView,
                        temporaryDirectory: temporaryDirectory,
                        cleanup: {
                            try? FileManager.default.removeItem(at: temporaryDirectory.createUrl())
                        },
                        nativeONNXModelDataProvider: nativeONNXModelDataProvider
                    )
                }

                func intArray(from value: Any?) -> [Int]? {
                    if let values = value as? [Int] {
                        return values
                    }
                    if let values = value as? [NSNumber] {
                        return values.map(\.intValue)
                    }
                    return nil
                }

                func valueCount(from value: Any?) -> Int? {
                    if let values = value as? [Float] {
                        return values.count
                    }
                    if let values = value as? [Double] {
                        return values.count
                    }
                    if let values = value as? [NSNumber] {
                        return values.count
                    }
                    return nil
                }

                it("can round-trip through the native ONNX bridge without changing the worker runtime") {
                    let temporaryDirectory = try! prepareTemporaryDocumentWorkerDirectory()
                    var handler: DocumentWorkerWebViewHandler?

                    waitUntil(timeout: .seconds(20)) { completion in
                        DispatchQueue.main.async {
                            let documentWorkerHandler = makeWebViewDocumentWorkerHandler(temporaryDirectory: temporaryDirectory)
                            handler = documentWorkerHandler

                            documentWorkerHandler.nativeONNXBridgeEcho(payload: [
                                "type": "float32",
                                "dims": [2, 2],
                                "values": [1, 2, 3, 4]
                            ])
                            .subscribe(onSuccess: { result in
                                expect(result["runtime"] as? String).to(equal("native"))
                                let payload = result["payload"] as? [String: Any]
                                expect(payload?["type"] as? String).to(equal("float32"))
                                expect(payload?["dims"] as? [Int]).to(equal([2, 2]))
                                expect(payload?["values"] as? [Int]).to(equal([1, 2, 3, 4]))
                                completion()
                            }, onFailure: { error in
                                fail("native ONNX bridge echo failed - \(error)")
                                completion()
                            })
                            .disposed(by: disposeBag)
                        }
                    }

                    handler?.removeFromSuperviewAsynchronously()
                }

                it("can run a native ONNX model from the WebView bridge without changing the worker runtime") {
                    let temporaryDirectory = try! prepareTemporaryDocumentWorkerDirectory()
                    var handler: DocumentWorkerWebViewHandler?

                    waitUntil(timeout: .seconds(20)) { completion in
                        DispatchQueue.main.async {
                            let documentWorkerHandler = makeWebViewDocumentWorkerHandler(
                                temporaryDirectory: temporaryDirectory,
                                nativeONNXModelDataProvider: { model in
                                    guard let url = Bundle(for: ONNXRuntimeSpec.self).url(forResource: model, withExtension: "onnx") else {
                                        throw DocumentWorkerWebViewHandler.Error.invalidNativeONNXBridgePayload("missing model fixture")
                                    }
                                    return try Data(contentsOf: url)
                                }
                            )
                            handler = documentWorkerHandler

                            documentWorkerHandler.nativeONNXBridgeRun(
                                model: "block_seg_classifier_model",
                                inputs: [
                                    [
                                        "name": "regular_features",
                                        "type": "float32",
                                        "dims": [1, 1, 196],
                                        "values": Array(repeating: 0, count: 196)
                                    ],
                                    [
                                        "name": "rich_features",
                                        "type": "float32",
                                        "dims": [1, 1, 306],
                                        "values": Array(repeating: 0, count: 306)
                                    ],
                                    [
                                        "name": "hash_slots",
                                        "type": "int64",
                                        "dims": [1, 1, 36],
                                        "values": Array(repeating: 0, count: 36)
                                    ],
                                    [
                                        "name": "char_slots",
                                        "type": "int64",
                                        "dims": [1, 1, 4],
                                        "values": Array(repeating: 0, count: 4)
                                    ],
                                    [
                                        "name": "pad_mask",
                                        "type": "bool",
                                        "dims": [1, 1],
                                        "values": [false]
                                    ]
                                ],
                                outputNames: [
                                    "type_logits",
                                    "flow_logits"
                                ]
                            )
                            .subscribe(onSuccess: { result in
                                let outputs = result["outputs"] as? [String: Any]
                                let typeLogits = outputs?["type_logits"] as? [String: Any]
                                expect(typeLogits?["type"] as? String).to(equal("float32"))
                                expect(intArray(from: typeLogits?["dims"])).to(equal([1, 1, 7]))
                                expect(valueCount(from: typeLogits?["values"])).to(equal(7))

                                let flowLogits = outputs?["flow_logits"] as? [String: Any]
                                expect(flowLogits?["type"] as? String).to(equal("float32"))
                                expect(intArray(from: flowLogits?["dims"])).to(equal([1, 1, 3]))
                                expect(valueCount(from: flowLogits?["values"])).to(equal(3))
                                completion()
                            }, onFailure: { error in
                                fail("native ONNX bridge run failed - \(error)")
                                completion()
                            })
                            .disposed(by: disposeBag)
                        }
                    }

                    handler?.removeFromSuperviewAsynchronously()
                }
            }

            context("with a valid URL") {
                let libraryId = LibraryIdentifier.custom(.myLibrary)

                func fixtureURL(forResource resource: String, withExtension fileExtension: String) -> URL {
                    Bundle(for: Self.self).url(forResource: resource, withExtension: fileExtension)!
                }

                func makeFile(resource: String, fileExtension: String, key: String, filename: String, contentType: String) -> FileData {
                    let sourceURL = fixtureURL(forResource: resource, withExtension: fileExtension)
                    let data = try! Data(contentsOf: sourceURL)
                    let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: contentType) as! FileData
                    try! TestControllers.fileStorage.write(data, to: file, options: .atomic)
                    expect(TestControllers.fileStorage.has(file)).to(beTrue())
                    return file
                }

                func processStructuredDocumentText(file: FileData, expectedURL: URL, timeout: Int) {
                    let work: DocumentWorkerController.Work = .structuredDocumentText
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheInput: false, isOneOff: true, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(timeout)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .queued, .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(3), timeout: .seconds(timeout))
                    assertStructuredDocumentTextPack(updates: emittedUpdates, expectedURL: expectedURL)
                }

                let structuredTextFixtures = [
                    (description: "PDF", resource: "1", fileExtension: "pdf", key: "dddddddd", contentType: "application/pdf", expected: "1_pdf_structured_text", timeout: 120),
                    (description: "bitcoin PDF", resource: "bitcoin", fileExtension: "pdf", key: "ddddddd2", contentType: "application/pdf", expected: "bitcoin_pdf_structured_text", timeout: 120),
                    (description: "EPUB", resource: "1", fileExtension: "epub", key: "eeeeeeee", contentType: "application/epub+zip", expected: "1_epub_structured_text", timeout: 30),
                    (description: "advanced EPUB", resource: "1_advanced", fileExtension: "epub", key: "eeeeeee1", contentType: "application/epub+zip", expected: "1_advanced_epub_structured_text", timeout: 60),
                    (description: "EPUB 2", resource: "2", fileExtension: "epub", key: "eeeeeee2", contentType: "application/epub+zip", expected: "2_epub_structured_text", timeout: 60),
                    (description: "advanced EPUB 2", resource: "2_advanced", fileExtension: "epub", key: "eeeeee2a", contentType: "application/epub+zip", expected: "2_advanced_epub_structured_text", timeout: 60),
                    (description: "EPUB 3", resource: "3", fileExtension: "epub", key: "eeeeeee3", contentType: "application/epub+zip", expected: "3_epub_structured_text", timeout: 60),
                    (description: "snapshot HTML", resource: "1", fileExtension: "html", key: "ffffffff", contentType: "text/html", expected: "1_html_structured_text", timeout: 20),
                    (description: "snapshot HTML 2", resource: "2", fileExtension: "html", key: "fffffff2", contentType: "text/html", expected: "2_html_structured_text", timeout: 20)
                ]

                for fixture in structuredTextFixtures {
                    it("can extract structured document text for \(fixture.description)") {
                        let file = makeFile(
                            resource: fixture.resource,
                            fileExtension: fixture.fileExtension,
                            key: fixture.key,
                            filename: fixture.resource,
                            contentType: fixture.contentType
                        )

                        processStructuredDocumentText(
                            file: file,
                            expectedURL: fixtureURL(forResource: fixture.expected, withExtension: "json"),
                            timeout: fixture.timeout
                        )
                    }
                }

                it("can extract structured document text for PDF with JavaScriptCore and native ONNX") {
                    let nativeDocumentWorkerController = DocumentWorkerController(
                        fileStorage: TestControllers.fileStorage,
                        usesNativeONNXForStructuredDocumentText: true
                    )

                    let work: DocumentWorkerController.Work = .structuredDocumentText
                    let key = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
                    let file = makeFile(
                        resource: "1",
                        fileExtension: "pdf",
                        key: key,
                        filename: "1",
                        contentType: "application/pdf"
                    )
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheInput: false, isOneOff: true, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(120)) { completion in
                        nativeDocumentWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                expect(update.runtime).to(equal(.jsContext))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .queued, .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(3), timeout: .seconds(120))
                    assertStructuredDocumentTextPack(updates: emittedUpdates)
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
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheInput: false, isOneOff: true, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .queued, .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(3), timeout: .seconds(20))
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
                    let worker = DocumentWorkerController.Worker(file: file, shouldCacheInput: false, isOneOff: true, priority: .default)
                    var emittedUpdates: [DocumentWorkerController.Update.Kind] = []

                    waitUntil(timeout: .seconds(20)) { completion in
                        documentWorkerController.queue(work: work, in: worker)
                            .subscribe(onNext: { update in
                                expect(update.work).to(equal(work))
                                emittedUpdates.append(update.kind)
                                switch update.kind {
                                case .failed, .cancelled, .extractedData:
                                    completion()

                                case .queued, .inProgress:
                                    break
                                }
                            })
                            .disposed(by: disposeBag)
                    }

                    expect(emittedUpdates.count).toEventually(equal(3), timeout: .seconds(20))
                    process(updates: emittedUpdates, jsonFileName: "font_data_pdf_full_text")
                }
            }

            func process(updates: [DocumentWorkerController.Update.Kind], ignoreKeys: Set<String> = [], jsonFileName: String) {
                let url = Bundle(for: Self.self).url(forResource: jsonFileName, withExtension: "json")!
                process(updates: updates, ignoreKeys: ignoreKeys, jsonURL: url)
            }

            func assertStructuredDocumentTextPack(updates: [DocumentWorkerController.Update.Kind], expectedURL: URL? = nil) {
                let magic = Data([0x89, 0x53, 0x44, 0x54, 0x0d, 0x0a, 0x1a, 0x0a])
                var materializedData: [String: Any]?
                for (index, update) in updates.enumerated() {
                    switch update {
                    case .queued:
                        expect(index).to(equal(0))

                    case .inProgress:
                        expect(index).to(equal(1))

                    case .extractedData(let data, _):
                        expect(index).to(equal(2))
                        guard let buf = data["buf"] as? Data else {
                            fail("expected SDT pack data, got \(data)")
                            return
                        }
                        expect(buf.count).to(beGreaterThan(magic.count))
                        expect(Data(buf.prefix(magic.count))).to(equal(magic))
                        do {
                            let pack = try SDTPack(data: buf)
                            let metadata = try pack.getMetadata()
                            let catalog = try pack.getCatalog()
                            let materialized = try pack.materialize()
                            materializedData = materialized
                            guard let materializedMetadata = materialized["metadata"] as? [String: Any] else {
                                fail("missing materialized metadata")
                                return
                            }
                            guard let materializedCatalog = materialized["catalog"] as? [String: Any] else {
                                fail("missing materialized catalog")
                                return
                            }
                            expect((metadata as NSDictionary).isEqual(materializedMetadata)).to(beTrue())
                            expect((catalog as NSDictionary).isEqual(materializedCatalog)).to(beTrue())
                            assertBlockAccess(in: pack, materialized: materialized)
                            try assertPageBlocksAccess(in: pack, materialized: materialized)
                        } catch {
                            fail("failed to materialize SDTPack: \(error)")
                            return
                        }

                    default:
                        fail("unexpected update \(index): \(update)")
                    }
                }
                guard let materializedData else {
                    fail("missing materialized SDTPack data")
                    return
                }
                if let expectedURL {
                    process(updates: [.queued, .inProgress, .extractedData(data: materializedData)], ignoreKeys: ["dateCreated"], jsonURL: expectedURL)
                }
            }

            func assertBlockAccess(in pack: SDTPack, materialized: [String: Any]) {
                guard let content = materialized["content"] as? [[String: Any]] else {
                    fail("missing materialized content")
                    return
                }
                expect(content).toNot(beEmpty())

                do {
                    for index in sampleIndexes(count: content.count) {
                        let block = try pack.getBlock(ref: [index])
                        expect(block).toNot(beNil())
                        if let block {
                            expect((block as NSDictionary).isEqual(content[index])).to(beTrue())
                        }
                    }

                    if let nestedRef = firstContentNestedRef(in: content) {
                        let block = try pack.getBlock(ref: nestedRef)
                        let expected = node(in: content, at: nestedRef)
                        expect(block).toNot(beNil())
                        expect(expected).toNot(beNil())
                        if let block, let expected {
                            expect((block as NSDictionary).isEqual(expected)).to(beTrue())
                        }
                    }

                    expect(try pack.getBlock(ref: [])).to(beNil())
                    expect(try pack.getBlock(ref: [-1])).to(beNil())
                    expect(try pack.getBlock(ref: [content.count])).to(beNil())
                    try assertBlocksAccess(content: content)
                } catch {
                    fail("failed to read SDTPack block: \(error)")
                }

                func assertBlocksAccess(content: [[String: Any]]) throws {
                    guard !content.isEmpty else {
                        expect(try pack.getBlocks(startBlock: 0, endBlock: 0)).to(beEmpty())
                        return
                    }

                    let firstBlock = try pack.getBlocks(startBlock: 0, endBlock: 0)
                    expect(firstBlock.count).to(equal(1))
                    if let block = firstBlock.first {
                        expect((block as NSDictionary).isEqual(content[0])).to(beTrue())
                    }

                    let sampledIndexes = sampleIndexes(count: content.count)
                    if let start = sampledIndexes.first, let end = sampledIndexes.last {
                        let blocks = try pack.getBlocks(startBlock: start, endBlock: end)
                        let expected = Array(content[start...end])
                        expect(blocks.count).to(equal(expected.count))
                        for (block, expectedBlock) in zip(blocks, expected) {
                            expect((block as NSDictionary).isEqual(expectedBlock)).to(beTrue())
                        }
                    }

                    let clampedStart = try pack.getBlocks(startBlock: -10, endBlock: 0)
                    expect(clampedStart.count).to(equal(1))
                    if let block = clampedStart.first {
                        expect((block as NSDictionary).isEqual(content[0])).to(beTrue())
                    }

                    let clampedEnd = try pack.getBlocks(startBlock: content.count - 1, endBlock: content.count + 10)
                    expect(clampedEnd.count).to(equal(1))
                    if let block = clampedEnd.first {
                        expect((block as NSDictionary).isEqual(content[content.count - 1])).to(beTrue())
                    }

                    expect(try pack.getBlocks(startBlock: 1, endBlock: 0)).to(beEmpty())
                    expect(try pack.getBlocks(startBlock: content.count, endBlock: content.count + 1)).to(beEmpty())
                }

                func firstContentNestedRef(in content: [[String: Any]]) -> [Int]? {
                    for (index, block) in content.enumerated() {
                        if let ref = firstNodeNestedRef(in: block, ref: [index]) {
                            return ref
                        }
                    }
                    return nil

                    func firstNodeNestedRef(in node: [String: Any], ref: [Int]) -> [Int]? {
                        guard let content = node["content"] as? [[String: Any]] else { return nil }
                        for (index, child) in content.enumerated() {
                            let childRef = ref + [index]
                            if child["text"] == nil {
                                return childRef
                            }
                            if let ref = firstNodeNestedRef(in: child, ref: childRef) {
                                return ref
                            }
                        }
                        return nil
                    }
                }

                func node(in content: [[String: Any]], at ref: [Int]) -> [String: Any]? {
                    guard let first = ref.first, first >= 0, first < content.count else { return nil }
                    var node: [String: Any] = content[first]
                    for index in ref.dropFirst() {
                        guard let children = node["content"] as? [[String: Any]], index >= 0, index < children.count else {
                            return nil
                        }
                        node = children[index]
                    }
                    return node
                }
            }

            func assertPageBlocksAccess(in pack: SDTPack, materialized: [String: Any]) throws {
                guard let catalog = materialized["catalog"] as? [String: Any],
                      let pages = catalog["pages"] as? [[String: Any]],
                      let content = materialized["content"] as? [[String: Any]] else {
                    fail("missing materialized catalog pages or content")
                    return
                }

                expect(pack.getTopLevelBlockCount()).to(equal(content.count))
                for pageIndex in sampleIndexes(count: pages.count) {
                    let blocks = try pack.getPageBlocks(pageIndex: pageIndex)
                    let expected = expectedPageBlocks(pages: pages, content: content, pageIndex: pageIndex)
                    expect(blocks.count).to(equal(expected.count))
                    for (block, expectedBlock) in zip(blocks, expected) {
                        expect((block as NSDictionary).isEqual(expectedBlock)).to(beTrue())
                    }
                }

                expect(try pack.getPageBlocks(pageIndex: -1)).to(beEmpty())
                expect(try pack.getPageBlocks(pageIndex: pages.count)).to(beEmpty())

                func expectedPageBlocks(pages: [[String: Any]], content: [[String: Any]], pageIndex: Int) -> [[String: Any]] {
                    guard pageIndex >= 0, pageIndex < pages.count,
                          let span = expectedContentRangeBlockSpan(pages[pageIndex]["contentRange"], topLevelBlockCount: content.count),
                          span.startIndex < span.endIndexExclusive else {
                        return []
                    }
                    return Array(content[span.startIndex..<span.endIndexExclusive])

                    func expectedContentRangeBlockSpan(_ value: Any?, topLevelBlockCount: Int) -> (startIndex: Int, endIndexExclusive: Int)? {
                        guard let range = value as? [Any],
                              range.count == 2,
                              let start = expectedContentBoundary(range[0]),
                              let end = expectedContentBoundary(range[1]),
                              let startIndex = expectedBoundaryTopLevelIndex(start, topLevelBlockCount: topLevelBlockCount) else {
                            return nil
                        }
                        if start == end {
                            return (startIndex, startIndex)
                        }
                        guard let endIndexExclusive = expectedBoundaryEndIndexExclusive(end, topLevelBlockCount: topLevelBlockCount) else {
                            return nil
                        }
                        return (startIndex, max(startIndex, endIndexExclusive))

                        func expectedContentBoundary(_ value: Any?) -> [Int]? {
                            guard let values = value as? [Any], !values.isEmpty else { return nil }
                            var boundary: [Int] = []
                            for value in values {
                                let intValue: Int?
                                if let value = value as? Int {
                                    intValue = value
                                } else if let value = value as? NSNumber {
                                    intValue = value.intValue
                                } else {
                                    intValue = nil
                                }
                                guard let intValue, intValue >= 0 else { return nil }
                                boundary.append(intValue)
                            }
                            return boundary
                        }

                        func expectedBoundaryTopLevelIndex(_ boundary: [Int], topLevelBlockCount: Int) -> Int? {
                            guard let index = boundary.first, index <= topLevelBlockCount else { return nil }
                            return index
                        }

                        func expectedBoundaryEndIndexExclusive(_ boundary: [Int], topLevelBlockCount: Int) -> Int? {
                            guard let index = expectedBoundaryTopLevelIndex(boundary, topLevelBlockCount: topLevelBlockCount) else { return nil }
                            if index == topLevelBlockCount {
                                return topLevelBlockCount
                            }
                            return boundary.count == 1 ? index : index + 1
                        }
                    }
                }
            }

            func sampleIndexes(count: Int) -> [Int] {
                guard count > 0 else { return [] }
                return Array(Set([0, count / 2, count - 1])).sorted()
            }

            func process(updates: [DocumentWorkerController.Update.Kind], ignoreKeys: Set<String> = [], jsonURL: URL) {
                for (index, update) in updates.enumerated() {
                    switch update {
                    case .queued:
                        expect(index).to(equal(0))

                    case .inProgress:
                        expect(index).to(equal(1))

                    case .extractedData(let data, _):
                        expect(index).to(equal(2))
                        let expectedData = try! Data(contentsOf: jsonURL)
                        let expectedJSONData = try! JSONSerialization.jsonObject(with: expectedData, options: .allowFragments) as! [String: Any]
                        compareJSONObjects(actual: data, expected: expectedJSONData, ignoreKeys: ignoreKeys, context: jsonURL.lastPathComponent)

                    default:
                        fail("unexpected update \(index): \(update)")
                    }
                }

                func compareJSONObjects(actual: [String: Any], expected: [String: Any], ignoreKeys: Set<String>, context: String) {
                    let actualKeys = Set(actual.keys).subtracting(ignoreKeys)
                    let expectedKeys = Set(expected.keys).subtracting(ignoreKeys)
                    expect(actualKeys).to(equal(expectedKeys))
                    for key in expectedKeys {
                        compareJSONValues(actual: actual[key], expected: expected[key], ignoreKeys: ignoreKeys, context: "\(context).\(key)")
                    }
                }

            func compareJSONValues(actual: Any?, expected: Any?, ignoreKeys: Set<String>, context: String) {
                    if let expected = expected as? [String: Any] {
                        guard let actual = actual as? [String: Any] else {
                            fail("expected object at \(context), got \(String(describing: actual))")
                            return
                        }
                        compareJSONObjects(actual: actual, expected: expected, ignoreKeys: ignoreKeys, context: context)
                        return
                    }

                    if let expected = expected as? [Any] {
                        guard let actual = actual as? [Any] else {
                            fail("expected array at \(context), got \(String(describing: actual))")
                            return
                        }
                        expect(actual.count).to(equal(expected.count), description: context)
                        guard actual.count == expected.count else { return }
                        for index in expected.indices {
                            compareJSONValues(actual: actual[index], expected: expected[index], ignoreKeys: ignoreKeys, context: "\(context)[\(index)]")
                        }
                        return
                    }

                    if expected is NSNull {
                        expect(actual as? NSNull).toNot(beNil(), description: context)
                        return
                    }

                    if let expected = expected as? String {
                        if context.hasSuffix(".text") {
                            expect((actual as? String)?.replacingOccurrences(of: "\n", with: " ")).to(equal(expected.replacingOccurrences(of: "\n", with: " ")), description: context)
                        } else {
                            expect(actual as? String).to(equal(expected), description: context)
                        }
                        return
                    }

                    if let expected = expected as? NSNumber {
                        expect(actual as? NSNumber).to(equal(expected), description: context)
                        return
                    }

                    expect(actual as? AnyHashable).to(equal(expected as? AnyHashable), description: context)
                }
            }

            func prepareTemporaryDocumentWorkerDirectory() throws -> File {
                guard let workerHtmlUrl = Bundle.main.url(forResource: "document_worker", withExtension: "html") else {
                    fail("document_worker.html not found")
                    throw DocumentWorkerWebViewHandler.Error.cantFindWorkFile
                }
                guard let bundledWorkerUrl = Bundle.main.url(forResource: "document_worker", withExtension: nil, subdirectory: "Bundled") else {
                    fail("bundled document_worker directory not found")
                    throw DocumentWorkerWebViewHandler.Error.cantFindWorkFile
                }

                let temporaryDirectory = Files.temporaryDirectory
                let temporaryDirectoryUrl = temporaryDirectory.createUrl()
                try FileManager.default.createDirectory(at: temporaryDirectoryUrl, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: workerHtmlUrl, to: temporaryDirectory.copy(withName: "document_worker", ext: "html").createUrl())

                let contents = try FileManager.default.contentsOfDirectory(at: bundledWorkerUrl, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                for url in contents {
                    let destination = temporaryDirectoryUrl.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: destination)
                }

                return temporaryDirectory
            }
        }

        afterSuite {
            try? TestControllers.fileStorage.remove(Files.downloads)
        }
    }
}

private final class TestDocumentWorkerWebViewProvider: WebViewProvider {
    private var webViews: [WKWebView] = []

    func addWebView(configuration: WKWebViewConfiguration?) -> WKWebView {
        let webView = configuration.map { WKWebView(frame: .zero, configuration: $0) } ?? WKWebView(frame: .zero)
        webViews.append(webView)
        return webView
    }
}
