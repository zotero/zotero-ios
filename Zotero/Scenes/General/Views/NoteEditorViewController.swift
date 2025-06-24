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
    private enum RightBarButtonItem: Int {
        case done
        case closing
        case restoreOpenItems
    }

    @IBOutlet private weak var webView: WKWebView!
    @IBOutlet private weak var webViewBottom: NSLayoutConstraint!
    @IBOutlet private weak var tagsContainer: UIView!
    @IBOutlet private weak var tagsTitleLabel: UILabel!
    @IBOutlet private weak var tagsLabel: UILabel!

    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let uriConverter: ZoteroURIConverter
    let viewModel: ViewModel<NoteEditorActionHandler>
    private let disposeBag: DisposeBag

    private var debounceDisposeBag: DisposeBag?
    private unowned let openItemsController: OpenItemsController
    weak var coordinatorDelegate: (NoteEditorCoordinatorDelegate & OpenItemsPresenter)?

    init(
        viewModel: ViewModel<NoteEditorActionHandler>,
        htmlAttributedStringConverter: HtmlAttributedStringConverter,
        dbStorage: DbStorage,
        fileStorage: FileStorage,
        uriConverter: ZoteroURIConverter,
        openItemsController: OpenItemsController
    ) {
        self.viewModel = viewModel
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.uriConverter = uriConverter
        self.openItemsController = openItemsController
        disposeBag = DisposeBag()
        super.init(nibName: "NoteEditorViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        openItemsController.setOpenItemsUserActivity(from: self, libraryId: viewModel.state.library.identifier, title: viewModel.state.title)

        if let parentTitleData = viewModel.state.parentTitleData {
            navigationItem.titleView = NoteEditorTitleView(type: parentTitleData.type, title: htmlAttributedStringConverter.convert(text: parentTitleData.title).string)
        }

        setupNavbarItems(for: viewModel.state, isClosing: false)
        setupKeyboard()
        setupWebView()
        setupOpenItemsObserving()
        update(tags: viewModel.state.tags)

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

        func setupOpenItemsObserving() {
            guard let sessionIdentifier else { return }
            openItemsController.observable(for: sessionIdentifier)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] items in
                    self?.viewModel.process(action: .updateOpenItems(items: items))
                })
                .disposed(by: disposeBag)
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

    private func setupNavbarItems(for state: NoteEditorState, isClosing: Bool) {
        defer {
            updateRestoreOpenItemsButton(withCount: state.openItemsCount)
        }
        let currentItems = (self.navigationItem.rightBarButtonItems ?? []).compactMap({ RightBarButtonItem(rawValue: $0.tag) })
        let expectedItems = rightBarButtonItemTypes(for: state, isClosing: isClosing)
        guard currentItems != expectedItems else { return }
        navigationItem.rightBarButtonItems = expectedItems.map({ createRightBarButtonItem($0) }).reversed()

        func rightBarButtonItemTypes(for state: NoteEditorState, isClosing: Bool) -> [RightBarButtonItem] {
            var items: [RightBarButtonItem] = [isClosing ? .closing : .done]
            if FeatureGates.enabled.contains(.multipleOpenItems), state.openItemsCount > 0 {
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
                    .subscribe(onNext: { [weak self] _ in
                        guard let self else { return }
                        closeAndSaveIfNeeded()
                    })
                    .disposed(by: disposeBag)
                item = done

            case .closing:
                let activityIndicator = UIActivityIndicatorView(style: .medium)
                activityIndicator.color = .gray
                activityIndicator.startAnimating()
                item = UIBarButtonItem(customView: activityIndicator)

            case .restoreOpenItems:
                let openItems = UIBarButtonItem.openItemsBarButtonItem()
                if let sessionIdentifier {
                    let deferredOpenItemsMenuElement = openItemsController.deferredOpenItemsMenuElement(
                        for: sessionIdentifier,
                        showMenuForCurrentItem: true,
                        openItemPresenterProvider: { [weak self] in
                            self?.coordinatorDelegate
                        },
                        completion: { [weak self] changedCurrentItem, openItemsChanged in
                            guard let self else { return }
                            if changedCurrentItem {
                                closeAndSaveIfNeeded()
                            } else if openItemsChanged {
                                openItemsController.setOpenItemsUserActivity(from: self, libraryId: viewModel.state.library.identifier, title: viewModel.state.title)
                            }
                        }
                    )
                    let openItemsMenu = UIMenu(title: L10n.Accessibility.Pdf.openItems, options: [.displayInline], children: [deferredOpenItemsMenuElement])
                    openItems.menu = UIMenu(children: [openItemsMenu])
                }
                item = openItems
            }

            item.tag = type.rawValue
            return item
        }

        func updateRestoreOpenItemsButton(withCount count: Int) {
            guard let item = navigationItem.rightBarButtonItems?.first(where: { button in RightBarButtonItem(rawValue: button.tag) == .restoreOpenItems }) else { return }
            item.image = .openItemsImage(count: count)
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
            case .edit, .readOnly:
                openItemsController.setOpenItemsUserActivity(from: self, libraryId: state.library.identifier, title: state.title)

            case.itemCreation, .standaloneCreation:
                break
            }
        }

        if state.changes.contains(.openItems) || state.changes.contains(.closing) {
            setupNavbarItems(for: state, isClosing: state.isClosing)
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

        case "openAnnotation":
            guard
                let uri = data["attachmentURI"] as? String,
                let (key, libraryId) = uriConverter.convert(uri: uri),
                let position = data["position"] as? [String: Any],
                let rawRects = position["rects"] as? [[Double]],
                let pageIndex = position["pageIndex"] as? Int
            else { return }
            let rects = rawRects.compactMap({ doubles -> CGRect? in
                guard doubles.count == 4 else { return nil }
                return CGRect(x: doubles[0], y: doubles[1], width: doubles[2] - doubles[0], height: doubles[3] - doubles[1])
            })
            let preview = AnnotationPreview(parentKey: key, libraryId: libraryId, pageIndex: pageIndex, rects: rects)
            coordinatorDelegate?.showItem(withPreview: preview, completion: createCloseCompletion())

        case "openCitationPage":
            guard let citation = data["citation"] as? [String: Any], let metadata = parseCitation(from: citation) else { return }
            coordinatorDelegate?.showItem(withCitation: metadata, completion: createCloseCompletion())

        case "showCitationItem":
            guard let citation = data["citation"] as? [String: Any], let metadata = parseCitation(from: citation) else { return }
            coordinatorDelegate?.showItemDetail(withCitation: metadata, completion: createCloseCompletion())

        default:
            DDLogWarn("NoteEditorViewController JS: unknown action \(action); \(data)")
        }

        func parseCitation(from data: [String: Any]) -> CitationMetadata? {
            guard
                let rawItems = data["citationItems"] as? [[String: Any]],
                let rawItem = rawItems.first,
                let uris = rawItem["uris"] as? [String],
                let uri = uris.first,
                let (key, libraryId) = uriConverter.convert(uri: uri),
                let locator = (rawItem["locator"] as? String).flatMap(Int.init),
                let item = try? dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: .main),
                let attachment = AttachmentCreator.mainAttachment(for: item, fileStorage: fileStorage, urlDetector: nil)
            else { return nil }
            return CitationMetadata(attachmentKey: attachment.key, parentKey: key, libraryId: libraryId, locator: locator)
        }

        func createCloseCompletion() -> ((Bool) -> Void) {
            return { [weak self] closed in
                guard closed, let self, debounceDisposeBag != nil else { return }
                debounceDisposeBag = nil
                viewModel.process(action: .save)
            }
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

        attributedString.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: NSRange(location: 0, length: attributedString.length))
        tagsLabel.attributedText = attributedString
    }

    @IBAction private func changeTags() {
        guard !viewModel.state.kind.readOnly else { return }
        let selected = Set(viewModel.state.tags.map({ $0.name }))
        coordinatorDelegate?.showTagPicker(libraryId: viewModel.state.library.identifier, selected: selected, picked: { [weak self] tags in
            self?.viewModel.process(action: .setTags(tags))
        })
    }

    private func closeAndSaveIfNeeded() {
        if debounceDisposeBag == nil {
            close()
            return
        }

        debounceDisposeBag = nil
        viewModel.process(action: .saveBeforeClosing)
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
