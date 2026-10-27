//
//  CarPlayHtmlEpubReadAloudSession.swift
//  Zotero
//
//  Created by Michal Rentka on 13.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import WebKit

import CocoaLumberjackSwift
import RxCocoa
import RxSwift

/// HTML/EPUB reader loaded in a web view which is never shown. It provides read aloud segments and maps positions the same
/// way as `HtmlEpubDocumentViewController` does for the visible reader.
final class CarPlayHtmlEpubReader {
    /// Size of the hidden web view, so that the document is laid out like in a reader.
    private static let size = CGSize(width: 1024, height: 768)

    private unowned let fileStorage: FileStorage
    /// Temporary directory with reader files and a copy of the document, like the reader uses.
    private let directory: File
    private let documentFile: File
    private let webView: WKWebView
    private let webViewHandler: WebViewHandler
    private let disposeBag: DisposeBag
    /// Script creating the document view, called once the reader is initialized.
    private var createViewJavascript: String?
    /// Whether the document view is ready to answer requests.
    private var isViewReady: Bool
    private var actionsWaitingForView: [() -> Void]
    private var readAloudSegmentRequests: [Int: ([SpeechReaderSegment]?) -> Void] = [:]
    private var readAloudStartBlockIndexRequests: [Int: (Int?) -> Void] = [:]
    private var sourceSDTPositionRequests: [Int: (SDTPosition?) -> Void] = [:]
    private var sdtSourcePositionRequests: [Int: (ReaderSourcePosition?) -> Void] = [:]
    private var nextRequestID = 0

    init(file: File, fileStorage: FileStorage, webViewProvider: WebViewProvider?) throws {
        guard let readerURL = Bundle.main.url(forResource: "reader", withExtension: nil, subdirectory: "Bundled") else {
            throw HtmlEpubReaderState.Error.incompatibleDocument
        }

        // Reader files and document files (in case of snapshot there can be multiple files) are copied to one directory, so that
        // the reader can access everything.
        let directory = Files.temporaryDirectory
        let documentFile = directory.appending(relativeComponent: "content").copy(withName: file.name, ext: file.ext)
        let readerFiles: [File] = try fileStorage.contentsOfDirectory(at: Files.file(from: readerURL))
        for readerFile in readerFiles {
            try fileStorage.copy(from: readerFile, to: directory.copy(withName: readerFile.name, ext: readerFile.ext))
        }
        let documentFiles: [File] = try fileStorage.contentsOfDirectory(at: file.directory)
        for documentFilePart in documentFiles {
            try fileStorage.copy(from: documentFilePart, to: documentFile.copy(withName: documentFilePart.name, ext: documentFilePart.ext))
        }

        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        // The app's hidden web view host is used when the app's window exists. Without it (CarPlay only) the web view isn't in any window.
        let webView = webViewProvider?.addWebView(configuration: configuration) ?? WKWebView(frame: .zero, configuration: configuration)
        webView.frame = CGRect(origin: .zero, size: Self.size)

        self.fileStorage = fileStorage
        self.directory = directory
        self.documentFile = documentFile
        self.webView = webView
        webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: HtmlEpubDocumentViewController.JSHandlers.allCases.map({ $0.rawValue }))
        isViewReady = false
        actionsWaitingForView = []
        disposeBag = DisposeBag()

