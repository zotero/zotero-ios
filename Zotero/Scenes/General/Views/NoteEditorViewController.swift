//
//  NoteEditorViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 07/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SafariServices
import UIKit
import WebKit

import RxSwift

final class NoteEditorViewController: UIViewController {
    @IBOutlet private weak var webView: WKWebView!
    @IBOutlet private weak var tagsTitleLabel: UILabel!
    @IBOutlet private weak var tagsLabel: UILabel!

    private static let jsHandler: String = "textHandler"
    private let viewModel: ViewModel<NoteEditorActionHandler>
    private let disposeBag: DisposeBag

    private var debounceDisposeBag: DisposeBag?
    weak var coordinatorDelegate: NoteEditorCoordinatorDelegate?

    private var htmlUrl: URL? {
        if viewModel.state.kind.readOnly {
            return Bundle.main.url(forResource: "note", withExtension: "html")
        } else {
            return Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "tinymce")
        }
    }

    init(viewModel: ViewModel<NoteEditorActionHandler>) {
        self.viewModel = viewModel
        disposeBag = DisposeBag()
        super.init(nibName: "NoteEditorViewController", bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let data = viewModel.state.title {
            navigationItem.titleView = NoteEditorTitleView(type: data.type, title: data.title)
        }

        view.backgroundColor = .systemBackground
        setupNavbarItems()
        setupWebView()
        update(tags: viewModel.state.tags)

        viewModel.stateObservable
            .subscribe(with: self, onNext: { _, state in
                process(state: state)
            })
            .disposed(by: disposeBag)

        func setupNavbarItems() {
            let done = UIBarButtonItem(title: L10n.done, style: .done, target: nil, action: nil)
            done.rx.tap
                .subscribe(with: self, onNext: { `self`, _ in
                    forceSaveIfNeeded()
                    self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
                })
                .disposed(by: disposeBag)
            navigationItem.rightBarButtonItem = done

            func forceSaveIfNeeded() {
                guard debounceDisposeBag != nil else { return }
                debounceDisposeBag = nil
                viewModel.process(action: .save)
            }
        }

        func setupWebView() {
            webView.navigationDelegate = self
            webView.configuration.userContentController.add(self, name: NoteEditorViewController.jsHandler)

            guard let url = htmlUrl, var data = try? String(contentsOf: url, encoding: .utf8) else { return }
            data = data.replacingOccurrences(of: "#initialnote", with: viewModel.state.text)
            webView.loadHTMLString(data, baseURL: url)
        }

        func process(state: NoteEditorState) {
            if state.changes.contains(.tags) {
                update(tags: state.tags)
            }
            if state.changes.contains(.save) {
                debounceSave()
            }

            func debounceSave() {
                debounceDisposeBag = nil
                let disposeBag = DisposeBag()

                Single<Int>.timer(.seconds(1), scheduler: MainScheduler.instance)
                    .subscribe(onSuccess: { [weak self] _ in
                        guard let self else { return }
                        viewModel.process(action: .save)
                        debounceDisposeBag = nil
                    })
                    .disposed(by: disposeBag)

                debounceDisposeBag = disposeBag
            }
        }
    }

    // MARK: - Actions
    private func update(tags: [Tag]) {
        let attributedString = NSMutableAttributedString()

        for (idx, tag) in tags.enumerated() {
            let (color, type) = TagColorGenerator.uiColor(for: tag.color)
            let textColor = UIColor { $0.userInterfaceStyle == .light ? .darkText : .white }

            switch type {
            case .border:
                attributedString.append(NSAttributedString(string: tag.name, attributes: [.foregroundColor: textColor]))

            case .filled:
                attributedString.append(NSAttributedString(string: tag.name, attributes: [.foregroundColor: color]))
            }

            if idx != tags.count - 1 {
                attributedString.append(NSAttributedString(string: ", ", attributes: [.foregroundColor: textColor]))
            }
        }

        attributedString.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: NSRange(location: 0, length: attributedString.string.count))
        tagsLabel.attributedText = attributedString
    }

    @IBAction private func changeTags() {
        guard !viewModel.state.kind.readOnly else { return }
        let selected = Set(viewModel.state.tags.map({ $0.name }))
        coordinatorDelegate?.showTagPicker(libraryId: viewModel.state.library.identifier, selected: selected, picked: { [weak self] tags in
            self?.viewModel.process(action: .setTags(tags))
        })
    }
}

extension NoteEditorViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        switch url.scheme ?? "" {
        case "file", "about":
            // Allow initial load
            decisionHandler(.allow)

        default:
            // Try opening other URLs
            decisionHandler(.cancel)
            coordinatorDelegate?.show(url: url)
        }
    }
}

extension NoteEditorViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == NoteEditorViewController.jsHandler, let text = message.body as? String else { return }
        viewModel.process(action: .setText(text))
    }
}
