//
//  HtmlEpubDocumentViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 05.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

class HtmlEpubDocumentViewController: UIViewController {
    enum JSHandlers: String, CaseIterable {
        case text = "textHandler"
        case log = "logHandler"
    }

    /// State of an active read-aloud highlight session. The annotation is created by the reader, so that the user sees it
    /// while the session is active, but it's stored in the database only when the session ends. The latest annotation
    /// reported by the reader is therefore kept here, because the reader's own (debounced) saves are ignored.
    private struct ReadAloudAnnotationSession {
        enum PendingEnd {
            case store
            case discard
        }

        /// Key assigned to the annotation by the reader. `nil` until the reader responds to the first request.
        var key: String?
        /// Latest annotation reported by the reader.
        var annotation: [String: Any]?
        /// Identifier of the request which is currently in flight, `nil` when the reader responded to all requests.
        var requestID: Int?
        /// Latest params requested while a request was in flight. Sent as soon as the reader responds.
        var pendingParams: [String: Any]?
        /// Set when the session ended while a request was in flight. Performed as soon as the reader responds.
        var pendingEnd: PendingEnd?
    }

    private let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var webView: WKWebView!
    private var webViewHandler: WebViewHandler!
    var containerInsets: NSDirectionalEdgeInsets? {
        didSet {
            applyContainerInsetsIfInitialized()
        }
    }
    private var isReaderInitialized: Bool
    /// Pending read-aloud bridge requests, keyed by the `requestID` sent to the reader and resolved on the matching
    /// response event (`onReadAloudSegments` / `onReadAloudStartBlockIndex`).
    private var readAloudSegmentRequests: [Int: ([SpeechReaderSegment]?) -> Void] = [:]
    private var readAloudStartBlockIndexRequests: [Int: (Int?) -> Void] = [:]
    private var nextReadAloudRequestID = 0
    private var readAloudAnnotationSession: ReadAloudAnnotationSession?
    weak var parentDelegate: HtmlEpubReaderContainerDelegate?

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        self.viewModel = viewModel
        disposeBag = DisposeBag()
        isReaderInitialized = false
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .systemBackground
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        observeViewModel()
        setupWebView()
        viewModel.process(action: .initialiseReader)

