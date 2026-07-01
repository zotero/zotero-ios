//
//  ReadAloudViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import UIKit

import RxSwift

struct ReadAloudVoiceChange {
    let voice: SpeechVoice
    let preferredLanguage: String?
}

protocol ReadAloudCoordinatorDelegate: AnyObject {
    func showVoicePicker(
        for voice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        userInterfaceStyle: UIUserInterfaceStyle,
        selectionChanged: @escaping (ReadAloudVoiceChange) -> Void
    )
    func showReadAloudOnboarding(
        from presenter: UIViewController,
        language: String?,
        detectedLanguage: String,
        userInterfaceStyle: UIUserInterfaceStyle,
        completion: @escaping (SpeechVoice?) -> Void
    )
    func showReadAloudAddMoreTime(from presenter: UIViewController)
}

protocol ReadAloudViewDelegate: AnyObject {
    var isNavigationBarHidden: Bool { get }
    func readAloudToolbarChanged(height: CGFloat)
    func addReadAloudControlsViewToAnnotationToolbar(view: AnnotationToolbarLeadingView)
    func removeReadAloudControlsViewFromAnnotationToolbar()
    func clearSpeechHighlight()
    func showSpeechHighlighterOverlay(_ overlay: ReadAloudHighlighterOverlayView, isCompact: Bool, speechControlsView: UIView?, animated: Bool)
    func hideSpeechHighlighterOverlay(_ overlay: ReadAloudHighlighterOverlayView)
    func updateSpeechHighlightStyle(tool: AnnotationTool, color: String)
    func presentReadAloudOnboarding(language: String?, detectedLanguage: String, completion: @escaping (SpeechVoice?) -> Void)
    func presentReadAloudVoicePicker(currentVoice: SpeechVoice, language: String?, detectedLanguage: String, selectionChanged: @escaping (ReadAloudVoiceChange) -> Void)
    func presentReadAloudAddMoreTime()
}

final class ReadAloudViewHandler<Delegate: SpeechManagerDelegate> {
    let navbarButtonTag = 4
    /// Size of the headphones checkbox capsule itself.
    private let navbarHeadphonesButtonSize: CGFloat = 38
    /// Transparent horizontal padding added around the capsule so the bar button matches the standard bar button
    /// footprint and lines up evenly with the system bar buttons next to it.
    private var navbarHeadphonesHorizontalPadding: CGFloat {
        max(0, (CheckboxButton.standardNavigationBarButtonSize - navbarHeadphonesButtonSize) / 2)
    }
    private weak var navbarItemContainer: UIView?
    private weak var navbarHeadphonesButtonRef: CheckboxButton?
    private weak var navbarHeadphonesWarningDot: UIView?
    private weak var navbarBridgeView: UIView?
    private var navbarContainerTrailingConstraint: NSLayoutConstraint?
    private unowned let viewController: UIViewController
    private unowned let documentContainer: UIView
    private unowned let dbStorage: DbStorage
    let speechManager: SpeechManager<Delegate>
    private let key: String
    private let libraryId: LibraryIdentifier
    private let disposeBag: DisposeBag

    /// Stores the last speaking position (page index + character offset) so that speech can resume from where it left off
    /// when the user returns to the same page. In-memory only, not persisted to disk.
    private var lastSpeakingPosition: (index: Delegate.Index, characterIndex: Int)?
    /// This flag is used to resume playing read-aloud after a voice has been changed in voice picker.
    private var wasPlayingBeforeVoiceChange: Bool
    private weak var activeOverlay: ReadAloudControlsView<Delegate>?
    private weak var highlighterOverlay: ReadAloudHighlighterOverlayView?
    var isHighlighterOverlayVisible: Bool { highlighterOverlay != nil }
    weak var delegate: ReadAloudViewDelegate?
    var isFormSheet: Bool {
        // Detecting horizontalSizeClass == .compact is not reliable, as the controller can still be shown as formSheet even when horizontalSizeClass is .regular. Therefore the safest way to check
        // whether the controller is shown as form sheet or popover is to check view size. However the controller doesn't have to be visible all the time, so when the controller is not visible,
        // we just check the size class. This way there can be discrepancies between popover/formSheet and overlay/toolbar, but realistically most people won't really see this.
        if UIDevice.current.userInterfaceIdiom == .phone {
            return true
        }
        if let presentedViewController = viewController.presentedViewController {
            return viewController.view.frame.width == presentedViewController.view.frame.width
        } else {
            return viewController.traitCollection.horizontalSizeClass == .compact
        }
    }

