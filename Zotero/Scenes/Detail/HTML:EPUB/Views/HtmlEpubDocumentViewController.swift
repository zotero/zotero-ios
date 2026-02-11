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

    private(set) weak var webView: WKWebView!
    var webViewHandler: WebViewHandler!
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
        // Start with clear background to prevent black bar, will be updated based on appearance
        view.backgroundColor = .clear
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
            if #available(iOS 16.4, *) {
                webView.isInspectable = true
            }
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.bounces = false
            webView.scrollView.alwaysBounceVertical = false
            webView.scrollView.alwaysBounceHorizontal = false
            webView.scrollView.showsVerticalScrollIndicator = false
            webView.scrollView.showsHorizontalScrollIndicator = false
            if #available(iOS 16.4, *) {
                webView.isInspectable = true
            }
            view.addSubview(webView)

            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: view.topAnchor),
                webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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
    
    private var lastKnownCFI: String?
    private var lastKnownOffset: Double?
    private var hasInjectedToolbarInsetCSS = false

    func notifyResize() {
        guard let cfi = lastKnownCFI else { return }
        let offsetStr = lastKnownOffset != nil ? "\(lastKnownOffset!)" : "null"
        webViewHandler.call(javascript: "window._view.setPreResizeCFI('\(cfi)', \(offsetStr));")
            .subscribe()
            .disposed(by: disposeBag)
    }

    func updateLastKnownPosition(cfi: String?, offset: Double?) {
        lastKnownCFI = cfi
        lastKnownOffset = offset
    }

    /// Injects CSS into the epub iframe to permanently reserve bottom space for the toolbar offset.
    /// This ensures that when the WebView is translated down (toolbar visible), the bottom margin
    /// of the paginated columns is preserved rather than pushed off-screen.
    private func injectToolbarInsetCSS(cfi: String, offset: Double?) {
        let toolbarHeight = (parentDelegate?.statusBarHeight ?? 0) + (parentDelegate?.navigationBarHeight ?? 0)
        guard toolbarHeight > 0 else { return }

        let totalBottomMargin = 40 + Int(toolbarHeight)
        let totalVerticalDeduction = 80 + Int(toolbarHeight)

        let css = "body.flow-mode-paginated:not(.fixed-layout){margin-bottom:\(totalBottomMargin)px!important}"
            + "body.flow-mode-paginated:not(.fixed-layout)>.sections{"
            + "max-height:calc(100vh - \(totalVerticalDeduction)px)!important;"
            + "min-height:calc(100vh - \(totalVerticalDeduction)px)!important}"

        let escapedCfi = cfi.replacingOccurrences(of: "'", with: "\\'")
        let offsetStr = offset != nil ? "\(offset!)" : "undefined"

        let js = """
        (function(){
            var doc=window._view&&window._view._iframeDocument;
            if(!doc||doc.getElementById('toolbar-inset-override'))return;
            var s=doc.createElement('style');
            s.id='toolbar-inset-override';
            s.textContent='\(css)';
            doc.head.appendChild(s);
            requestAnimationFrame(function(){
                window._view.navigate({pageNumber:'\(escapedCfi)'},{skipHistory:true,behavior:'auto',offsetBlock:\(offsetStr)});
            });
        })();
        """

        webViewHandler.call(javascript: js).subscribe().disposed(by: disposeBag)
    }

    private func process(state: HtmlEpubReaderState) {
        if state.changes.contains(.readerInitialised) {
            webViewHandler.load(fileUrl: state.readerFile.createUrl()).subscribe().disposed(by: disposeBag)
            return
        }

        if let data = state.documentData {
            load(documentData: data)
            // Apply typesetting settings after document loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.applyTypesettingSettings(from: state.settings)
            }
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
            // Reapply typesetting when appearance changes
            applyTypesettingSettings(from: state.settings)
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
        let backgroundColor: UIColor
        switch appearanceMode {
        case .automatic:
            webView.overrideUserInterfaceStyle = userInterfaceStyle
            backgroundColor = userInterfaceStyle == .dark ? .black : .white

        case .light:
            webView.overrideUserInterfaceStyle = .light
            backgroundColor = .white

        case .sepia:
            webView.overrideUserInterfaceStyle = .light
            backgroundColor = UIColor(red: 0.98, green: 0.95, blue: 0.89, alpha: 1.0)

        case .dark:
            webView.overrideUserInterfaceStyle = .dark
            backgroundColor = .black
        }
        
        view.backgroundColor = backgroundColor
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        
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
                DDLogInfo("HtmlEpubDocumentViewController: onInitialized")
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

                let webViewOffset = webView?.transform.ty ?? 0
                let rect = CGRect(x: rectArray[0], y: rectArray[1] + webViewOffset, width: rectArray[2] - rectArray[0], height: rectArray[3] - rectArray[1])
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
                // Store the current CFI for position restoration
                if let state = params["state"] as? [String: Any], let cfi = state["cfi"] as? String {
                    DDLogInfo("HtmlEpubDocumentViewController: updating lastKnownCFI to: \(cfi)")
                    let offset = state["cfiElementOffset"] as? Double
                    updateLastKnownPosition(cfi: cfi, offset: offset)

                    // Inject toolbar inset CSS on first valid position
                    if !hasInjectedToolbarInsetCSS {
                        hasInjectedToolbarInsetCSS = true
                        injectToolbarInsetCSS(cfi: cfi, offset: offset)
                    }
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

            case "onBackdropTap":
                parentDelegate?.toggleInterfaceVisibility()

            default:
                break
            }

        default:
            break
        }
    }
    
    // MARK: - Typesetting
    
    private func applyTypesettingSettings(from settings: HtmlEpubSettings) {
        guard let webView else {
            DDLogWarn("HtmlEpubDocumentViewController: Cannot apply typesetting - webView is nil")
            return
        }
        DDLogInfo("HtmlEpubDocumentViewController: Applying typesetting - font: \(settings.typesetting.fontFamily ?? "default"), customFont: \(settings.customFont ?? "none")")
        
        // Get fresh settings from FontManager to ensure we have latest font selections
        let fontManager = FontManager.shared
        var appliedSettings = settings.typesetting
        
        // Override font family if custom font is set
        if let customFont = settings.customFont {
            appliedSettings.fontFamily = customFont
            DDLogInfo("HtmlEpubDocumentViewController: Using custom font: \(customFont)")
        } else if let documentCustomFont = fontManager.font(forDocument: viewModel.state.key) {
            appliedSettings.fontFamily = documentCustomFont
            DDLogInfo("HtmlEpubDocumentViewController: Using document custom font: \(documentCustomFont)")
        }
        
        TypesettingApplicator.applySettings(appliedSettings, appearance: settings.appearance, to: webView)
    }
}

extension HtmlEpubDocumentViewController: ParentWithSidebarDocumentController {
    func disableAnnotationTools() {
        guard let tool = viewModel.state.activeTool else { return }
        viewModel.process(action: .toggleTool(tool))
    }
}