        webViewHandler.receivedMessageHandler = { [weak self] handler, message in
            self?.process(handler: handler, message: message)
        }
    }

    deinit {
        webView.removeFromSuperview()
        try? fileStorage.remove(directory)
    }

    /// Loads the reader and opens the document at `page` (raw page value stored for the document).
    func load(page rawPage: String) {
        let type: String
        var viewState = "scale: 1"
        switch documentFile.ext.lowercased() {
        case "epub":
            type = "epub"
            viewState += ", cfi: '\(rawPage)'"

        default:
            type = "snapshot"
            if let scrollYPercent = Double(rawPage) {
                viewState += ", scrollYPercent: \(scrollYPercent)"
            }
        }
        let url = documentFile.createUrl().absoluteString.replacingOccurrences(of: "'", with: #"\'"#)
        let annotations = WebViewEncoder.encodeAsJSONForJavascript([[String: Any]]())
        createViewJavascript = "createView({ type: '\(type)', url: '\(url)', annotations: \(annotations), viewState: {\(viewState)}});"

        webViewHandler.load(fileUrl: directory.copy(withName: "view", ext: "html").createUrl())
            .subscribe(onFailure: { error in
                DDLogError("CarPlayHtmlEpubReader: can't load reader - \(error)")
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Read Aloud

    /// Hands the structured-document-text pack to the reader and fetches its read aloud segments, once the document view is ready.
    func readAloudSegments(sdtPackData: Data, packVersion: Int, schemaMajorVersion: Int, completion: @escaping ([SpeechReaderSegment]?) -> Void) {
        performWhenViewReady { [weak self] in
            guard let self else { return }
            call(javascript: "setSDTPack({ bytes: \(WebViewEncoder.encodeForJavascript(sdtPackData)), packVersion: \(packVersion), schemaMajorVersion: \(schemaMajorVersion) });", onFailure: nil)
            let requestID = createRequestID()
            readAloudSegmentRequests[requestID] = completion
            call(javascript: "getReadAloudSegments({ granularity: 'sentence', requestID: \(requestID) });") { [weak self] in
                self?.readAloudSegmentRequests.removeValue(forKey: requestID)?(nil)
            }
        }
    }

    func readAloudStartBlockIndex(completion: @escaping (Int?) -> Void) {
        performWhenViewReady { [weak self] in
            guard let self else { return }
            let requestID = createRequestID()
            readAloudStartBlockIndexRequests[requestID] = completion
            call(javascript: "getReadAloudStartBlockIndex({ requestID: \(requestID) });") { [weak self] in
                self?.readAloudStartBlockIndexRequests.removeValue(forKey: requestID)?(nil)
            }
        }
    }

    func mapSDTPosition(forSourcePosition source: ReaderSourcePosition, completion: @escaping (SDTPosition?) -> Void) {
        performWhenViewReady { [weak self] in
            guard let self else { return }
            let requestID = createRequestID()
            sourceSDTPositionRequests[requestID] = completion
            call(javascript: "sourceToSDTPosition({ position: \(WebViewEncoder.encodeAsJSONForJavascript(source)), requestID: \(requestID) });") { [weak self] in
                self?.sourceSDTPositionRequests.removeValue(forKey: requestID)?(nil)
            }
        }
    }

    func mapSourcePosition(forSDTPosition position: SDTPosition, completion: @escaping (ReaderSourcePosition?) -> Void) {
        performWhenViewReady { [weak self] in
            guard let self else { return }
            let requestID = createRequestID()
            sdtSourcePositionRequests[requestID] = completion
            let anchor: [String: Any] = ["start": position.start, "end": position.end]
            call(javascript: "sdtAnchorToPosition({ anchor: \(WebViewEncoder.encodeAsJSONForJavascript(anchor)), requestID: \(requestID) });") { [weak self] in
                self?.sdtSourcePositionRequests.removeValue(forKey: requestID)?(nil)
            }
        }
    }

    // MARK: - Helpers

    private func performWhenViewReady(_ action: @escaping () -> Void) {
        if isViewReady {
            action()
        } else {
            actionsWaitingForView.append(action)
        }
    }

    private func createRequestID() -> Int {
        let requestID = nextRequestID
        nextRequestID += 1
        return requestID
    }

    private func call(javascript: String, onFailure: (() -> Void)?) {
        webViewHandler.call(javascript: javascript)
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { error in
                DDLogError("CarPlayHtmlEpubReader: javascript call failed - \(error)")
                onFailure?()
            })
            .disposed(by: disposeBag)
    }

    private func process(handler: String, message: Any) {
        switch handler {
        case HtmlEpubDocumentViewController.JSHandlers.log.rawValue:
            DDLogInfo("CarPlayHtmlEpubReader: JSLOG \(message)")

        case HtmlEpubDocumentViewController.JSHandlers.text.rawValue:
            guard let data = message as? [String: Any], let event = data["event"] as? String else {
                DDLogWarn("CarPlayHtmlEpubReader: unknown message - \(message)")
                return
            }
            let params = data["params"] as? [String: Any]
            let requestID = params?["requestID"] as? Int

            switch event {
            case "onInitialized":
                guard let createViewJavascript else { return }
                call(javascript: createViewJavascript, onFailure: nil)

            case "onViewContentInitialized":
                isViewReady = true
                let actions = actionsWaitingForView
                actionsWaitingForView = []
                actions.forEach({ $0() })

            case "onReadAloudSegments":
                guard let requestID else { return }
                let segments = (params?["segments"] as? [[String: Any]])?.compactMap(HtmlEpubDocumentViewController.parseReaderSegment)
                readAloudSegmentRequests.removeValue(forKey: requestID)?(segments)

            case "onReadAloudStartBlockIndex":
                guard let requestID else { return }
                readAloudStartBlockIndexRequests.removeValue(forKey: requestID)?((params?["blockIndex"] as? NSNumber)?.intValue)

            case "onSDTPosition":
                guard let requestID else { return }
                sdtSourcePositionRequests.removeValue(forKey: requestID)?(params?["position"] as? ReaderSourcePosition)

            case "onSourceSDTPosition":
                guard let requestID else { return }
                sourceSDTPositionRequests.removeValue(forKey: requestID)?(HtmlEpubDocumentViewController.parseSDTPosition(params?["position"]))

            default:
                break
            }

        default:
            break
        }
    }
}

final class CarPlayHtmlEpubReadAloudSession {
    let key: String
    let libraryId: LibraryIdentifier
    let documentTitle: String?
    let documentAuthors: String?
    let documentFile: FileData?
    private let reader: CarPlayHtmlEpubReader
    private let dbStorage: DbStorage
    let remoteVoicesController: RemoteVoicesController
    private let positionStore: CarPlayReadAloudPositionStore
    private let disposeBag: DisposeBag
    private var speechManager: SpeechManager<CarPlayHtmlEpubReadAloudSession>!

    init(
        key: String,
        libraryId: LibraryIdentifier,
        file: FileData,
        title: String?,
        authors: String?,
        dbStorage: DbStorage,
        fileStorage: FileStorage,
        lastReadWatcher: LastReadWatcher,
        speechPlaybackOwnership: SpeechPlaybackOwnership,
        documentWorkerController: DocumentWorkerController,
        documentPreviewController: DocumentPreviewController,
        apiClient: ApiClient
    ) throws {
        self.key = key
        self.libraryId = libraryId
        self.dbStorage = dbStorage
        documentFile = file
        documentTitle = title
        documentAuthors = authors
        reader = try CarPlayHtmlEpubReader(file: file, fileStorage: fileStorage, webViewProvider: documentWorkerController.webViewProvider)
        remoteVoicesController = RemoteVoicesController(apiClient: apiClient)
        positionStore = CarPlayReadAloudPositionStore(key: key, libraryId: libraryId, dbStorage: dbStorage)
        disposeBag = DisposeBag()

        speechManager = SpeechManager<CarPlayHtmlEpubReadAloudSession>.carPlay(
            delegate: self,
            key: key,
            libraryId: libraryId,
            dbStorage: dbStorage,
            speechPlaybackOwnership: speechPlaybackOwnership,
            remoteVoicesController: remoteVoicesController,
            documentWorkerController: documentWorkerController,
            documentPreviewController: documentPreviewController
        )
        speechManager.observeReading(key: key, libraryId: libraryId, positionStore: positionStore, lastReadWatcher: lastReadWatcher, disposeBag: disposeBag)
    }
}

extension CarPlayHtmlEpubReadAloudSession: CarPlayReadAloudSession {
    var state: BehaviorRelay<SpeechState> {
        return speechManager.state
    }

    var onPlaybackTakenOver: (() -> Void)? {
        get { speechManager.onPlaybackTakenOver }
        set { speechManager.onPlaybackTakenOver = newValue }
    }

    var extractionProgress: BehaviorRelay<Double?> {
        return speechManager.extractionProgress
    }

    /// Opens the document where the reader was last left and starts reading where reading aloud of this document last left
    /// off, otherwise where the reader was last left.
    func start() {
        let defaultPageValue = documentFile?.ext.lowercased() == "epub" ? "_start" : "0"
        let documentData = CarPlayReadAloudSessionHelper.documentData(key: key, libraryId: libraryId, defaultPageValue: defaultPageValue, dbStorage: dbStorage)
        reader.load(page: documentData?.page ?? defaultPageValue)
        if let position = documentData?.lastReadAloudPosition {
            speechManager.start(.resume(position))
        } else {
            speechManager.start(.currentPage)
        }
    }

    func startFromBeginning() {
        speechManager.start(.documentStart)
    }

    func stop() {
        speechManager.stop()
        positionStore.flush()
    }

    var voice: SpeechVoice? {
        return speechManager.voice
    }

    var language: String? {
        return speechManager.language
    }

    var detectedLanguage: String {
        return speechManager.detectedLanguage
    }

    func pause() {
        speechManager.pause()
    }

    func resume() {
        speechManager.resume()
    }

    func apply(voiceChange: ReadAloudVoiceChange) {
        speechManager.apply(voiceChange: voiceChange, key: key, libraryId: libraryId, dbStorage: dbStorage)
    }
}

/// Same as `HtmlEpubReaderViewController`: the whole document is a single structured-document-text page and the reader
/// provides the read aloud segments.
extension CarPlayHtmlEpubReadAloudSession: SpeechManagerDelegate {
    var documentPassword: String? {
        return nil
    }

    func getCurrentPageIndex() -> Int {
        return 0
    }

    func getNextPageIndex(from currentPageIndex: Int) -> Int? {
        return nil
    }

    func getPreviousPageIndex(from currentPageIndex: Int) -> Int? {
        return nil
    }

    func pageIndex(forStructuredDocumentTextPage page: Int) -> Int? {
        return page == 0 ? 0 : nil
    }

    func structuredDocumentTextPage(forPageIndex pageIndex: Int) -> Int? {
        return pageIndex == 0 ? 0 : nil
    }

    func moved(to pageIndex: Int, from previousPageIndex: Int) {}

    func focusPage(_ pageIndex: Int) {}

    func readAloudReaderSegments(sdtPackData: Data, packVersion: Int, schemaMajorVersion: Int, completion: @escaping ([SpeechReaderSegment]?) -> Void) {
        reader.readAloudSegments(sdtPackData: sdtPackData, packVersion: packVersion, schemaMajorVersion: schemaMajorVersion, completion: completion)
    }

    func readAloudVisibleStartBlockIndex(completion: @escaping (Int?) -> Void) {
        reader.readAloudStartBlockIndex(completion: completion)
    }

    func mapSDTPosition(forSourcePosition source: ReaderSourcePosition, completion: @escaping (SDTPosition?) -> Void) {
        reader.mapSDTPosition(forSourcePosition: source, completion: completion)
    }

    func mapSourcePosition(forSDTPosition position: SDTPosition, completion: @escaping (ReaderSourcePosition?) -> Void) {
        reader.mapSourcePosition(forSDTPosition: position, completion: completion)
    }

    // There is no document to highlight in and highlight sessions can't be started without a reader.

    func readAloudHighlightChanged(position: ReadAloudPosition, pageIndex: Int) {}

    func annotationPreviewChanged(position: ReadAloudPosition, pageIndex: Int, tool: AnnotationTool, color: String) {}

    func createAnnotation(ofType tool: AnnotationTool, color: String, position: ReadAloudPosition, onPage pageIndex: Int) {}

    func clearAnnotationPreview() {}
}