    init(
        key: String,
        libraryId: LibraryIdentifier,
        viewController: UIViewController,
        documentContainer: UIView,
        delegate: Delegate,
        dbStorage: DbStorage,
        remoteVoicesController: RemoteVoicesController,
        documentWorkerController: DocumentWorkerController
    ) {
        self.key = key
        self.libraryId = libraryId
        self.viewController = viewController
        self.documentContainer = documentContainer
        self.dbStorage = dbStorage
        wasPlayingBeforeVoiceChange = false
        disposeBag = DisposeBag()
        let language = try? dbStorage.perform(request: ReadSpeechLanguageDbRequest(key: key, libraryId: libraryId), on: .main)
        speechManager = SpeechManager(
            delegate: delegate,
            voiceLanguage: language,
            remoteVoiceTier: Defaults.shared.remoteVoiceTier,
            remoteVoicesController: remoteVoicesController,
            documentWorkerController: documentWorkerController
        )

        speechManager.onSpeakingPositionChanged = { [weak self] pageIndex, characterIndex in
            self?.lastSpeakingPosition = (index: pageIndex, characterIndex: characterIndex)
        }

        speechManager.state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                switch state {
                case .stopped, .outOfCredits:
                    dismissHighlighterOverlay(confirm: true)
                    self.delegate?.clearSpeechHighlight()
                    hideOverlay()
                    reloadReadAloudButton(isSelected: false, state: state, remainingTime: speechManager.remainingTime.value)

                case .speaking, .paused, .initializing, .loading:
                    reloadReadAloudButton(isSelected: true, state: state, remainingTime: speechManager.remainingTime.value)
                    showOverlayIfNeeded(forType: currentOverlayType(controller: self), state: state)
                }
                updateReadAloudButtonMenu(state: state)
            })
            .disposed(by: disposeBag)

        speechManager.remainingTime
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] remainingTime in
                guard let self else { return }
                reloadReadAloudButton(isSelected: nil, state: speechManager.state.value, remainingTime: remainingTime)
            })
            .disposed(by: disposeBag)
    }

    private func updateReadAloudButtonMenu(state: SpeechState) {
        guard let button = navbarHeadphonesButtonRef else { return }
        if !state.isStopped && !state.isOutOfCredits && activeOverlay?.type != .bottomToolbar {
            button.menu = createReadAloudMenu()
            button.showsMenuAsPrimaryAction = true
        } else {
            button.menu = nil
            button.showsMenuAsPrimaryAction = false
        }
    }

    private func createReadAloudMenu() -> UIMenu {
        let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
            if let self {
                completion(makeReadAloudMenuChildren(controller: self))
            } else {
                completion([])
            }
        }
        return UIMenu(children: [deferred])

        func makeReadAloudMenuChildren(controller: ReadAloudViewHandler) -> [UIMenuElement] {
            let firstGroup = UIMenu(title: currentVoiceTitle(controller: controller), options: .displayInline, children: createControls(controller: controller))
            firstGroup.preferredElementSize = .medium
            let speedGroup = UIMenu(title: "Speech Rate", options: [], children: createSpeedActions(controller: controller))
            var elements: [UIMenuElement] = [firstGroup, speedGroup]
            if let warningGroup = createWarningGroupIfNeeded(controller: controller) {
                elements.insert(warningGroup, at: 1)
            }
            return elements
        }

        func createControls(controller: ReadAloudViewHandler) -> [UIMenuElement] {
            var items: [UIMenuElement] = []
            if let remainingTime = controller.speechManager.remainingTime.value, RemainingTimeFormatter.shouldDisplay(remainingTime) {
                items.append(
                    UIAction(
                        title: RemainingTimeFormatter.formatted(remainingTime),
                        image: UIImage(systemName: "clock"),
                        attributes: RemainingTimeFormatter.isWarning(remainingTime) ? [.destructive] : []
                    ) { [weak controller] _ in
                        guard let controller else { return }
                        presentVoicePicker(controller: controller)
                    }
                )
            }
            items.append(UIAction(title: "Switch", image: UIImage(systemName: "person.wave.2")) { [weak controller] _ in
                guard let controller else { return }
                presentVoicePicker(controller: controller)
            })
            items.append(UIAction(title: "Stop", image: UIImage(systemName: "square.fill")) { [weak controller] _ in
                controller?.speechManager.stop()
            })
            return items
        }

        func presentVoicePicker(controller: ReadAloudViewHandler) {
            guard let voice = controller.speechManager.voice else { return }
            wasPlayingBeforeVoiceChange = controller.speechManager.state.value.isSpeakingOrLoading
            controller.speechManager.pause()
            controller.delegate?.presentReadAloudVoicePicker(
                currentVoice: voice,
                language: speechManager.language,
                detectedLanguage: speechManager.detectedLanguage
            ) { [weak controller] change in
                guard let controller else { return }
                processVoiceChange(change, controller: controller)
            }
        }

        func processVoiceChange(_ change: ReadAloudVoiceChange, controller: ReadAloudViewHandler) {
            try? controller.dbStorage.perform(request: SetSpeechLanguageDbRequest(key: controller.key, libraryId: controller.libraryId, language: change.preferredLanguage), on: .main)
            controller.speechManager.set(voice: change.voice, preferredLanguage: change.preferredLanguage)
            if wasPlayingBeforeVoiceChange {
                controller.speechManager.resume()
                wasPlayingBeforeVoiceChange = false
            }
        }

        func createWarningGroupIfNeeded(controller: ReadAloudViewHandler) -> UIMenu? {
            guard let remainingTime = controller.speechManager.remainingTime.value, RemainingTimeFormatter.isWarning(remainingTime) else { return nil }
            var items: [UIMenuElement] = []
            items.append(UIAction(title: "Add More Time", image: nil) { [weak controller] _ in
                controller?.delegate?.presentReadAloudAddMoreTime()
            })
            if remainingTime <= 0, let title = continueWithDowngradeTitle(voice: controller.speechManager.voice) {
                items.append(UIAction(title: title, image: nil) { [weak controller] _ in
                    controller?.speechManager.downgradeVoiceTierAndContinue()
                })
            }
            return UIMenu(title: "", image: nil, options: [.displayInline], children: items)
        }

        func continueWithDowngradeTitle(voice: SpeechVoice?) -> String? {
            switch voice {
            case .remote(let remoteVoice):
                switch remoteVoice.tier {
                case .premium:
                    return "Continue Reading With Standard Voices"

                case .standard:
                    return "Continue Reading With Local Voices"
                }

            case .local, .none:
                return nil
            }
        }

        func createSpeedActions(controller: ReadAloudViewHandler) -> [UIMenuElement] {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3]
            let currentRate = controller.speechManager.speechRateModifier
            return rates.map { rate in
                let title = (formatter.string(from: NSNumber(value: rate)) ?? "") + "×"
                let action = UIAction(title: title) { [weak controller] _ in
                    controller?.speechManager.set(rateModifier: rate)
                }
                if abs(rate - currentRate) < 0.001 {
                    action.state = .on
                }
                return action
            }
        }

        func currentVoiceTitle(controller: ReadAloudViewHandler) -> String {
            guard let voice = controller.speechManager.voice else { return L10n.Speech.unknownVoice }
            switch voice {
            case .local(let value):
                return value.name

            case .remote(let value):
                return value.label
            }
        }
    }

    func createReadAloudButton(isSelected: Bool, isEnabled: Bool = true) -> UIBarButtonItem {
        let button = CheckboxButton(
            image: UIImage(systemName: "headphones", withConfiguration: UIImage.SymbolConfiguration(scale: .large))!.withRenderingMode(.alwaysTemplate),
            contentInsets: NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
            cornerStyle: .capsule
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsLargeContentViewer = true
        button.accessibilityLabel = L10n.Accessibility.Speech.showSpeech
        button.deselectedBackgroundColor = .clear
        button.deselectedTintColor = isEnabled ? Asset.Colors.zoteroBlueWithDarkMode.color : .gray
        button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        button.selectedTintColor = .white
        button.isSelected = isSelected
        button.isEnabled = isEnabled
        button.addAction(
            UIAction(handler: { [weak self] _ in
                self?.toggleReadAloud()
            }),
            for: .touchUpInside
        )

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        let dotSize: CGFloat = 10
        let warningDot = UIView()
        warningDot.translatesAutoresizingMaskIntoConstraints = false
        warningDot.backgroundColor = .systemRed
        warningDot.layer.cornerRadius = dotSize / 2
        warningDot.isUserInteractionEnabled = false
        let state = speechManager.state.value
        warningDot.isHidden = !(!state.isStopped && isRemainingTimeWarning(speechManager.remainingTime.value))
        container.addSubview(warningDot)

        // Pad the capsule horizontally so the bar button matches the standard bar button footprint and lines up
        // evenly with the system bar buttons next to it (which have more surrounding padding than the tight capsule).
        let hPadding = navbarHeadphonesHorizontalPadding
        let trailing = container.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: hPadding)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPadding),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.widthAnchor.constraint(equalToConstant: navbarHeadphonesButtonSize),
            button.heightAnchor.constraint(equalToConstant: navbarHeadphonesButtonSize),
            trailing,
            warningDot.widthAnchor.constraint(equalToConstant: dotSize),
            warningDot.heightAnchor.constraint(equalToConstant: dotSize),
            warningDot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            warningDot.topAnchor.constraint(equalTo: button.topAnchor, constant: 2)
        ])

        let item = UIBarButtonItem(customView: container)
        item.tag = navbarButtonTag
        navbarItemContainer = container
        navbarHeadphonesButtonRef = button
        navbarHeadphonesWarningDot = warningDot
        navbarContainerTrailingConstraint = trailing
        return item
    }

    private func isRemainingTimeWarning(_ remainingTime: TimeInterval?) -> Bool {
        return remainingTime.flatMap({ RemainingTimeFormatter.isWarning($0) }) ?? false
    }

    func toggleReadAloud() {
        if speechManager.state.value.isStopped {
            startReadAloud()
        } else {
            speechManager.stop()
        }
    }

    private func startReadAloud() {
        if Defaults.shared.didShowReadAloudOnboarding {
            startOrResumeSpeech()
        } else {
            delegate?.presentReadAloudOnboarding(
                language: speechManager.language,
                detectedLanguage: speechManager.detectedLanguage
            ) { [weak self] selectedVoice in
                guard let self, let selectedVoice else { return }
                Defaults.shared.didShowReadAloudOnboarding = true
                speechManager.set(voice: selectedVoice, preferredLanguage: nil)
                startOrResumeSpeech()
            }
        }
    }

    func startOrResumeSpeech() {
        if speechManager.state.value.isPaused {
            speechManager.resume()
        } else {
            let startIndex = resolvedStartIndex()
            speechManager.start(startIndex: startIndex)
        }

        func resolvedStartIndex() -> Int {
            guard let lastSpeakingPosition, let currentPage = speechManager.currentPageIndex, lastSpeakingPosition.index == currentPage else { return 0 }
            return lastSpeakingPosition.characterIndex
        }
    }

    private func currentOverlayType(controller: ReadAloudViewHandler<Delegate>) -> ReadAloudControlsView<Delegate>.Kind {
        if controller.isFormSheet {
            return .bottomToolbar
        } else if !(controller.delegate?.isNavigationBarHidden ?? true) {
            return .navbar
        } else {
            return .annotationToolbar
        }
    }

    private func reloadReadAloudButton(isSelected: Bool?, state: SpeechState, remainingTime: TimeInterval?) {
        if let isSelected {
            navbarHeadphonesButtonRef?.isSelected = isSelected
        }
        navbarHeadphonesWarningDot?.isHidden = !(!state.isStopped && isRemainingTimeWarning(remainingTime))
    }

    func readAloudControlsShouldChange(isNavbarHidden: Bool) {
        guard activeOverlay != nil else { return }
        let type: ReadAloudControlsView<Delegate>.Kind
        if isFormSheet {
            type = .bottomToolbar
        } else if !isNavbarHidden {
            type = .navbar
        } else {
            type = .annotationToolbar
        }
        let state = speechManager.state.value
        showOverlayIfNeeded(forType: type, state: state)
        updateReadAloudButtonMenu(state: state)
        repositionHighlighterOverlayIfNeeded()
    }

    private func repositionHighlighterOverlayIfNeeded() {
        guard let oldOverlay = highlighterOverlay else { return }
        delegate?.hideSpeechHighlighterOverlay(oldOverlay)
        let newOverlay = ReadAloudHighlighterOverlayView(
            isCompact: isFormSheet,
            annotationTool: oldOverlay.selectedAnnotationTool,
            annotationColor: oldOverlay.selectedColor
        )
        newOverlay.update(text: oldOverlay.currentText)
        newOverlay.deleteAction = oldOverlay.deleteAction
        newOverlay.backwardAction = oldOverlay.backwardAction
        newOverlay.forwardAction = oldOverlay.forwardAction
        newOverlay.skipBackwardAction = oldOverlay.skipBackwardAction
        newOverlay.skipForwardAction = oldOverlay.skipForwardAction
        newOverlay.annotationToolChanged = oldOverlay.annotationToolChanged
        newOverlay.annotationColorChanged = oldOverlay.annotationColorChanged
        newOverlay.onMenuPresented = oldOverlay.onMenuPresented
        newOverlay.onMenuDismissed = oldOverlay.onMenuDismissed
        highlighterOverlay = newOverlay
        delegate?.showSpeechHighlighterOverlay(newOverlay, isCompact: isFormSheet, speechControlsView: activeOverlay, animated: false)
    }

    private func showOverlayIfNeeded(forType type: ReadAloudControlsView<Delegate>.Kind, state: SpeechState) {
        guard state != .stopped, activeOverlay?.type != type else { return }

        if let activeOverlay {
            remove(activeControls: activeOverlay)
        }

        let highlighterAction: (() -> Void)?
        switch type {
        case .navbar, .bottomToolbar:
            highlighterAction = { [weak self] in self?.toggleHighlighterOverlay() }

        case .annotationToolbar:
            highlighterAction = nil
        }
        let playAction: () -> Void = { [weak self] in self?.startOrResumeSpeech() }
        let overlay = ReadAloudControlsView(
            type: type,
            speechManager: speechManager,
            playAction: playAction,
            settingsMenu: createReadAloudMenu(),
            highlighterAction: highlighterAction
        )
        activeOverlay = overlay

        switch type {
        case .bottomToolbar:
            showAsBottomToolbar()

        case .annotationToolbar:
            delegate?.addReadAloudControlsViewToAnnotationToolbar(view: overlay)

        case .navbar:
            showInNavigationBar()
        }

        func showAsBottomToolbar() {
            viewController.view.insertSubview(overlay, belowSubview: documentContainer)

            NSLayoutConstraint.activate([
                overlay.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor)
            ])

            viewController.view.layoutIfNeeded()
            delegate?.readAloudToolbarChanged(height: overlay.frame.height)
            viewController.view.layoutIfNeeded()
        }

        func showInNavigationBar() {
            guard let container = navbarItemContainer,
                  let button = navbarHeadphonesButtonRef,
                  let oldTrailing = navbarContainerTrailingConstraint
            else { return }

            oldTrailing.isActive = false

            let bridge = UIView()
            bridge.translatesAutoresizingMaskIntoConstraints = false
            bridge.backgroundColor = .systemGray6
            container.insertSubview(bridge, belowSubview: button)
            navbarBridgeView = bridge

            overlay.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(overlay)

            let newTrailing = container.trailingAnchor.constraint(equalTo: overlay.trailingAnchor)
            NSLayoutConstraint.activate([
                bridge.leadingAnchor.constraint(equalTo: button.centerXAnchor),
                bridge.topAnchor.constraint(equalTo: container.topAnchor),
                bridge.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bridge.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                overlay.leadingAnchor.constraint(equalTo: button.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: container.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                newTrailing
            ])
            navbarContainerTrailingConstraint = newTrailing
        }
    }

    private func toggleHighlighterOverlay() {
        if highlighterOverlay != nil {
            dismissHighlighterOverlay(confirm: true)
            return
        }
        guard let result = speechManager.startHighlightSession() else { return }
        let overlay = ReadAloudHighlighterOverlayView(
            isCompact: isFormSheet,
            annotationTool: speechManager.highlightAnnotationTool,
            annotationColor: speechManager.highlightAnnotationColor
        )
        overlay.update(text: result.text)
        overlay.deleteAction = { [weak self] in
            self?.dismissHighlighterOverlay(confirm: false)
        }
        overlay.backwardAction = { [weak self] in
            guard let self, let result = speechManager.moveHighlightBackward() else { return }
            self.highlighterOverlay?.update(text: result.text)
        }
        overlay.forwardAction = { [weak self] in
            guard let self, let result = speechManager.moveHighlightForward() else { return }
            self.highlighterOverlay?.update(text: result.text)
        }
        overlay.skipBackwardAction = { [weak self] in
            guard let self, let result = speechManager.extendHighlightBackward() else { return }
            self.highlighterOverlay?.update(text: result.text)
        }
        overlay.skipForwardAction = { [weak self] in
            guard let self, let result = speechManager.extendHighlightForward() else { return }
            self.highlighterOverlay?.update(text: result.text)
        }
        overlay.annotationToolChanged = { [weak self] tool in
            guard let self else { return }
            speechManager.setHighlightAnnotationTool(tool)
            delegate?.updateSpeechHighlightStyle(tool: tool, color: speechManager.highlightAnnotationColor)
        }
        overlay.annotationColorChanged = { [weak self] color in
            guard let self else { return }
            speechManager.setHighlightAnnotationColor(color)
            delegate?.updateSpeechHighlightStyle(tool: speechManager.highlightAnnotationTool, color: color)
        }
        overlay.onMenuPresented = { [weak self] in
            self?.speechManager.stopHighlightInactivityTimer()
        }
        overlay.onMenuDismissed = { [weak self] in
            self?.speechManager.startHighlightInactivityTimer()
        }
        speechManager.onHighlightSessionTimedOut = { [weak self] in
            self?.dismissHighlighterOverlay(confirm: true)
        }
        highlighterOverlay = overlay
        delegate?.showSpeechHighlighterOverlay(overlay, isCompact: isFormSheet, speechControlsView: activeOverlay, animated: true)
    }

    private func dismissHighlighterOverlay(confirm: Bool) {
        if confirm {
            speechManager.endHighlightSession()
        } else {
            speechManager.cancelHighlightSession()
        }
        speechManager.onHighlightSessionTimedOut = nil
        guard let overlay = highlighterOverlay else { return }
        delegate?.hideSpeechHighlighterOverlay(overlay)
        highlighterOverlay = nil
    }

    func confirmActiveHighlightSession() {
        guard highlighterOverlay != nil else { return }
        dismissHighlighterOverlay(confirm: true)
    }

    func cancelActiveHighlightSession() {
        guard highlighterOverlay != nil else { return }
        dismissHighlighterOverlay(confirm: false)
    }

    func performHighlighterAction(_ action: (ReadAloudHighlighterOverlayView) -> Void) {
        guard let overlay = highlighterOverlay else { return }
        action(overlay)
    }

    private func hideOverlay() {
        guard let activeOverlay else { return }
        remove(activeControls: activeOverlay)
        self.activeOverlay = nil
        viewController.view.layoutIfNeeded()
    }

    private func remove(activeControls: ReadAloudControlsView<Delegate>) {
        switch activeControls.type {
        case .navbar:
            navbarBridgeView?.removeFromSuperview()
            navbarBridgeView = nil
            activeControls.removeFromSuperview()
            if let container = navbarItemContainer, let button = navbarHeadphonesButtonRef {
                navbarContainerTrailingConstraint?.isActive = false
                let restored = container.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: navbarHeadphonesHorizontalPadding)
                restored.isActive = true
                navbarContainerTrailingConstraint = restored
            }

        case .bottomToolbar:
            delegate?.readAloudToolbarChanged(height: 0)
            activeControls.removeFromSuperview()

        case .annotationToolbar:
            delegate?.removeReadAloudControlsViewFromAnnotationToolbar()
        }
    }
}
