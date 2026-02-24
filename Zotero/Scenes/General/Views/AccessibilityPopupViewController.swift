//
//  AccessibilityPopupViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 30.05.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import NaturalLanguage
import UIKit

import AVFAudio
import RxCocoa
import RxSwift

import CocoaLumberjackSwift

struct AccessibilityPopupVoiceChange {
    let voice: SpeechVoice
    let voiceLanguage: String
    let preferredLanguage: String?
}

protocol AccessibilityPopoupCoordinatorDelegate: AnyObject {
    func showVoicePicker(
        for voice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        userInterfaceStyle: UIUserInterfaceStyle,
        selectionChanged: @escaping (AccessibilityPopupVoiceChange) -> Void
    )
}

final class AccessibilityPopupViewController<Delegate: SpeechManagerDelegate>: UIViewController, UIPopoverPresentationControllerDelegate {
    private unowned let speechManager: SpeechManager<Delegate>
    private let speedNumberFormatter: NumberFormatter
    private let disposeBag: DisposeBag
    private let readerAction: () -> Void
    private let dismissAction: () -> Void
    private let isFormSheet: () -> Bool
    private let voiceChangeAction: (AccessibilityPopupVoiceChange) -> Void
    private var containerTop: NSLayoutConstraint!
    private var containerHeight: NSLayoutConstraint!
    private weak var speechButton: UIButton!
    private weak var speechContainer: UIView!
    private weak var voiceButton: VoiceButtonView!
    private weak var speedButton: UIButton!
    private weak var controlsView: AccessibilitySpeechControlsStackView<Delegate>!
    private var speechButtonBottom: NSLayoutConstraint!
    private var speechContainerBottom: NSLayoutConstraint!
    private var currentHeight: CGFloat {
        return speechManager.state.value.isStopped ? baseHeight(isPopover: !isFormSheet()) : expandedHeight(isPopover: !isFormSheet())
    }

    weak var coordinatorDelegate: AccessibilityPopoupCoordinatorDelegate?

