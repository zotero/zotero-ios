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

import CocoaLumberjackSwift
import RxSwift

final class NoteEditorViewController: UIViewController {
    fileprivate enum JSHandlers: String, CaseIterable {
        case messageHandler
        case logHandler
    }

    @IBOutlet private weak var webView: WKWebView!
    @IBOutlet private weak var webViewBottom: NSLayoutConstraint!
    @IBOutlet private weak var tagsContainer: UIView!
    @IBOutlet private weak var tagsTitleLabel: UILabel!
    @IBOutlet private weak var tagsLabel: UILabel!

    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    let viewModel: ViewModel<NoteEditorActionHandler>
    private let disposeBag: DisposeBag

    private var debounceDisposeBag: DisposeBag?
    weak var coordinatorDelegate: NoteEditorCoordinatorDelegate?

    init(viewModel: ViewModel<NoteEditorActionHandler>, htmlAttributedStringConverter: HtmlAttributedStringConverter) {
        self.viewModel = viewModel
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        disposeBag = DisposeBag()
        super.init(nibName: "NoteEditorViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        switch viewModel.state.kind {
        case .edit(let key), .readOnly(let key):
            let openItem = OpenItem(kind: .note(libraryId: viewModel.state.library.identifier, key: key), userIndex: 0)
            set(userActivity: .contentActivity(with: [openItem], libraryId: viewModel.state.library.identifier, collectionId: Defaults.shared.selectedCollectionId)
                .set(title: viewModel.state.title)
            )

        case.itemCreation, .standaloneCreation:
            break
        }

        if let parentTitleData = viewModel.state.parentTitleData {
            navigationItem.titleView = NoteEditorTitleView(type: parentTitleData.type, title: htmlAttributedStringConverter.convert(text: parentTitleData.title).string)
        }

        setupNavbarItems(isClosing: false)
        setupKeyboard()
        setupWebView()
        update(tags: viewModel.state.tags)
        viewModel.process(action: .setup)

        viewModel.stateObservable
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                process(state: state)
            })
            .disposed(by: disposeBag)

        func setupWebView() {
            webView.scrollView.isScrollEnabled = false

            for handler in JSHandlers.allCases {
                webView.configuration.userContentController.add(self, name: handler.rawValue)
            }

            guard let url = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Bundled/note_editor") else {
                DDLogError("NoteEditorViewController: editor source not found")
                return
            }
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func setupKeyboard() {
            NotificationCenter.default
                .keyboardWillShow
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] notification in
                    guard let self, let data = notification.keyboardData else { return }
                    moveWebView(toKeyboardData: data, controller: self)
                })
                .disposed(by: disposeBag)

            NotificationCenter.default
                .keyboardWillHide
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] notification in
                    guard let self, let data = notification.keyboardData else { return }
                    moveWebView(toKeyboardData: data, controller: self)
                })
                .disposed(by: disposeBag)

            NotificationCenter.default.removeObserver(webView!, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            NotificationCenter.default.removeObserver(webView!, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(webView!, name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        func moveWebView(toKeyboardData data: KeyboardData, controller: NoteEditorViewController) {
            let isClosing = data.endFrame.minY > data.startFrame.minY
            controller.webViewBottom.constant = isClosing ? 0 : data.endFrame.height
            UIView.animate(withDuration: data.animationDuration, delay: 0, options: data.animationOptions, animations: {
                controller.view.layoutIfNeeded()
            })
        }
    }

    // MARK: - Actions

    private func setupNavbarItems(isClosing: Bool) {
        if isClosing {
            let activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.color = .gray
            activityIndicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activityIndicator)
            return
        }

        let done = UIBarButtonItem(title: L10n.done, style: .done, target: nil, action: nil)
        done.rx
            .tap
            .subscribe(onNext: { [weak self] _ in
                guard let self else { return }
                closeAndSaveIfNeeded(controller: self)
            })
            .disposed(by: disposeBag)
        navigationItem.rightBarButtonItem = done

        func closeAndSaveIfNeeded(controller: NoteEditorViewController) {
            if controller.debounceDisposeBag == nil {
                controller.close()
                return
            }

            controller.debounceDisposeBag = nil
            controller.viewModel.process(action: .saveBeforeClosing)
        }
    }

    private func close() {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    func process(state: NoteEditorState) {
        if state.changes.contains(.saved) && state.isClosing {
            close()
        }

        if state.changes.contains(.tags) {
            update(tags: state.tags)
        }

        if state.changes.contains(.shouldSave) {
            debounceSave()
        }
        if state.changes.contains(.kind) || state.changes.contains(.title) {
            switch state.kind {
            case .edit(let key), .readOnly(let key):
                let openItem = OpenItem(kind: .note(libraryId: state.library.identifier, key: key), userIndex: 0)
                set(userActivity: .contentActivity(with: [openItem], libraryId: state.library.identifier, collectionId: Defaults.shared.selectedCollectionId)
                    .set(title: state.title)
                )

            case.itemCreation, .standaloneCreation:
                break
            }
        }

        if state.changes.contains(.closing) {
            setupNavbarItems(isClosing: state.isClosing)
        }

        if !state.createdImages.isEmpty {
            let webViewCalls = state.createdImages.map({
                let encodedData = WebViewEncoder.encodeAsJSONForJavascript(["nodeID": $0.nodeId, "attachmentKey": $0.key])
                return webView.call(javascript: "attachImportedImage(\(encodedData));").asObservable()
            })
            Observable.concat(webViewCalls).subscribe().disposed(by: disposeBag)
        }

        if let resource = state.downloadedResource {
            let encodedData = WebViewEncoder.encodeAsJSONForJavascript(["id": resource.identifier, "data": resource.data])
            webView.call(javascript: "notifySubscription(\(encodedData));").subscribe().disposed(by: disposeBag)
        }

        if state.changes.contains(.kind) || state.changes.contains(.title) {
            switch state.kind {
            case .edit(let key), .readOnly(let key):
                let openItem = OpenItem(kind: .note(libraryId: state.library.identifier, key: key), userIndex: 0)
                set(userActivity: .contentActivity(with: [openItem], libraryId: state.library.identifier, collectionId: Defaults.shared.selectedCollectionId)
                    .set(title: state.title)
                )

            case.itemCreation, .standaloneCreation:
                break
            }
        }

        if let error = state.error {
            coordinatorDelegate?.show(error: error, isClosing: state.changes.contains(.closing))
        }

        func debounceSave() {
            debounceDisposeBag = DisposeBag()
            Single<Int>.timer(.seconds(1), scheduler: MainScheduler.instance)
                .subscribe(onSuccess: { [weak self] _ in
                    guard let self else { return }
                    viewModel.process(action: .save)
                    debounceDisposeBag = nil
                })
                .disposed(by: debounceDisposeBag!)
        }
    }

    private func perform(action: String, data: [String: Any]) {
        switch action {
        case "initialized":
            let data = WebViewEncoder.encodeAsJSONForJavascript(["value": viewModel.state.text, "readOnly": viewModel.state.kind.readOnly])
            webView.call(javascript: "start(\(data));").subscribe().disposed(by: disposeBag)

        case "readerInitialized":
            DDLogInfo("NoteEditorViewController: reader initialized")

        case "update":
            guard let value = data["value"] as? String else { return }
            viewModel.process(action: .setText(value))

        case "openURL":
            guard let urlString = data["url"] as? String, let url = URL(string: urlString) else { return }
            coordinatorDelegate?.show(url: url)

        case "subscribe":
            guard let subscription = data["subscription"] as? [String: Any] else { return }
            viewModel.process(action: .loadResource(subscription))

        case "unsubscribe":
            viewModel.process(action: .deleteResource(data))

        case "importImages":
            viewModel.process(action: .importImages(data))

        default:
            DDLogWarn("NoteEditorViewController JS: unknown action \(action); \(data)")
        }
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

extension NoteEditorViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let handler = JSHandlers(rawValue: message.name) else {
            DDLogWarn("NoteEditorViewController: unknown js handler \(message.name); \(message.body)")
            return
        }

        switch handler {
        case .logHandler:
            guard let body = message.body as? String else { return }
            DDLogInfo("NoteEditorViewController JS: \(body)")

        case .messageHandler:
            guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
                DDLogError("NoteEditorViewController JS: unknown message \(message.body)")
                return
            }
            perform(action: action, data: body)
        }
    }
}
