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

    private var debounceDisposeBag: DisposeBag
    weak var coordinatorDelegate: DetailNoteEditorCoordinatorDelegate?

    private var htmlUrl: URL? {
        if self.viewModel.state.readOnly {
            return Bundle.main.url(forResource: "note", withExtension: "html")
        } else {
            return Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "tinymce")
        }
    }

    init(viewModel: ViewModel<NoteEditorActionHandler>) {
        self.viewModel = viewModel
        self.debounceDisposeBag = DisposeBag()
        self.disposeBag = DisposeBag()
        super.init(nibName: "NoteEditorViewController", bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemBackground
        self.setupNavbarItems()
        self.setupWebView()
        self.update(tags: self.viewModel.state.tags)

        self.viewModel.stateObservable
                      .subscribe(with: self, onNext: { `self`, state in
                          self.process(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    // MARK: - Actions

    private func process(state: NoteEditorState) {
        if state.changes.contains(.tags) {
            self.update(tags: state.tags)
        }
        if state.changes.contains(.save) {
            self.debounceSave()
        }
    }

    private func debounceSave() {
        self.debounceDisposeBag = DisposeBag()

        Single<Int>.timer(.milliseconds(1500), scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.viewModel.process(action: .save)
                   })
                   .disposed(by: self.debounceDisposeBag)
    }

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

        attributedString.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: NSMakeRange(0, attributedString.string.count))
        self.tagsLabel.attributedText = attributedString
    }

    @IBAction private func changeTags() {
        guard !self.viewModel.state.readOnly else { return }
        let selected = Set(self.viewModel.state.tags.map({ $0.name }))
        self.coordinatorDelegate?.pushTagPicker(libraryId: self.viewModel.state.libraryId, selected: selected, picked: { [weak self] tags in
            self?.viewModel.process(action: .setTags(tags))
        })
    }
    
    // MARK: - Setups

    private func setupNavbarItems() {
        let done = UIBarButtonItem(title: L10n.done, style: .done, target: nil, action: nil)
        done.rx.tap
               .subscribe(with: self, onNext: { `self`, _ in
                   self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
               })
               .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = done
    }

    private func setupWebView() {
        self.webView.navigationDelegate = self
        self.webView.configuration.userContentController.add(self, name: NoteEditorViewController.jsHandler)

        guard let url = self.htmlUrl, var data = try? String(contentsOf: url, encoding: .utf8) else { return }
        data = data.replacingOccurrences(of: "#initialnote", with: self.viewModel.state.text)
        self.webView.loadHTMLString(data, baseURL: url)
    }
}

extension NoteEditorViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Allow initial load
        guard url.scheme == "http" || url.scheme == "https" else {
            decisionHandler(.allow)
            return
        }

        // Show other links in SFSafariView
        decisionHandler(.cancel)
        self.coordinatorDelegate?.showWeb(url: url)
    }
}

extension NoteEditorViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == NoteEditorViewController.jsHandler, let text = message.body as? String else { return }
        self.viewModel.process(action: .setText(text))
    }
}