        func observeViewModel() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] state in
                    self?.process(state: state)
                })
                .disposed(by: disposeBag)
        }

        func setupWebView() {
            let highlightAction = UIAction(title: L10n.Pdf.highlight) { [weak self] _ in
                self?.viewModel.process(action: .createAnnotationFromSelection(.highlight))
                self?.deselectText()
            }
            let underlineAction = UIAction(title: L10n.Pdf.underline) { [weak self] _ in
                self?.viewModel.process(action: .createAnnotationFromSelection(.underline))
                self?.deselectText()
            }

            let configuration = WKWebViewConfiguration()
            configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            let webView = HtmlEpubWebView(customMenuActions: [highlightAction, underlineAction], configuration: configuration)
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.isOpaque = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            if #available(iOS 16.4, *) {
                webView.isInspectable = true
            }
            view.addSubview(webView)

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: webView.topAnchor),
                view.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
            ])
            self.webView = webView
            webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
            webViewHandler.receivedMessageHandler = { [weak self] handler, message in
                self?.process(handler: handler, message: message)
            }
        }
    }

    // MARK: - Actions

    func show(location: [String: Any]) {
        webViewHandler.call(javascript: "navigate({ location: \(WebViewEncoder.encodeAsJSONForJavascript(location)) });").subscribe().disposed(by: disposeBag)
    }

    func selectSearchResult(index: Int) {
        webViewHandler.call(javascript: "window._view.find({ index: \(index) });").subscribe().disposed(by: disposeBag)
    }

    func clearSearch() {
        webViewHandler.call(javascript: "window._view.find();").subscribe().disposed(by: disposeBag)
    }

    private func deselectText() {
        webViewHandler.call(javascript: "window._view.selectAnnotations([]);").subscribe().disposed(by: disposeBag)
    }

    // MARK: - Read Aloud

    /// Hands the structured-document-text pack to the reader so it can serve `getReadAloudSegments` and create
    /// annotations from SDT positions. Fire-and-forget.
    func setSDTPack(bytes: Data, packVersion: Int, schemaMajorVersion: Int) {
        webViewHandler.call(javascript: "setSDTPack({ bytes: \(WebViewEncoder.encodeForJavascript(bytes)), packVersion: \(packVersion), schemaMajorVersion: \(schemaMajorVersion) });")
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { error in
                DDLogError("HtmlEpubDocumentViewController: setting SDT pack failed - \(error)")
            })
            .disposed(by: disposeBag)
    }

    /// Fetches the reader's read-aloud segments (text + reader SDT position + paragraph-start flag) at the given
    /// granularity. Resolved asynchronously via the `onReadAloudSegments` event, keyed by `requestID`.
    func getReadAloudSegments(granularity: String, completion: @escaping ([SpeechReaderSegment]?) -> Void) {
        let requestID = nextReadAloudRequestID
        nextReadAloudRequestID += 1
        readAloudSegmentRequests[requestID] = completion
        webViewHandler.call(javascript: "getReadAloudSegments({ granularity: '\(granularity)', requestID: \(requestID) });")
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { [weak self] error in
                DDLogError("HtmlEpubDocumentViewController: getting read aloud segments failed - \(error)")
                self?.readAloudSegmentRequests.removeValue(forKey: requestID)?(nil)
            })
            .disposed(by: disposeBag)
    }

    /// Fetches the structured-document-text block index currently in view (read fresh, so read-aloud can start where the
    /// reader is). Resolved asynchronously via the `onReadAloudStartBlockIndex` event, keyed by `requestID`.
    func getReadAloudStartBlockIndex(completion: @escaping (Int?) -> Void) {
        let requestID = nextReadAloudRequestID
        nextReadAloudRequestID += 1
        readAloudStartBlockIndexRequests[requestID] = completion
        webViewHandler.call(javascript: "getReadAloudStartBlockIndex({ requestID: \(requestID) });")
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { [weak self] error in
                DDLogError("HtmlEpubDocumentViewController: getting read aloud start block index failed - \(error)")
                self?.readAloudStartBlockIndexRequests.removeValue(forKey: requestID)?(nil)
            })
            .disposed(by: disposeBag)
    }

    /// Creates or resizes/restyles the highlight-session annotation spanning `sdtStart`…`sdtEnd`. The annotation is only
    /// rendered in the document while the session is active, it's stored in the database when the session ends
    /// (`endReadAloudAnnotationSession(store: true)`).
    ///
    /// The first call of a session starts it. Only one request can be in flight at a time, because the reader assigns the
    /// annotation key and it has to be known before the annotation can be resized instead of created again. While a
    /// request is in flight only the latest requested range is remembered and sent when the reader responds.
    func setReadAloudAnnotation(type: AnnotationTool, color: String, sdtStart: [Int], sdtEnd: [Int]) {
        let readerType: String
        switch type {
        case .highlight:
            readerType = "highlight"

        case .underline:
            readerType = "underline"

        case .eraser, .image, .ink, .freeText, .note:
            return
        }
        // The reader uses `startPosition.start` and `endPosition.end`; the two inner endpoints are unused.
        let params: [String: Any] = [
            "type": readerType,
            "color": color,
            "startPosition": ["start": sdtStart, "end": sdtStart],
            "endPosition": ["start": sdtEnd, "end": sdtEnd]
        ]

        if var session = readAloudAnnotationSession {
            guard session.pendingEnd == nil else { return }
            if session.requestID != nil {
                session.pendingParams = params
                readAloudAnnotationSession = session
                return
            }
            send(readAloudAnnotationParams: params)
            return
        }

        // The session has to be started in the view model before the reader is asked to create the annotation, so that
        // its saves are ignored. The reader can report them synchronously, before it responds with the annotation.
        readAloudAnnotationSession = ReadAloudAnnotationSession()
        viewModel.process(action: .startReadAloudAnnotationSession)
        send(readAloudAnnotationParams: params)
    }

    private func send(readAloudAnnotationParams params: [String: Any]) {
        guard var session = readAloudAnnotationSession else { return }
        var params = params
        if let key = session.key {
            params["id"] = key
        }
        let requestID = nextReadAloudRequestID
        nextReadAloudRequestID += 1
        session.requestID = requestID
        readAloudAnnotationSession = session
        webViewHandler.call(javascript: "setReadAloudAnnotation({ params: \(WebViewEncoder.encodeAsJSONForJavascript(params)), requestID: \(requestID) });")
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { [weak self] error in
                DDLogError("HtmlEpubDocumentViewController: setting read aloud annotation failed - \(error)")
                self?.process(readAloudAnnotation: nil, requestID: requestID)
            })
            .disposed(by: disposeBag)
    }

    /// Ends the highlight session. `store: true` stores the annotation reported by the reader in the database (the single
    /// write of a session), `store: false` discards it and removes it from the document.
    ///
    /// Called for both a confirmed and a discarded session, in this order, so the first call decides the outcome.
    func endReadAloudAnnotationSession(store: Bool) {
        guard var session = readAloudAnnotationSession, session.pendingEnd == nil else { return }

        if session.requestID != nil {
            // Wait for the reader to respond, otherwise the last change would be lost and the key of the annotation
            // which has to be removed from the document may not be known yet.
            session.pendingEnd = store ? .store : .discard
            session.pendingParams = nil
            readAloudAnnotationSession = session
            return
        }

        readAloudAnnotationSession = nil

        if !store, let key = session.key {
            webViewHandler.call(javascript: "unsetReadAloudAnnotation({ key: '\(key)' });")
                .subscribe(onFailure: { error in
                    DDLogError("HtmlEpubDocumentViewController: unsetting read aloud annotation failed - \(error)")
                })
                .disposed(by: disposeBag)
        }

        viewModel.process(action: .endReadAloudAnnotationSession(annotation: store ? session.annotation : nil, key: session.key))
    }

    /// Processes the reader's response to `setReadAloudAnnotation` - caches the annotation, so that it can be stored when
    /// the session ends, and performs whatever was requested while the request was in flight.
    private func process(readAloudAnnotation annotation: [String: Any]?, requestID: Int) {
        guard var session = readAloudAnnotationSession, session.requestID == requestID else { return }
        session.requestID = nil
        if let annotation, let key = annotation["id"] as? String {
            session.key = key
            session.annotation = annotation
        } else {
            DDLogWarn("HtmlEpubDocumentViewController: reader didn't create read aloud annotation")
        }
        readAloudAnnotationSession = session

        if let pendingEnd = session.pendingEnd {
            readAloudAnnotationSession?.pendingEnd = nil
            endReadAloudAnnotationSession(store: pendingEnd == .store)
            return
        }

        if let params = session.pendingParams {
            readAloudAnnotationSession?.pendingParams = nil
            send(readAloudAnnotationParams: params)
        }
    }

    /// Spotlights the currently-read segment (`sdtStart`…`sdtEnd`) in the reader. The reader maps the SDT position to a
    /// selector, draws the spotlight, and scrolls it into view if needed. Fire-and-forget.
    func setReadAloudSpotlight(sdtStart: [Int], sdtEnd: [Int]) {
        let anchor: [String: Any] = ["start": sdtStart, "end": sdtEnd]
        webViewHandler.call(javascript: "setReadAloudSpotlight({ anchor: \(WebViewEncoder.encodeAsJSONForJavascript(anchor)) });")
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { error in
                DDLogError("HtmlEpubDocumentViewController: setting read aloud spotlight failed - \(error)")
            })
            .disposed(by: disposeBag)
    }

    /// Clears the read-aloud spotlight in the reader.
    func clearReadAloudSpotlight() {
        webViewHandler.call(javascript: "setReadAloudSpotlight({});")
            .subscribe(onFailure: { error in
                DDLogError("HtmlEpubDocumentViewController: clearing read aloud spotlight failed - \(error)")
            })
            .disposed(by: disposeBag)
    }

    /// Parses a reader read-aloud segment JSON dictionary into a `SpeechReaderSegment`.
    private static func parseReaderSegment(_ dictionary: [String: Any]) -> SpeechReaderSegment? {
        guard let text = dictionary["text"] as? String,
              let position = dictionary["position"] as? [String: Any],
              let start = intArray(position["start"]),
              let end = intArray(position["end"]) else { return nil }
        return SpeechReaderSegment(text: text, start: start, end: end, isParagraphStart: (dictionary["anchor"] as? String) == "paragraphStart")
    }

    /// Coerces a JS number array (bridged as `[NSNumber]`) into `[Int]`.
    private static func intArray(_ value: Any?) -> [Int]? {
        return (value as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }
    }

    private func process(state: HtmlEpubReaderState) {
        if state.changes.contains(.readerInitialised) {
            setWebViewInterfaceStyle(to: state.settings.appearance, userInterfaceStyle: state.interfaceStyle)
            webViewHandler.load(fileUrl: state.readerFile.createUrl()).subscribe().disposed(by: disposeBag)
            return
        }

        if let data = state.documentData {
            load(documentData: data)
            return
        }

        if let update = state.documentUpdate {
            updateView(modifications: update.modifications, insertions: update.insertions, deletions: update.deletions)
        }

        if let term = state.documentSearchTerm {
            search(term: term)
        }

        if let key = state.focusDocumentKey {
            selectInDocument(key: key)
        }

        if state.changes.contains(.activeTool) || state.changes.contains(.toolColor) {
            let tool = state.activeTool
            let color = tool.flatMap({ state.toolColors[$0] })

            if let tool, let color {
                set(tool: (tool, color))
            } else {
                set(tool: nil)
            }
        }

        if state.changes.contains(.appearance) {
            updateInterface(to: state.settings.appearance, userInterfaceStyle: state.interfaceStyle)
        }

        func search(term: String) {
            webViewHandler.call(javascript: "search({ term: \(WebViewEncoder.encodeForJavascript(term.data(using: .utf8))) });")
                .observe(on: MainScheduler.instance)
                .subscribe(onFailure: { error in
                    DDLogError("HtmlEpubDocumentViewController: searching document failed - \(error)")
                })
                .disposed(by: disposeBag)
        }

        func selectInDocument(key: String) {
            webViewHandler.call(javascript: "select({ key: '\(key)' });")
                .observe(on: MainScheduler.instance)
                .subscribe(onFailure: { error in
                    DDLogError("HtmlEpubDocumentViewController: navigating to \(key) failed - \(error)")
                })
                .disposed(by: disposeBag)
        }

        func updateView(modifications: [[String: Any]], insertions: [[String: Any]], deletions: [String]) {
            let encodedDeletions = WebViewEncoder.encodeAsJSONForJavascript(deletions)
            let encodedInsertions = WebViewEncoder.encodeAsJSONForJavascript(insertions)
            let encodedModifications = WebViewEncoder.encodeAsJSONForJavascript(modifications)
            webViewHandler.call(javascript: "updateAnnotations({ deletions: \(encodedDeletions), insertions: \(encodedInsertions), modifications: \(encodedModifications)});")
                .observe(on: MainScheduler.instance)
                .subscribe(onFailure: { error in
                    DDLogError("HtmlEpubDocumentViewController: updating document failed - \(error)")
                })
                .disposed(by: disposeBag)
        }

        func load(documentData data: HtmlEpubReaderState.DocumentData) {
            DDLogInfo("HtmlEpubDocumentViewController: try creating view for \(data.type); page = \(String(describing: data.page))")
            DDLogInfo("URL: \(data.url.absoluteString)")
            let appearance = Appearance.from(appearanceMode: state.settings.appearance, interfaceStyle: state.interfaceStyle)
            setWebViewInterfaceStyle(to: state.settings.appearance, userInterfaceStyle: state.interfaceStyle)
            var javascript = "createView({ type: '\(data.type)', url: '\(data.url.absoluteString.replacingOccurrences(of: "'", with: #"\'"#))', annotations: \(data.annotationsJson), colorScheme: '\(appearance.htmlEpubValue)', \(appearance.htmlEpubThemeOption)"
            if let key = data.selectedAnnotationKey {
                javascript += ", location: {annotationID: '\(key)'}"
            } else if let page = data.page {
                switch page {
                case .html(let scrollYPercent):
                    javascript += ", viewState: {scrollYPercent: \(scrollYPercent), scale: 1}"

                case .epub(let cfi):
                    javascript += ", viewState: {cfi: '\(cfi)'}"
                }
            }
            javascript += "});"

            webViewHandler.call(javascript: javascript)
                .observe(on: MainScheduler.instance)
                .subscribe(onFailure: { error in
                    DDLogError("HtmlEpubDocumentViewController: loading document failed - \(error)")
                })
                .disposed(by: disposeBag)
        }
    }

    private func updateInterface(to appearanceMode: ReaderSettingsState.Appearance, userInterfaceStyle: UIUserInterfaceStyle) {
        setWebViewInterfaceStyle(to: appearanceMode, userInterfaceStyle: userInterfaceStyle)
        let appearance = Appearance.from(appearanceMode: appearanceMode, interfaceStyle: userInterfaceStyle)
        webView.call(javascript: appearanceJavascript(for: appearance)).subscribe().disposed(by: disposeBag)

        func appearanceJavascript(for appearance: Appearance) -> String {
            return "window._view.setColorScheme('\(appearance.htmlEpubValue)');window._view.setTheme('\(appearance.htmlEpubTheme)');"
        }
    }

    private func setWebViewInterfaceStyle(to appearanceMode: ReaderSettingsState.Appearance, userInterfaceStyle: UIUserInterfaceStyle) {
        let appearance = Appearance.from(appearanceMode: appearanceMode, interfaceStyle: userInterfaceStyle)
        switch appearanceMode {
        case .automatic:
            webView.overrideUserInterfaceStyle = userInterfaceStyle

        case .light, .sepia:
            webView.overrideUserInterfaceStyle = .light

        case .dark:
            webView.overrideUserInterfaceStyle = .dark
        }
        setReaderBackgroundColor(appearance.htmlEpubThemeColor)

        func setReaderBackgroundColor(_ color: UIColor) {
            view.backgroundColor = color
            webView?.backgroundColor = color
            webView?.scrollView.backgroundColor = color
            parentDelegate?.setReaderBackground(color: color)
        }
    }

    private func set(tool data: (AnnotationTool, UIColor)?) {
        guard let (tool, color) = data else {
            webViewHandler.call(javascript: "clearTool();").subscribe().disposed(by: disposeBag)
            return
        }

        let toolName: String
        switch tool {
        case .highlight:
            toolName = "highlight"

        case .note:
            toolName = "note"

        case .underline:
            toolName = "underline"

        case .eraser, .image, .ink, .freeText:
            return
        }
        webViewHandler.call(javascript: "setTool({ type: '\(toolName)', color: '\(color.hexString)' });").subscribe().disposed(by: disposeBag)
    }

    private func applyContainerInsetsIfInitialized() {
        guard let containerInsets, isReaderInitialized else { return }
        let javascript = "setContainerInsets({ top: \(containerInsets.top), right: \(containerInsets.trailing), bottom: \(containerInsets.bottom), left: \(containerInsets.leading) });"
        webViewHandler.call(javascript: javascript)
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { error in
                DDLogError("HtmlEpubDocumentViewController: setting container insets failed - \(error)")
            })
            .disposed(by: disposeBag)
    }

    private func process(handler: String, message: Any) {
        switch handler {
        case JSHandlers.log.rawValue:
            DDLogInfo("HtmlEpubDocumentViewController: JSLOG \(message)")

        case JSHandlers.text.rawValue:
            guard let data = message as? [String: Any], let event = data["event"] as? String else {
                DDLogWarn("HtmlEpubDocumentViewController: unknown message - \(message)")
                return
            }

            DDLogInfo("HtmlEpubDocumentViewController event: \(event)")

            switch event {
            case "onInitialized":
                isReaderInitialized = true
                applyContainerInsetsIfInitialized()
                viewModel.process(action: .loadDocument)

            case "onSaveAnnotations":
                guard let params = data["params"] as? [String: Any] else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing params - \(message)")
                    return
                }
                DDLogInfo("HtmlEpubDocumentViewController: \(params)")
                viewModel.process(action: .saveAnnotations(params))

            case "onReadAloudAnnotation":
                // Reader responded to a `setReadAloudAnnotation` request with the resulting annotation.
                guard let params = data["params"] as? [String: Any], let requestID = params["requestID"] as? Int else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing requestID - \(message)")
                    return
                }
                process(readAloudAnnotation: params["annotation"] as? [String: Any], requestID: requestID)

            case "onSetAnnotationPopup":
                guard let params = data["params"] as? [String: Any] else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing params - \(message)")
                    return
                }
                
                if params.isEmpty {
                    return
                }

                guard let rectArray = params["rect"] as? [CGFloat], let key = (params["annotation"] as? [String: Any])?["id"] as? String else {
                    DDLogError("HtmlEpubDocumentViewController: incorrect params for document selection - \(params)")
                    return
                }

                let topInset = parentDelegate?.containerTopInset ?? 0
                let rect = CGRect(x: rectArray[0], y: rectArray[1] + topInset, width: rectArray[2] - rectArray[0], height: rectArray[3] - rectArray[1])
                viewModel.process(action: .showAnnotationPopover(key: key, rect: rect))

            case "onSelectAnnotations":
                guard let params = data["params"] as? [String: Any], let ids = params["ids"] as? [String] else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing params - \(message)")
                    return
                }
                if let key = ids.first {
                    viewModel.process(action: .selectAnnotationFromDocument(key: key))
                } else {
                    viewModel.process(action: .deselectSelectedAnnotation)
                }

            case "onSetSelectionPopup":
                guard let params = data["params"] as? [String: Any] else {
                    return
                }
                viewModel.process(action: .setSelectedTextParams(params))

            case "onChangeViewState":
                guard let params = data["params"] as? [String: Any] else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing params - \(message)")
                    return
                }
                viewModel.process(action: .setViewState(params))

            case "onChangeViewStats":
                guard let params = data["params"] as? [String: Any], let stats = params["stats"] as? [String: Any] else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing params - \(message)")
                    return
                }
                viewModel.process(action: .setViewStats(stats))

            case "onOpenLink":
                guard let params = data["params"] as? [String: Any], let urlString = params["url"] as? String, let url = URL(string: urlString) else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing params - \(message)")
                    return
                }
                parentDelegate?.show(url: url)

            case "onSetOutline":
                viewModel.process(action: .parseOutline(data: data))

            case "onFindResult":
                viewModel.process(action: .processDocumentSearchResults(data: data))

            case "onBackdropTap":
                parentDelegate?.toggleInterfaceVisibility()

            case "onReadAloudSegments":
                // Reader responded to a `getReadAloudSegments` request; resolve the matching pending completion.
                guard let params = data["params"] as? [String: Any], let requestID = params["requestID"] as? Int else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing requestID - \(message)")
                    return
                }
                let completion = readAloudSegmentRequests.removeValue(forKey: requestID)
                let segments = (params["segments"] as? [[String: Any]])?.compactMap(Self.parseReaderSegment)
                completion?(segments)

            case "onReadAloudStartBlockIndex":
                guard let params = data["params"] as? [String: Any], let requestID = params["requestID"] as? Int else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing requestID - \(message)")
                    return
                }
                let completion = readAloudStartBlockIndexRequests.removeValue(forKey: requestID)
                completion?((params["blockIndex"] as? NSNumber)?.intValue)

            default:
                break
            }

        default:
            break
        }
    }
}

extension HtmlEpubDocumentViewController: ParentWithSidebarDocumentController {
    func disableAnnotationTools() {
        guard let tool = viewModel.state.activeTool else { return }
        viewModel.process(action: .toggleTool(tool))
    }
}
