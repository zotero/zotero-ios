//
//  ReadAloudControlsStackView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import NaturalLanguage
import UIKit

import RxSwift

final class ReadAloudControlsStackView<Delegate: SpeechManagerDelegate>: UIStackView {
    private let disposeBag: DisposeBag = DisposeBag()

    weak var playButton: UIButton!
    weak var pauseButton: UIButton!
    weak var backwardButton: UIButton!
    weak var forwardButton: UIButton!
    weak var activityIndicator: UIActivityIndicatorView!

    convenience init(speechManager: SpeechManager<Delegate>, playAction: @escaping () -> Void) {
        let imageConfiguration = UIImage.SymbolConfiguration.init(scale: .large)
        // `scale: .large` is relative to the symbol's base size (the default body text style). Using a larger text
        // style as the base makes play/pause render slightly bigger than the other (body-based) `.large` buttons,
        // while still scaling with Dynamic Type.
        let playPauseImageConfiguration = UIImage.SymbolConfiguration(textStyle: .title3, scale: .large)

        var playConfig = UIButton.Configuration.plain()
        playConfig.image = UIImage(systemName: "play.fill", withConfiguration: playPauseImageConfiguration)
        let playButton = UIButton(configuration: playConfig)
        playButton.accessibilityLabel = L10n.Accessibility.Speech.play
        playButton.isHidden = speechManager.state.value.isSpeaking

        var pauseConfig = UIButton.Configuration.plain()
        pauseConfig.image = UIImage(systemName: "pause.fill", withConfiguration: playPauseImageConfiguration)
        let pauseButton = UIButton(configuration: pauseConfig)
        pauseButton.accessibilityLabel = L10n.Accessibility.Speech.pause
        pauseButton.isHidden = !speechManager.state.value.isSpeaking

        var forwardConfig = UIButton.Configuration.plain()
        forwardConfig.image = UIImage(systemName: "plus.arrow.trianglehead.clockwise", withConfiguration: imageConfiguration)
        let forwardButton = UIButton(configuration: forwardConfig)
        forwardButton.accessibilityLabel = L10n.Accessibility.Speech.forward
        forwardButton.isEnabled = speechManager.state.value.isSpeaking

        var backwardConfig = UIButton.Configuration.plain()
        backwardConfig.image = UIImage(systemName: "minus.arrow.trianglehead.counterclockwise", withConfiguration: imageConfiguration)
        let backwardButton = UIButton(configuration: backwardConfig)
        backwardButton.accessibilityLabel = L10n.Accessibility.Speech.backward
        backwardButton.isEnabled = speechManager.state.value.isSpeaking

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.hidesWhenStopped = true

        self.init(arrangedSubviews: [backwardButton, playButton, pauseButton, activityIndicator, forwardButton])

        translatesAutoresizingMaskIntoConstraints = false
        axis = .horizontal
        alignment = .center
        distribution = .fillEqually
        playButton.addAction(UIAction(handler: { _ in playAction() }), for: .touchUpInside)
        pauseButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.pause() }), for: .touchUpInside)
        // Tap skips a single sentence; long press skips a whole paragraph.
        forwardButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.forward(by: .sentence) }), for: .touchUpInside)
        backwardButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.backward(by: .sentence) }), for: .touchUpInside)
        addParagraphLongPress(to: forwardButton) { [weak speechManager] in speechManager?.forward(by: .paragraph) }
        addParagraphLongPress(to: backwardButton) { [weak speechManager] in speechManager?.backward(by: .paragraph) }
        self.playButton = playButton
        self.pauseButton = pauseButton
        self.forwardButton = forwardButton
        self.backwardButton = backwardButton
        self.activityIndicator = activityIndicator

        speechManager.state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)
    }

    /// Adds a long press recognizer that fires `action` once when the press is recognized. The button's own
    /// `touchUpInside` is suppressed automatically once the long press wins, so short taps and long presses are exclusive.
    private func addParagraphLongPress(to button: UIButton, action: @escaping () -> Void) {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.25
        recognizer.rx.event
            .subscribe(onNext: { [weak button] recognizer in
                // A disabled UIButton still keeps user interaction enabled, so its gesture recognizers keep firing.
                guard recognizer.state == .began, button?.isEnabled == true else { return }
                action()
            })
            .disposed(by: disposeBag)
        button.addGestureRecognizer(recognizer)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func update(state: SpeechState) {
        switch state {
        case .initializing:
            playButton.isHidden = true
            pauseButton.isHidden = true
            activityIndicator.startAnimating()
            activityIndicator.isHidden = false
            forwardButton.isEnabled = false
            backwardButton.isEnabled = false

        case .loading:
            playButton.isHidden = true
            pauseButton.isHidden = true
            activityIndicator.startAnimating()
            activityIndicator.isHidden = false
            forwardButton.isEnabled = true
            backwardButton.isEnabled = true

        case .speaking:
            if activityIndicator.isAnimating {
                activityIndicator.stopAnimating()
            }
            playButton.isHidden = true
            pauseButton.isHidden = false
            forwardButton.isEnabled = true
            backwardButton.isEnabled = true

        case .paused:
            if activityIndicator.isAnimating {
                activityIndicator.stopAnimating()
            }
            pauseButton.isHidden = true
            playButton.isHidden = false
            forwardButton.isEnabled = true
            backwardButton.isEnabled = true

        case .stopped, .outOfCredits:
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
