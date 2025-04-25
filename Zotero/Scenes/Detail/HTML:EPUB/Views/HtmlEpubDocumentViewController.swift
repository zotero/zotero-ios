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
        load()

        func observeViewModel() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] state in
                    self?.process(state: state)
                })
                .disposed(by: disposeBag)
        }

        func setupWebView() {
            let webView = WKWebView()
            webView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(webView)

            NSLayoutConstraint.activate([
                view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: webView.topAnchor),
                view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
            ])
            self.webView = webView
            webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
            webViewHandler.receivedMessageHandler = { [weak self] handler, message in
                self?.process(handler: handler, message: message)
            }
        }

        func load() {
            guard let readerUrl = Bundle.main.url(forResource: "view", withExtension: "html", subdirectory: "Bundled/reader") else {
                DDLogError("HtmlEpubReaderViewController: can't load reader view.html")
                return
            }
            webViewHandler.load(fileUrl: readerUrl).subscribe().disposed(by: disposeBag)
        }
    }

    // MARK: - Actions

    private func process(state: HtmlEpubReaderState) {
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

        func set(tool data: (AnnotationTool, UIColor)?) {
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

            case .eraser, .image, .ink, .underline, .freeText:
                return
            }
            webViewHandler.call(javascript: "setTool({ type: '\(toolName)', color: '\(color.hexString)' });").subscribe().disposed(by: disposeBag)
        }

        func search(term: String) {
            webViewHandler.call(javascript: "search({ term: \(WebViewEncoder.encodeForJavascript(term.data(using: .utf8))) });")
                .observe(on: MainScheduler.instance)
                .subscribe(onFailure: { error in
                    DDLogError("HtmlEpubReaderViewController: searching document failed - \(error)")
                })
                .disposed(by: disposeBag)
        }

        func selectInDocument(key: String) {
            webViewHandler.call(javascript: "select({ key: '\(key)' });")
                .observe(on: MainScheduler.instance)
                .subscribe(onFailure: { error in
                    DDLogError("HtmlEpubReaderViewController: navigating to \(key) failed - \(error)")
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
                    DDLogError("HtmlEpubReaderViewController: updating document failed - \(error)")
                })
                .disposed(by: disposeBag)
        }

        func load(documentData data: HtmlEpubReaderState.DocumentData) {
            DDLogInfo("HtmlEpubDocumentViewController: try creating view for \(data.type); page = \(String(describing: data.page))")
            var javascript = "createView({ type: '\(data.type)', buf: \(data.buffer), annotations: \(data.annotationsJson)"
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
                    DDLogError("HtmlEpubReaderViewController: loading document failed - \(error)")
                })
                .disposed(by: disposeBag)
        }
    }

    private func process(handler: String, message: Any) {
        switch handler {
        case JSHandlers.log.rawValue:
            DDLogInfo("HtmlEpubReaderViewController: JSLOG \(message)")

        case JSHandlers.text.rawValue:
            guard let data = message as? [String: Any], let event = data["event"] as? String else {
                DDLogWarn("HtmlEpubReaderViewController: unknown message - \(message)")
                return
            }

            DDLogInfo("HtmlEpubReaderViewController: \(event)")

            switch event {
            case "onInitialized":
                viewModel.process(action: .loadDocument)

            case "onSaveAnnotations":
                guard let params = data["params"] as? [String: Any] else {
                    DDLogWarn("HtmlEpubReaderViewController: event \(event) missing params - \(message)")
                    return
                }
                DDLogInfo("HtmlEpubReaderViewController: \(params)")
                viewModel.process(action: .saveAnnotations(params))

            case "onSetAnnotationPopup":
                guard let params = data["params"] as? [String: Any] else {
                    DDLogWarn("HtmlEpubReaderViewController: event \(event) missing params - \(message)")
                    return
                }
                
                if params.isEmpty {
                    viewModel.process(action: .deselectSelectedAnnotation)
                    return
                }

                guard let rectArray = params["rect"] as? [CGFloat], let key = (params["annotation"] as? [String: Any])?["id"] as? String else {
                    DDLogError("HtmlEpubReaderViewController: incorrect params for document selection - \(params)")
                    return
                }

                let navigationBarInset = (parentDelegate?.statusBarHeight ?? 0) + (parentDelegate?.navigationBarHeight ?? 0)
                let rect = CGRect(x: rectArray[0], y: rectArray[1] + navigationBarInset, width: rectArray[2] - rectArray[0], height: rectArray[3] - rectArray[1])
                viewModel.process(action: .selectAnnotationFromDocument(key: key, rect: rect))

            case "onChangeViewState":
                guard let params = data["params"] as? [String: Any] else {
                    DDLogWarn("HtmlEpubReaderViewController: event \(event) missing params - \(message)")
                    return
                }
                viewModel.process(action: .setViewState(params))

            default:
                break
            }

        default:
            break
        }
    }
}