    init(
        speechManager: SpeechManager<Delegate>,
        isFormSheet: @escaping () -> Bool,
        readerAction: @escaping () -> Void,
        dismissAction: @escaping () -> Void,
        voiceChangeAction: @escaping (AccessibilityPopupVoiceChange) -> Void
    ) {
        self.speechManager = speechManager
        self.isFormSheet = isFormSheet
        self.readerAction = readerAction
        self.dismissAction = dismissAction
        self.voiceChangeAction = voiceChangeAction
        speedNumberFormatter = NumberFormatter()
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
        speedNumberFormatter.numberStyle = .decimal
        speedNumberFormatter.minimumFractionDigits = 0
        speedNumberFormatter.maximumFractionDigits = 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        createView()
        updatePopup(toHeight: currentHeight)
        observeState()
        
        if speechManager.state.value == .stopped {
            speechManager.start()
        }

        func createView() {
            // Speech container
            let speechContainer = UIView()
            speechContainer.translatesAutoresizingMaskIntoConstraints = false
            speechContainer.backgroundColor = Asset.Colors.navbarBackground.color
            speechContainer.layer.cornerRadius = 13
            speechContainer.layer.masksToBounds = true
            speechContainer.isHidden = speechManager.state.value.isStopped

            let titleLabel = UILabel()
            titleLabel.text = L10n.Accessibility.Speech.title
            titleLabel.font = .preferredFont(forTextStyle: .headline)

            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            var xConfiguration = UIButton.Configuration.filled()
            xConfiguration.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration.init(pointSize: titleLabel.font.pointSize, weight: .medium, scale: .medium))
            xConfiguration.baseBackgroundColor = .systemGray5
            xConfiguration.baseForegroundColor = .darkGray
            xConfiguration.cornerStyle = .capsule
            let xButton = UIButton(configuration: xConfiguration)
            xButton.setContentHuggingPriority(.required, for: .vertical)
            xButton.setContentHuggingPriority(.required, for: .horizontal)
            xButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            xButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.stop() }), for: .touchUpInside)

            let titleStackView = UIStackView(arrangedSubviews: [titleLabel, spacer, xButton])
            titleStackView.axis = .horizontal
            titleStackView.alignment = .fill
            titleStackView.distribution = .fill
            titleStackView.setContentHuggingPriority(.required, for: .vertical)
            titleStackView.translatesAutoresizingMaskIntoConstraints = false
            speechContainer.addSubview(titleStackView)

            let controlsView = AccessibilitySpeechControlsStackView(speechManager: speechManager)
            controlsView.setContentHuggingPriority(.defaultLow, for: .vertical)
            speechContainer.addSubview(controlsView)

            let voiceButton = VoiceButtonView()
            voiceButton.title = speechManager.voice.flatMap({ voiceTitle(from: $0) }) ?? L10n.Accessibility.Speech.unknownVoice
            voiceButton.isEnabled = false
            voiceButton.setContentHuggingPriority(.required, for: .vertical)
            voiceButton.addAction(UIAction(handler: { [weak self] _ in self?.showVoiceOptions() }), for: .touchUpInside)

            let spacer2 = UIView()
            spacer2.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer2.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            spacer2.widthAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true

            let speedActions = [2, 1.75, 1.5, 1.25, 1, 0.75].map({ [unowned self] val in UIAction(title: formatted(modifier: val), handler: { [weak self] _ in self?.set(rateModifier: val) }) })
            var speedConfiguration = UIButton.Configuration.filled()
            speedConfiguration.title = formatted(modifier: speechManager.speechRateModifier)
            speedConfiguration.baseBackgroundColor = .systemGray5
            speedConfiguration.baseForegroundColor = .label
            speedConfiguration.cornerStyle = .capsule
            speedConfiguration.contentInsets = .init(top: 6, leading: 10, bottom: 6, trailing: 10)
            let speedButton = UIButton(configuration: speedConfiguration)
            speedButton.isEnabled = voiceButton.isEnabled
            speedButton.setContentHuggingPriority(.required, for: .vertical)
            speedButton.setContentHuggingPriority(.required, for: .horizontal)
            speedButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            speedButton.setContentCompressionResistancePriority(.required, for: .vertical)
            speedButton.showsMenuAsPrimaryAction = true
            speedButton.menu = UIMenu(title: "Speech Rate", children: speedActions)

            let additionalControlsStackView = UIStackView(arrangedSubviews: [voiceButton, spacer2, speedButton])
            additionalControlsStackView.axis = .horizontal
            additionalControlsStackView.alignment = .fill
            additionalControlsStackView.distribution = .fill
            additionalControlsStackView.setContentHuggingPriority(.required, for: .vertical)
            additionalControlsStackView.translatesAutoresizingMaskIntoConstraints = false
            speechContainer.addSubview(additionalControlsStackView)

            self.controlsView = controlsView
            self.voiceButton = voiceButton
            self.speedButton = speedButton
            self.speechContainer = speechContainer

            // Reader button
            var mainButtonsAttributeContainer = AttributeContainer()
            mainButtonsAttributeContainer.font = .preferredFont(for: .body, weight: .medium)

            var readerConfiguration = UIButton.Configuration.filled()
            readerConfiguration.cornerStyle = .capsule
            readerConfiguration.imagePadding = 12
            readerConfiguration.image = UIImage(systemName: "text.page.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
            readerConfiguration.attributedTitle = AttributedString(L10n.Accessibility.showReader, attributes: mainButtonsAttributeContainer)
            readerConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 0, bottom: 14, trailing: 0)
            readerConfiguration.baseBackgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
            readerConfiguration.baseForegroundColor = .white
            let readerButton = UIButton(configuration: readerConfiguration)
            readerButton.translatesAutoresizingMaskIntoConstraints = false
            readerButton.accessibilityLabel = L10n.Accessibility.showReaderAccessibilityLabel
            readerButton.setContentCompressionResistancePriority(.required, for: .vertical)
            readerButton.addAction(UIAction(handler: { [weak self] _ in self?.readerAction() }), for: .touchUpInside)

            // Speech button

            var speechConfiguration = UIButton.Configuration.filled()
            speechConfiguration.cornerStyle = .capsule
            speechConfiguration.imagePadding = 12
            speechConfiguration.image = UIImage(systemName: "headphones", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
            speechConfiguration.attributedTitle = AttributedString(L10n.Accessibility.showSpeech, attributes: mainButtonsAttributeContainer)
            speechConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 0, bottom: 14, trailing: 0)
            speechConfiguration.baseBackgroundColor = .systemGray5
            speechConfiguration.baseForegroundColor = .label
            let speechButton = UIButton(configuration: speechConfiguration)
            speechButton.isHidden = !speechManager.state.value.isStopped
            speechButton.translatesAutoresizingMaskIntoConstraints = false
            speechButton.accessibilityLabel = L10n.Accessibility.showSpeechAccessibilityLabel
            speechButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.start() }), for: .touchUpInside)
            self.speechButton = speechButton

            speechButtonBottom = view.safeAreaLayoutGuide.bottomAnchor.constraint(greaterThanOrEqualTo: speechButton.bottomAnchor, constant: 16)
            speechContainerBottom = view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: speechContainer.bottomAnchor, constant: 16)

            // Container
            // We use additional container for the whole UI so that we can we can mimic the .pageSheet presentation in .formSheet,
            // because the .popover always adopts to .formSheet when window size changes and we can't force .pageSheet.
            let container = UIView()
            container.backgroundColor = .systemGroupedBackground
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(speechButton)
            container.addSubview(readerButton)
            container.addSubview(speechContainer)
            containerHeight = container.heightAnchor.constraint(equalToConstant: currentHeight)
            containerTop = container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
            view.addSubview(container)

            // Button which is used to dismiss on tap on the "fake background" area when in .pageSheet mode.
            let dismissButton = UIButton()
            dismissButton.translatesAutoresizingMaskIntoConstraints = false
            dismissButton.addAction(UIAction(handler: { [weak self] _ in self?.presentingViewController?.dismiss(animated: true) }), for: .touchUpInside)
            view.addSubview(dismissButton)

            let bottomToActivate = speechManager.state.value.isStopped ? speechButtonBottom : speechContainerBottom

            var toActivate = [
                // Container
                container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                dismissButton.topAnchor.constraint(equalTo: view.topAnchor),
                dismissButton.bottomAnchor.constraint(equalTo: container.topAnchor),
                dismissButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                dismissButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                // Reader Button
                readerButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                container.trailingAnchor.constraint(equalTo: readerButton.trailingAnchor, constant: 16),
                readerButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
                // Speech button
                speechButton.topAnchor.constraint(equalTo: readerButton.bottomAnchor, constant: 16),
                speechButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                container.trailingAnchor.constraint(equalTo: speechButton.trailingAnchor, constant: 16),
                speechButton.heightAnchor.constraint(equalTo: readerButton.heightAnchor),
                // Speech container
                speechContainer.topAnchor.constraint(equalTo: readerButton.bottomAnchor, constant: 16),
                speechContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                container.trailingAnchor.constraint(equalTo: speechContainer.trailingAnchor, constant: 16),
                bottomToActivate!,
                // Speech Title
                titleStackView.topAnchor.constraint(equalTo: speechContainer.topAnchor, constant: 16),
                titleStackView.leadingAnchor.constraint(equalTo: speechContainer.leadingAnchor, constant: 16),
                speechContainer.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor, constant: 16),
                // Speech Controls
                controlsView.leadingAnchor.constraint(equalTo: speechContainer.leadingAnchor, constant: 16),
                speechContainer.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: 16),
                titleStackView.bottomAnchor.constraint(equalTo: controlsView.topAnchor),
                // Speech Additional Controls
                controlsView.bottomAnchor.constraint(equalTo: additionalControlsStackView.topAnchor),
                additionalControlsStackView.leadingAnchor.constraint(equalTo: speechContainer.leadingAnchor, constant: 16),
                speechContainer.trailingAnchor.constraint(equalTo: additionalControlsStackView.trailingAnchor, constant: 16),
                speechContainer.bottomAnchor.constraint(equalTo: additionalControlsStackView.bottomAnchor, constant: 16)
            ]

            if isFormSheet() {
                toActivate.append(containerHeight)
            } else {
                toActivate.append(containerTop)
            }

            NSLayoutConstraint.activate(toActivate)
        }

        func observeState() {
            speechManager.state
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] state in
                    guard let self else { return }
                    process(state: state)
                })
                .disposed(by: disposeBag)
            
            speechManager.remainingTime
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] remainingTime in
                    guard let self else { return }
                    updateRemainingTime(remainingTime)
                })
                .disposed(by: disposeBag)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissAction()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updatePopup(toHeight: currentHeight)
    }

    // MARK: - Keyboard Commands

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = [
            .init(title: L10n.Accessibility.Speech.forward, action: #selector(speechForwardByParagraph), input: UIKeyCommand.inputRightArrow, modifierFlags: []),
            .init(title: L10n.Accessibility.Speech.backward, action: #selector(speechBackwardByParagraph), input: UIKeyCommand.inputLeftArrow, modifierFlags: []),
            .init(title: L10n.Accessibility.Speech.forward, action: #selector(speechForwardBySentence), input: UIKeyCommand.inputRightArrow, modifierFlags: [.alternate]),
            .init(title: L10n.Accessibility.Speech.backward, action: #selector(speechBackwardBySentence), input: UIKeyCommand.inputLeftArrow, modifierFlags: [.alternate])
        ]
        if speechManager.state.value.isSpeaking || speechManager.state.value.isPaused {
            let title = speechManager.state.value.isSpeaking ? L10n.Accessibility.Speech.pause : L10n.Accessibility.Speech.play
            commands.append(.init(title: title, action: #selector(togglePlayPause), input: " ", modifierFlags: []))
        }
        return commands
    }

    @objc private func speechForwardByParagraph() {
        speechManager.forward(by: .paragraph)
    }

    @objc private func speechBackwardByParagraph() {
        speechManager.backward(by: .paragraph)
    }

    @objc private func speechForwardBySentence() {
        speechManager.forward(by: .sentence)
    }

    @objc private func speechBackwardBySentence() {
        speechManager.backward(by: .sentence)
    }

    @objc private func togglePlayPause() {
        if speechManager.state.value.isSpeaking {
            speechManager.pause()
        } else if speechManager.state.value.isPaused {
            speechManager.resume()
        }
    }

    // MARK: - Actions

    private func voiceTitle(from voice: SpeechVoice) -> String {
        switch voice {
        case .local(let voice):
            return voice.name
            
        case .remote(let voice):
            return voice.label
        }
    }

    private func showVoiceOptions() {
        guard let voice = speechManager.voice else { return }
        if speechManager.state.value.isSpeaking {
            speechManager.pause()
        }
        coordinatorDelegate?.showVoicePicker(
            for: voice,
            language: speechManager.language,
            detectedLanguage: speechManager.detectedLanguage,
            userInterfaceStyle: overrideUserInterfaceStyle,
            selectionChanged: { [weak self] change in
                self?.update(voice: change.voice)
                self?.voiceChangeAction(change)
            }
        )
    }

    private func formatted(modifier: Float) -> String {
        return (speedNumberFormatter.string(from: NSNumber(value: modifier)) ?? "") + "x"
    }
    
    private func updateRemainingTime(_ remainingTime: TimeInterval?) {
        if voiceButton.title == L10n.Accessibility.Speech.unknownVoice, let voice = speechManager.voice {
            voiceButton.title = voiceTitle(from: voice)
        }
        voiceButton.remainingTime = remainingTime
    }

    private func set(rateModifier: Float) {
        speechManager.set(rateModifier: rateModifier)
        speedButton.configuration?.title = formatted(modifier: rateModifier)
    }

    func baseHeight(isPopover: Bool) -> CGFloat {
        return isPopover ? 130 : 176
    }

    func expandedHeight(isPopover: Bool) -> CGFloat {
        return isPopover ? 262 : 300
    }

    // MARK: - SpeechManager State

    private func process(state: SpeechState) {
        guard let data = updateToState() else { return }
        view.layoutIfNeeded()
        data.toShow.alpha = 0
        data.toShow.isHidden = false
        UIView.animate(withDuration: 0.2, animations: {
            data.toShow.alpha = 1
            data.toHide.alpha = 0
            self.updatePopup(toHeight: data.height)
            self.view.layoutIfNeeded()
        }, completion: { _ in
            data.toHide.isHidden = true
        })

        func updateToState() -> (toHide: UIView, toShow: UIView, height: CGFloat)? {
            switch state {
            case .loading:
                if voiceButton.isEnabled {
                    voiceButton.isEnabled = false
                    speedButton.isEnabled = false
                }
                return loadingSpeakingContainerState()

            case .speaking:
                if !voiceButton.isEnabled, let voice = speechManager.voice {
                    // TODO: - change title when page changes
                    voiceButton.title = voiceTitle(from: voice)
                    voiceButton.isEnabled = true
                    speedButton.isEnabled = true
                }
                return loadingSpeakingContainerState()

            case .stopped:
                guard speechButton.isHidden else { return nil }
                speechContainerBottom.isActive = false
                speechButtonBottom.isActive = true
                return (speechContainer, speechButton, baseHeight(isPopover: !isFormSheet()))

            case .paused, .outOfCredits:
                return nil
            }
        }

        func loadingSpeakingContainerState() -> (toHide: UIView, toShow: UIView, height: CGFloat)? {
            guard speechContainer.isHidden else { return nil }
            speechContainerBottom.isActive = true
            speechButtonBottom.isActive = false
            return (speechButton, speechContainer, expandedHeight(isPopover: !isFormSheet()))
        }
    }

    private func updatePopup(toHeight height: CGFloat) {
        if isFormSheet() {
            containerTop?.isActive = false
            containerHeight?.isActive = true
            containerHeight?.constant = height
        } else {
            containerHeight?.isActive = false
            containerTop?.isActive = true
            preferredContentSize = CGSize(width: 350, height: height)
        }
    }

    private func update(voice: SpeechVoice) {
        voiceButton.title = voiceTitle(from: voice)
    }

    // MARK: - UIPopoverPresentationControllerDelegate

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .formSheet
    }
}
// MARK: - VoiceButtonView

private final class VoiceButtonView: UIControl {
    /// Threshold in seconds below which the remaining time indicator turns red
    private static let warningThresholdSeconds: TimeInterval = 180
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .label
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    
    private let clockImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "clock"))
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()
    
    /// Tracks the last displayed minute value to avoid unnecessary updates
    private var lastDisplayedMinute: Int?
    
    var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }
    
    var remainingTime: TimeInterval? {
        didSet {
            // Hide if no time or if time exceeds 90 days
            guard let time = remainingTime, RemainingTimeFormatter.shouldDisplay(time) else {
                clockImageView.isHidden = true
                timeLabel.isHidden = true
                lastDisplayedMinute = nil
                return
            }
            
            let totalMinutes = Int(ceil(time / 60))
            guard lastDisplayedMinute != totalMinutes else { return }
            lastDisplayedMinute = totalMinutes
            
            clockImageView.isHidden = false
            timeLabel.isHidden = false
            timeLabel.text = RemainingTimeFormatter.formatted(time)
            
            let timeColor: UIColor = time < Self.warningThresholdSeconds ? .systemRed : .secondaryLabel
            clockImageView.tintColor = timeColor
            timeLabel.textColor = timeColor
        }
    }
    
    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1.0 : 0.5
        }
    }
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.alpha = self.isHighlighted ? 0.7 : (self.isEnabled ? 1.0 : 0.5)
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .systemGray5
        layer.cornerRadius = 16
        
        let stackView = UIStackView(arrangedSubviews: [titleLabel, clockImageView, timeLabel])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isUserInteractionEnabled = false
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
        
        clockImageView.isHidden = true
        timeLabel.isHidden = true
    }
}
