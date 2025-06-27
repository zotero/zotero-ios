//
//  AccessibilityPopupViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 30.05.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

final class AccessibilityPopupViewController<Delegate: SpeechmanagerDelegate>: UIViewController {
    let baseHeight: CGFloat = 130
    let expandedHeight: CGFloat = 262
    private unowned let speechManager: SpeechManager<Delegate>
    private let speedNumberFormatter: NumberFormatter
    private let disposeBag: DisposeBag
    private let readerAction: () -> Void

    private weak var speechButton: UIButton!
    private weak var speechContainer: UIView!
    private weak var speedButton: UIButton!
    private weak var playButton: UIButton!
    private weak var pauseButton: UIButton!
    private weak var backwardButton: UIButton!
    private weak var forwardButton: UIButton!
    private weak var activityIndicator: UIActivityIndicatorView!
    private var speechButtonBottom: NSLayoutConstraint!
    private var speechContainerBottom: NSLayoutConstraint!

    init(speechManager: SpeechManager<Delegate>, readerAction: @escaping () -> Void) {
        self.speechManager = speechManager
        self.readerAction = readerAction
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

        view.backgroundColor = .systemGroupedBackground
        createView()
        observeState()

        func createView() {
            // Speech container
            let speechContainer = UIView()
            speechContainer.translatesAutoresizingMaskIntoConstraints = false
            speechContainer.backgroundColor = .systemBackground
            speechContainer.layer.cornerRadius = 13
            speechContainer.layer.masksToBounds = true
            speechContainer.isHidden = !speechManager.isSpeaking
            view.addSubview(speechContainer)

            let titleLabel = UILabel()
            titleLabel.text = L10n.Accessibility.Speech.title
            titleLabel.font = .preferredFont(forTextStyle: .headline)

            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let speedActions = [2, 1.75, 1.5, 1.25, 1, 0.75].map({ [unowned self] val in UIAction(title: formatted(modifier: val), handler: { [weak self] _ in self?.set(rateModifier: val) }) })
            var speedConfiguration = UIButton.Configuration.filled()
            speedConfiguration.title = formatted(modifier: Defaults.shared.speechRateModifier)
            speedConfiguration.baseBackgroundColor = .systemGray5
            speedConfiguration.baseForegroundColor = .label
            speedConfiguration.cornerStyle = .capsule
            speedConfiguration.contentInsets = .init(top: 6, leading: 16, bottom: 6, trailing: 16)
            let speedButton = UIButton(configuration: speedConfiguration)
            speedButton.setContentHuggingPriority(.required, for: .vertical)
            speedButton.setContentHuggingPriority(.required, for: .horizontal)
            speedButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            speedButton.showsMenuAsPrimaryAction = true
            speedButton.menu = UIMenu(title: "Speech Rate", children: speedActions)

            let titleStackView = UIStackView(arrangedSubviews: [titleLabel, spacer, speedButton])
            titleStackView.axis = .horizontal
            titleStackView.alignment = .fill
            titleStackView.distribution = .fill
            titleStackView.setContentHuggingPriority(.required, for: .vertical)
            titleStackView.translatesAutoresizingMaskIntoConstraints = false
            speechContainer.addSubview(titleStackView)

            let imageConfiguration = UIImage.SymbolConfiguration.init(scale: .large)

            var playConfig = UIButton.Configuration.plain()
            playConfig.image = UIImage(systemName: "play.fill", withConfiguration: imageConfiguration)
            playConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 22, bottom: 8, trailing: 22)
            let playButton = UIButton(configuration: playConfig)
            playButton.accessibilityLabel = L10n.Accessibility.Speech.play
            playButton.isHidden = speechManager.isSpeaking
            playButton.addAction(UIAction(handler: { [weak self] _ in self?.playOrResume() }), for: .touchUpInside)

            var pauseConfig = UIButton.Configuration.plain()
            pauseConfig.image = UIImage(systemName: "pause.fill", withConfiguration: imageConfiguration)
            let pauseButton = UIButton(configuration: pauseConfig)
            pauseButton.accessibilityLabel = L10n.Accessibility.Speech.pause
            pauseButton.isHidden = !speechManager.isSpeaking
            pauseButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.pause() }), for: .touchUpInside)

            var forwardConfig = UIButton.Configuration.plain()
            forwardConfig.image = UIImage(systemName: "plus.arrow.trianglehead.clockwise", withConfiguration: imageConfiguration)
            let forwardButton = UIButton(configuration: forwardConfig)
            forwardButton.accessibilityLabel = L10n.Accessibility.Speech.forward
            forwardButton.isEnabled = speechManager.isSpeaking
            forwardButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.forward() }), for: .touchUpInside)

            var backwardConfig = UIButton.Configuration.plain()
            backwardConfig.image = UIImage(systemName: "minus.arrow.trianglehead.counterclockwise", withConfiguration: imageConfiguration)
            let backwardButton = UIButton(configuration: backwardConfig)
            backwardButton.accessibilityLabel = L10n.Accessibility.Speech.backward
            backwardButton.isEnabled = speechManager.isSpeaking
            backwardButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.backward() }), for: .touchUpInside)

            let activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.hidesWhenStopped = true

            let controlsStackView = UIStackView(arrangedSubviews: [backwardButton, playButton, pauseButton, activityIndicator, forwardButton])
            controlsStackView.axis = .horizontal
            controlsStackView.alignment = .center
            controlsStackView.distribution = .fillEqually
            controlsStackView.setContentHuggingPriority(.defaultLow, for: .vertical)
            controlsStackView.translatesAutoresizingMaskIntoConstraints = false
            speechContainer.addSubview(controlsStackView)

            self.playButton = playButton
            self.pauseButton = pauseButton
            self.forwardButton = forwardButton
            self.backwardButton = backwardButton
            self.activityIndicator = activityIndicator
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
            readerConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
            readerConfiguration.baseBackgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
            readerConfiguration.baseForegroundColor = .white
            let readerButton = UIButton(configuration: readerConfiguration)
            readerButton.translatesAutoresizingMaskIntoConstraints = false
            readerButton.accessibilityLabel = L10n.Accessibility.showReaderAccessibilityLabel
            readerButton.addAction(UIAction(handler: { [weak self] _ in self?.readerAction() }), for: .touchUpInside)
            view.addSubview(readerButton)

            // Speech button

            var speechConfiguration = UIButton.Configuration.filled()
            speechConfiguration.cornerStyle = .capsule
            speechConfiguration.imagePadding = 12
            speechConfiguration.image = UIImage(systemName: "headphones", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
            speechConfiguration.attributedTitle = AttributedString(L10n.Accessibility.showSpeech, attributes: mainButtonsAttributeContainer)
            speechConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
            speechConfiguration.baseBackgroundColor = .systemGray5
            speechConfiguration.baseForegroundColor = .label
            let speechButton = UIButton(configuration: speechConfiguration)
            speechButton.isHidden = speechManager.isSpeaking
            speechButton.translatesAutoresizingMaskIntoConstraints = false
            speechButton.accessibilityLabel = L10n.Accessibility.showSpeechAccessibilityLabel
            speechButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.start() }), for: .touchUpInside)
            view.addSubview(speechButton)
            self.speechButton = speechButton

            // Constraints

            speechButtonBottom = view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: speechButton.bottomAnchor, constant: 16)
            speechContainerBottom = view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: speechContainer.bottomAnchor, constant: 16)

            let bottomToActivate = speechManager.isSpeaking ? speechContainerBottom : speechButtonBottom

            NSLayoutConstraint.activate([
                // Reader Button
                readerButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: readerButton.trailingAnchor, constant: 16),
                readerButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                // Speech button
                speechButton.topAnchor.constraint(equalTo: readerButton.bottomAnchor, constant: 16),
                speechButton.heightAnchor.constraint(equalTo: readerButton.heightAnchor),
                speechButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: speechButton.trailingAnchor, constant: 16),
                // Speech container
                speechContainer.topAnchor.constraint(equalTo: readerButton.bottomAnchor, constant: 16),
                speechContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: speechContainer.trailingAnchor, constant: 16),
                bottomToActivate!,
                // Speech container title
                titleStackView.leadingAnchor.constraint(equalTo: speechContainer.leadingAnchor, constant: 16),
                speechContainer.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor, constant: 16),
                // Speech container controls
                controlsStackView.leadingAnchor.constraint(equalTo: speechContainer.leadingAnchor, constant: 16),
                speechContainer.trailingAnchor.constraint(equalTo: controlsStackView.trailingAnchor, constant: 16),
                titleStackView.topAnchor.constraint(equalTo: speechContainer.topAnchor, constant: 12),
                titleStackView.bottomAnchor.constraint(equalTo: controlsStackView.topAnchor),
                speechContainer.bottomAnchor.constraint(equalTo: controlsStackView.bottomAnchor, constant: 6)
            ])
        }
        
        func observeState() {
            speechManager.state
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] state in
                    guard let self else { return }
                    process(state: state)
                })
                .disposed(by: disposeBag)
        }
    }

    // MARK: - Actions

    private func playOrResume() {
        if speechManager.isPaused {
            speechManager.resume()
        } else {
            speechManager.start()
        }
    }

    private func formatted(modifier: Float) -> String {
        return (speedNumberFormatter.string(from: NSNumber(value: modifier)) ?? "") + "x"
    }

    private func set(rateModifier: Float) {
        speechManager.set(rateModifier: rateModifier)
        speedButton.configuration?.title = formatted(modifier: rateModifier)
        Defaults.shared.speechRateModifier = rateModifier
    }

    // MARK: - SpeechManager State

    private func process(state: SpeechManager<Delegate>.State) {
        switch state {
        case .loading:
            playButton.isHidden = true
            pauseButton.isHidden = true
            activityIndicator.startAnimating()
            activityIndicator.isHidden = false
            updateUIToSpeakingIfNeeded()

        case .speaking:
            if activityIndicator.isAnimating {
                activityIndicator.stopAnimating()
            }
            playButton.isHidden = true
            pauseButton.isHidden = false
            forwardButton.isEnabled = true
            backwardButton.isEnabled = true
            updateUIToSpeakingIfNeeded()

        case .stopped:
            updateSpeechControlsToStoppedOrPaused()
            updateUIToStoppedIfNeeded()

        case .paused:
            updateSpeechControlsToStoppedOrPaused()
        }

        func updateUIToSpeakingIfNeeded() {
            guard speechContainer.isHidden else { return }
            updatePopup(toHeight: expandedHeight)
            speechContainer.isHidden = false
            speechButton.isHidden = true
            speechContainerBottom.isActive = true
            speechButtonBottom.isActive = false
        }

        func updateUIToStoppedIfNeeded() {
            guard speechButton.isHidden else { return }
            speechContainer.isHidden = true
            speechButton.isHidden = false
            speechContainerBottom.isActive = false
            speechButtonBottom.isActive = true
            updatePopup(toHeight: baseHeight)
        }

        func updatePopup(toHeight height: CGFloat) {
            switch UIDevice.current.userInterfaceIdiom {
            case .pad:
                preferredContentSize = CGSize(width: view.frame.width, height: height)

            default:
                // TODO
                break
            }
        }

        func updateSpeechControlsToStoppedOrPaused() {
            if activityIndicator.isAnimating {
                activityIndicator.stopAnimating()
            }
            pauseButton.isHidden = true
            playButton.isHidden = false
            forwardButton.isEnabled = false
            backwardButton.isEnabled = false
        }
    }
}
