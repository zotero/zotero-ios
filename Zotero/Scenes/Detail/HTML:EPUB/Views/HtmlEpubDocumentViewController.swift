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

    private let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var webView: WKWebView!
    private var webViewHandler: WebViewHandler!
    weak var parentDelegate: HtmlEpubReaderContainerDelegate?

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        self.viewModel = viewModel
        disposeBag = DisposeBag()
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
            if #available(iOS 16.4, *) {
                webView.isInspectable = true
            }
            view.addSubview(webView)

            NSLayoutConstraint.activate([
                view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: webView.topAnchor),
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

    private func process(state: HtmlEpubReaderState) {
        if state.changes.contains(.readerInitialised) {
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
            var javascript = "createView({ type: '\(data.type)', url: '\(data.url.absoluteString.replacingOccurrences(of: "'", with: #"\'"#))', annotations: \(data.annotationsJson)"
            if let page = data.page {
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
        switch appearanceMode {
        case .automatic:
            webView.overrideUserInterfaceStyle = userInterfaceStyle

        case .light, .sepia:
            webView.overrideUserInterfaceStyle = .light

        case .dark:
            webView.overrideUserInterfaceStyle = .dark
        }
        let appearanceString = Appearance.from(appearanceMode: appearanceMode, interfaceStyle: userInterfaceStyle).htmlEpubValue
        webView.call(javascript: "window._view.setColorScheme('\(appearanceString)');").subscribe().disposed(by: disposeBag)
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

    private func process(handler: String, message: Any) {
        switch handler {
        case JSHandlers.log.rawValue:
            DDLogInfo("HtmlEpubDocumentViewController: JSLOG \(message)")

        case JSHandlers.text.rawValue:
            guard let data = message as? [String: Any], let event = data["event"] as? String else {
                DDLogWarn("HtmlEpubDocumentViewController: unknown message - \(message)")
                return
            }

            DDLogInfo("HtmlEpubDocumentViewController: \(event)")

            switch event {
            case "onInitialized":
                viewModel.process(action: .loadDocument)

            case "onSaveAnnotations":
                guard let params = data["params"] as? [String: Any] else {
                    DDLogWarn("HtmlEpubDocumentViewController: event \(event) missing params - \(message)")
                    return
                }
                DDLogInfo("HtmlEpubDocumentViewController: \(params)")
                viewModel.process(action: .saveAnnotations(params))

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

                let navigationBarInset = (parentDelegate?.statusBarHeight ?? 0) + (parentDelegate?.navigationBarHeight ?? 0)
                let rect = CGRect(x: rectArray[0], y: rectArray[1] + navigationBarInset, width: rectArray[2] - rectArray[0], height: rectArray[3] - rectArray[1])
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
