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
    private enum RightBarButtonItem: Int {
        case done
        case restoreOpenItems
    }

    @IBOutlet private weak var webView: WKWebView!
    @IBOutlet private weak var tagsTitleLabel: UILabel!
    @IBOutlet private weak var tagsLabel: UILabel!

    private static let jsHandler: String = "textHandler"
    private let viewModel: ViewModel<NoteEditorActionHandler>
    private let disposeBag: DisposeBag

    private var debounceDisposeBag: DisposeBag?
    private unowned let openItemsController: OpenItemsController
    weak var coordinatorDelegate: (NoteEditorCoordinatorDelegate & OpenItemsPresenter)?

    private var htmlUrl: URL? {
        if viewModel.state.kind.readOnly {
            return Bundle.main.url(forResource: "note", withExtension: "html")
        } else {
            return Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "tinymce")
        }
    }

    init(viewModel: ViewModel<NoteEditorActionHandler>, openItemsController: OpenItemsController) {
        self.viewModel = viewModel
        self.openItemsController = openItemsController
        disposeBag = DisposeBag()
        super.init(nibName: "NoteEditorViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let sessionIdentifier = view.scene?.session.persistentIdentifier {
            set(userActivity: .pdfActivity(with: openItemsController.getItems(for: sessionIdentifier), libraryId: viewModel.state.library.identifier, collectionId: Defaults.shared.selectedCollectionId))
        }

        if let data = viewModel.state.title {
            navigationItem.titleView = NoteEditorTitleView(type: data.type, title: data.title)
        }

        view.backgroundColor = .systemBackground
        setupNavbarItems(for: viewModel.state)
        setupWebView()
        setupOpenItemsObserving()
        update(tags: viewModel.state.tags)

        viewModel.stateObservable
            .subscribe(with: self, onNext: { _, state in
                process(state: state)
            })
            .disposed(by: disposeBag)

        func setupNavbarItems(for state: NoteEditorState) {
            defer {
                updateRestoreOpenItemsButton(withCount: state.openItemsCount)
            }
            let currentItems = (self.navigationItem.rightBarButtonItems ?? []).compactMap({ RightBarButtonItem(rawValue: $0.tag) })
            let expectedItems = rightBarButtonItemTypes(for: state)
            guard currentItems != expectedItems else { return }
            navigationItem.rightBarButtonItems = expectedItems.map({ createRightBarButtonItem($0) }).reversed()

            func rightBarButtonItemTypes(for state: NoteEditorState) -> [RightBarButtonItem] {
                var items: [RightBarButtonItem] = [.done]
                if state.openItemsCount > 1 {
                    items = [.restoreOpenItems] + items
                }
                return items
            }

            func createRightBarButtonItem(_ type: RightBarButtonItem) -> UIBarButtonItem {
                let item: UIBarButtonItem
                switch type {
                case .done:
                    let done = UIBarButtonItem(title: L10n.done, style: .done, target: nil, action: nil)
                    done.rx.tap
                        .subscribe(with: self, onNext: { `self`, _ in
                            forceSaveIfNeeded()
                            self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
                        })
                        .disposed(by: disposeBag)
                    item = done

                case .restoreOpenItems:
                    let openItems: UIBarButtonItem
                    if let sessionIdentifier = view.scene?.session.persistentIdentifier {
                        let items = openItemsController.getItems(for: sessionIdentifier)
                        openItems = UIBarButtonItem(image: UIImage(systemName: "\(items.count).square"), style: .plain, target: nil, action: nil)
                        openItems.isEnabled = true
                        if let sessionIdentifier = view.scene?.session.persistentIdentifier {
                            let deferredOpenItemsMenuElement = openItemsController.deferredOpenItemsMenuElement(for: sessionIdentifier, disableOpenItem: true) { [weak self] item, _ in
                                guard let self, let coordinatorDelegate else { return }
                                openItemsController.restore(item, using: coordinatorDelegate)
                            }
                            let openItemsMenu = UIMenu(title: "Open Items", options: [.displayInline], children: [deferredOpenItemsMenuElement])
                            openItems.menu = UIMenu(children: [openItemsMenu])
                        }
                    } else {
                        openItems = UIBarButtonItem(image: UIImage(systemName: "0.square"), style: .plain, target: nil, action: nil)
                        openItems.isEnabled = false
                    }
                    openItems.accessibilityLabel = L10n.Accessibility.Pdf.openItems
                    openItems.title = L10n.Accessibility.Pdf.openItems
                    item = openItems
                }

                item.tag = type.rawValue
                return item
            }

            func updateRestoreOpenItemsButton(withCount count: Int) {
                guard let item = navigationItem.rightBarButtonItems?.first(where: { button in RightBarButtonItem(rawValue: button.tag) == .restoreOpenItems }) else { return }
                item.image = UIImage(systemName: "\(count).square")
            }

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

        func setupOpenItemsObserving() {
            guard let sessionIdentifier = view.scene?.session.persistentIdentifier else { return }
            openItemsController.observable(for: sessionIdentifier)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] items in
                    self?.viewModel.process(action: .updateOpenItems(items: items))
                })
                .disposed(by: disposeBag)
        }

        func process(state: NoteEditorState) {
            if state.changes.contains(.tags) {
                update(tags: state.tags)
            }
            if state.changes.contains(.save) {
                debounceSave()
            }
            if state.changes.contains(.openItems) {
                setupNavbarItems(for: state)
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
