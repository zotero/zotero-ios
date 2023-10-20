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

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = UIView()
        self.view.backgroundColor = .systemBackground
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        observeViewModel()
        setupWebView()
        load()

        func observeViewModel() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(with: self, onNext: { `self`, state in
                    self.process(state: state)
                })
                .disposed(by: disposeBag)
        }

        func setupWebView() {
            let webView = WKWebView()
            webView.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(webView)

            NSLayoutConstraint.activate([
                self.view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: webView.topAnchor),
                self.view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                self.view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
            ])
            self.webView = webView
            self.webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
            self.webViewHandler.receivedMessageHandler = { [weak self] handler, message in
                self?.process(handler: handler, message: message)
            }
        }

        func load() {
            guard let readerUrl = Bundle.main.url(forResource: "view", withExtension: "html", subdirectory: "Bundled/reader") else {
                DDLogError("HtmlEpubReaderViewController: can't load reader view.html")
                return
            }
            self.webViewHandler.load(fileUrl: readerUrl)
                .subscribe()
                .disposed(by: self.disposeBag)
        }
    }

    // MARK: - Actions

    func set(tool data: (AnnotationTool, UIColor)?) {
        guard let (tool, color) = data else {
            self.webViewHandler.call(javascript: "clearTool();")
                .subscribe()
                .disposed(by: self.disposeBag)
            return
        }

        let toolName: String
        switch tool {
        case .highlight:
            toolName = "highlight"

        case .note:
            toolName = "note"

        case .eraser, .image, .ink:
            return
        }

        self.webViewHandler.call(javascript: "setTool({ type: '\(toolName)', color: '\(color.hexString)' });")
            .subscribe()
            .disposed(by: self.disposeBag)
    }

    private func process(state: HtmlEpubReaderState) {
        if let data = state.documentData {
            load(documentData: data)
            return
        }

        if let update = state.documentUpdate {
            updateView(modifications: update.modifications, insertions: update.insertions, deletions: update.deletions)
        }

        func updateView(modifications: [[String: Any]], insertions: [[String: Any]], deletions: [String]) {
            do {
                let insertionsData = try JSONSerialization.data(withJSONObject: insertions)
                let modificationsData = try JSONSerialization.data(withJSONObject: modifications)
                let deletionsData = try JSONSerialization.data(withJSONObject: deletions)

                guard let insertionsJson = String(data: insertionsData, encoding: .utf8) else {
                    DDLogError("HtmlEpubReaderViewController: can't create insertions json - \(insertions)")
                    return
                }
                guard let deletionsJson = String(data: deletionsData, encoding: .utf8) else {
                    DDLogError("HtmlEpubReaderViewController: can't create deletions json - \(insertions)")
                    return
                }
                guard let modificationsJson = String(data: modificationsData, encoding: .utf8) else {
                    DDLogError("HtmlEpubReaderViewController: can't create modifications json - \(insertions)")
                    return
                }

                webViewHandler.call(javascript: "updateAnnotations({ deletions: \(deletionsJson), insertions: \(insertionsJson), modifications: \(modificationsJson)});")
                    .observe(on: MainScheduler.instance)
                    .subscribe(with: self, onFailure: { _, error in
                        DDLogError("HtmlEpubReaderViewController: updating document failed - \(error)")
                    })
                    .disposed(by: self.disposeBag)
            } catch let error {
                DDLogError("HtmlEpubReaderViewController: can't create update jsons - \(error)")
            }
        }

        func load(documentData data: HtmlEpubReaderState.DocumentData) {
            webViewHandler.call(javascript: "createView({ type: 'snapshot', buf: \(data.buffer), annotations: \(data.annotationsJson)});")
                .observe(on: MainScheduler.instance)
                .subscribe(with: self, onFailure: { _, error in
                    DDLogError("HtmlEpubReaderViewController: loading document failed - \(error)")
                })
                .disposed(by: self.disposeBag)
        }
    }

    private func process(handler: String, message: Any) {
        switch handler {
        case JSHandlers.log.rawValue:
            DDLogInfo("HtmlEpubReaderViewController: JSLOG \(message)")

        case JSHandlers.text.rawValue:
            guard let data = message as? [String: Any], let event = data["event"] as? String, let params = data["params"] as? [String: Any] else { return }

            DDLogInfo("HtmlEpubReaderViewController: \(event); \(params)")

            switch event {
            case "onInitialized":
                self.viewModel.process(action: .loadDocument)

            case "onSaveAnnotations":
                self.viewModel.process(action: .saveAnnotations(params))

            case "onSelectAnnotations":
                self.viewModel.process(action: .selectAnnotationFromDocument(params))

            default:
                break
            }

        default:
            break
        }
    }
}
