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
    private var hasInjectedVerticalScrollPagination = false

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

    private func injectVerticalScrollPagination(marginTop: CGFloat, navBarHeight: CGFloat, cfi: String) {
        let marginTopPx = Int(marginTop)
        let bottomMargin = 40
        let rawVpHeight = Int(UIScreen.main.bounds.height) - marginTopPx - Int(navBarHeight) - bottomMargin
        let escapedCfi = cfi.replacingOccurrences(of: "'", with: "\\'")

        let js = """
        (function(){
            var doc = null;
            try { doc = window._view._view._iframeDocument; } catch(e) {}
            if (!doc) {
                try { var f = document.querySelector('iframe'); if(f) doc = f.contentDocument; } catch(e) {}
            }
            if (!doc) return;

            var flow = window._view._view.flow;
            var sections = doc.querySelector('.sections');
            if (!flow || !sections) return;

            var marginTop = \(marginTopPx);

            // Measure line height
            var sc = sections.querySelector('.section-container') || sections;
            var tempP = doc.createElement('p');
            tempP.textContent = 'Xg';
            tempP.style.cssText = 'position:absolute;visibility:hidden;margin:0;padding:0;border:0;';
            sc.appendChild(tempP);
            var lineHeight = tempP.getBoundingClientRect().height;
            tempP.remove();
            if (!lineHeight || lineHeight <= 0) lineHeight = 24;

            function calcVpHeight(raw) {
                var h = lineHeight > 0 ? Math.floor(raw / lineHeight) * lineHeight : raw;
                return h > 0 ? h : raw;
            }

            var vpHeight = calcVpHeight(\(rawVpHeight));

            function buildCSS(mt, h) {
                return 'body.flow-mode-paginated:not(.fixed-layout){margin-top:' + mt + 'px!important;margin-bottom:0!important}'
                    + 'body.flow-mode-paginated:not(.fixed-layout)>.sections{'
                    + 'column-width:unset!important;column-gap:unset!important;column-fill:unset!important;'
                    + 'max-height:' + h + 'px!important;min-height:' + h + 'px!important;'
                    + 'overflow:hidden!important;overflow-x:hidden!important;}'
                    + '#annotation-overlay{display:block!important;}';
            }

            var existing = doc.getElementById('ios-vscroll-override');
            if (existing) existing.remove();
            var s = doc.createElement('style');
            s.id = 'ios-vscroll-override';
            s.textContent = buildCSS(marginTop, vpHeight);
            doc.head.appendChild(s);

            var origCurrentSectionIndexSet = Object.getOwnPropertyDescriptor(
                Object.getPrototypeOf(flow), 'currentSectionIndex'
            ).set;

            function adjustAfterScroll() {
                var sRect = sections.getBoundingClientRect();
                if (!sRect.width || !sRect.height) return;
                var x = sRect.left + sRect.width / 3;

                try {
                    var topR = doc.caretRangeFromPoint(x, sRect.top + 2);
                    if (topR && topR.startContainer && topR.startContainer.nodeType === 3) {
                        var tr = doc.createRange();
                        tr.setStart(topR.startContainer, topR.startOffset);
                        tr.setEnd(topR.startContainer, Math.min(topR.startOffset + 1, topR.startContainer.length));
                        var trects = tr.getClientRects();
                        if (trects.length > 0 && trects[0].top < sRect.top - 1) {
                            sections.scrollTop += Math.ceil(trects[0].bottom - sRect.top);
                            sRect = sections.getBoundingClientRect();
                        }
                    }
                } catch(e) {}

                var bottomClip = 0;
                try {
                    var bottomR = doc.caretRangeFromPoint(x, sRect.bottom - 1);
                    if (bottomR && bottomR.startContainer && bottomR.startContainer.nodeType === 3) {
                        var br = doc.createRange();
                        br.setStart(bottomR.startContainer, bottomR.startOffset);
                        br.setEnd(bottomR.startContainer, Math.min(bottomR.startOffset + 1, bottomR.startContainer.length));
                        var brects = br.getClientRects();
                        if (brects.length > 0 && brects[0].bottom > sRect.bottom + 1) {
                            var visiblePart = sRect.bottom - brects[0].top;
                            if (visiblePart > 0 && visiblePart < lineHeight * 0.8) {
                                bottomClip = Math.ceil(visiblePart);
                            }
                        }
                    }
                } catch(e) {}

                sections.style.clipPath = bottomClip > 0 ? 'inset(0 0 ' + bottomClip + 'px 0)' : '';

                var overlay = doc.getElementById('annotation-overlay');
                if (overlay) {
                    var clipTop = sRect.top;
                    var clipBottom = doc.documentElement.clientHeight - sRect.bottom + bottomClip;
                    overlay.style.clipPath = 'inset(' + clipTop + 'px 0 ' + Math.max(0, clipBottom) + 'px 0)';
                }
            }

            flow.scrollIntoView = function(target, options) {
                var index = null;
                try {
                    var node = (target.startContainer || target);
                    if (node.nodeType === 3) node = node.parentElement;
                    var sectionEl = node.closest('[data-section-index]');
                    if (sectionEl) index = parseInt(sectionEl.getAttribute('data-section-index'));
                } catch(e) {}
                if (index === null) return;

                if (!(options && options.skipHistory)) {
                    flow._nextHistoryPushIsFromNavigation = true;
                }

                origCurrentSectionIndexSet.call(flow, index);

                var range = target;
                if (target.toRange) range = target.toRange();
                var rect;
                try { rect = range.getBoundingClientRect(); } catch(e) { return; }

                var sectionsRect = sections.getBoundingClientRect();
                var newScrollTop = sections.scrollTop + rect.top - sectionsRect.top;
                newScrollTop = Math.floor(newScrollTop / vpHeight) * vpHeight;
                sections.scrollTo({ top: Math.max(0, newScrollTop), left: 0 });
                adjustAfterScroll();
                flow._onViewUpdate();
            };

            flow.canNavigateToPreviousPage = function() {
                if (flow.currentSectionIndex > 0) return true;
                return sections.scrollTop > 0;
            };

            flow.canNavigateToNextPage = function() {
                if (flow.currentSectionIndex < window._view._view.renderers.length - 1) return true;
                return sections.scrollTop < sections.scrollHeight - sections.offsetHeight - 1;
            };

            flow.navigateToPreviousPage = function() {
                if (!flow.canNavigateToPreviousPage()) return;
                if (sections.scrollTop <= 0 && flow.currentSectionIndex > 0) {
                    flow._nextHistoryPushIsFromNavigation = true;
                    origCurrentSectionIndexSet.call(flow, flow.currentSectionIndex - 1);
                    var maxScroll = Math.max(0, sections.scrollHeight - vpHeight);
                    var lastPage = Math.floor(maxScroll / vpHeight) * vpHeight;
                    sections.scrollTo({ top: lastPage, left: 0 });
                    adjustAfterScroll();
                    flow._onViewUpdate();
                    return;
                }
                sections.scrollTo({ top: Math.max(0, sections.scrollTop - vpHeight), left: 0 });
                adjustAfterScroll();
                flow._onViewUpdate();
            };

            flow.navigateToNextPage = function() {
                if (!flow.canNavigateToNextPage()) return;
                var maxScroll = sections.scrollHeight - sections.offsetHeight;
                if (sections.scrollTop >= maxScroll - 1 && flow.currentSectionIndex < window._view._view.renderers.length - 1) {
                    flow._nextHistoryPushIsFromNavigation = true;
                    origCurrentSectionIndexSet.call(flow, flow.currentSectionIndex + 1);
                    sections.scrollTo({ top: 0, left: 0 });
                    adjustAfterScroll();
                    flow._onViewUpdate();
                    return;
                }
                var newTop = sections.scrollTop + vpHeight;
                sections.scrollTo({ top: Math.min(newTop, maxScroll), left: 0 });
                adjustAfterScroll();
                flow._onViewUpdate();
            };

            flow.navigateToFirstPage = function() {
                origCurrentSectionIndexSet.call(flow, 0);
                sections.scrollTo({ top: 0, left: 0 });
                adjustAfterScroll();
                flow._onViewUpdate();
            };

            flow.navigateToLastPage = function() {
                var last = window._view._view.renderers.length - 1;
                origCurrentSectionIndexSet.call(flow, last);
                sections.scrollTo({ top: sections.scrollHeight, left: 0 });
                adjustAfterScroll();
                flow._onViewUpdate();
            };

            flow.canNavigateLeft = function() { return flow.canNavigateToPreviousPage(); };
            flow.canNavigateRight = function() { return flow.canNavigateToNextPage(); };
            flow.navigateLeft = function() { flow.navigateToPreviousPage(); };
            flow.navigateRight = function() { flow.navigateToNextPage(); };

            window._setIOSViewportHeight = function(rawH) {
                vpHeight = calcVpHeight(rawH);
                var style = doc.getElementById('ios-vscroll-override');
                if (style) style.textContent = buildCSS(marginTop, vpHeight);
                requestAnimationFrame(function() {
                    adjustAfterScroll();
                    flow.invalidate();
                });
            };

            window._setIOSViewportGeometry = function(rawH, mt) {
                marginTop = mt;
                vpHeight = calcVpHeight(rawH);
                var style = doc.getElementById('ios-vscroll-override');
                if (style) style.textContent = buildCSS(mt, vpHeight);
                requestAnimationFrame(function() {
                    adjustAfterScroll();
                    flow.invalidate();
                });
            };

            requestAnimationFrame(function(){
                window._view.navigate({pageNumber:'\(escapedCfi)'});
                setTimeout(function() { adjustAfterScroll(); }, 100);
            });
        })();
        """

        webViewHandler.call(javascript: js).subscribe().disposed(by: disposeBag)
        webView?.transform = CGAffineTransform(translationX: 0, y: navBarHeight)
    }

    func updateViewportHeight(navBarHidden: Bool, statusBarHeight: CGFloat, navBarHeight: CGFloat) {
        let marginTopPx = Int(statusBarHeight)
        let bottomMargin = 40
        let rawVpHeight = Int(UIScreen.main.bounds.height) - marginTopPx - (navBarHidden ? 0 : Int(navBarHeight)) - bottomMargin
        let js = "if(window._setIOSViewportHeight) window._setIOSViewportHeight(\(rawVpHeight));"
        webViewHandler.call(javascript: js).subscribe().disposed(by: disposeBag)
    }

    func updateViewportGeometry(statusBarHeight: CGFloat, navBarHeight: CGFloat, navBarHidden: Bool) {
        let marginTopPx = Int(statusBarHeight)
        let bottomMargin = 40
        let rawVpHeight = Int(UIScreen.main.bounds.height) - marginTopPx - (navBarHidden ? 0 : Int(navBarHeight)) - bottomMargin
        let js = "if(window._setIOSViewportGeometry) window._setIOSViewportGeometry(\(rawVpHeight), \(marginTopPx));"
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

                    if !hasInjectedVerticalScrollPagination {
                        hasInjectedVerticalScrollPagination = true
                        let marginTop = parentDelegate?.statusBarHeight ?? 0
                        let navBarHeight = parentDelegate?.navigationBarHeight ?? 0
                        injectVerticalScrollPagination(marginTop: marginTop, navBarHeight: navBarHeight, cfi: cfi)
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
