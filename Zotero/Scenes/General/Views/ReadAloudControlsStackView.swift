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
    /// Latest reported extraction progress (`nil` = unknown/indeterminate), retained so the progress view can be seeded
    /// with the current value whenever it becomes visible.
    private var currentProgress: Double?

    weak var playButton: UIButton!
    weak var pauseButton: UIButton!
    weak var backwardButton: UIButton!
    weak var forwardButton: UIButton!
    weak var progressView: CircularProgressView!

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

        let progressView = CircularProgressView(size: 24, lineWidth: 2)
        progressView.isHidden = !speechManager.state.value.isSpeakingOrLoading || speechManager.state.value.isSpeaking

        self.init(arrangedSubviews: [backwardButton, playButton, pauseButton, progressView, forwardButton])

        translatesAutoresizingMaskIntoConstraints = false
        axis = .horizontal
        alignment = .center
        distribution = .fillEqually
        playButton.addAction(UIAction(handler: { _ in playAction() }), for: .touchUpInside)
        pauseButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.pause() }), for: .touchUpInside)
        // Single tap skips a sentence; double tap skips a whole paragraph (coalesced by SpeechManager).
        forwardButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.navigateForward() }), for: .touchUpInside)
        backwardButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.navigateBackward() }), for: .touchUpInside)
        self.playButton = playButton
        self.pauseButton = pauseButton
        self.forwardButton = forwardButton
        self.backwardButton = backwardButton
        self.progressView = progressView

        speechManager.state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)

        speechManager.extractionProgress
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] progress in
                self?.updateProgress(progress)
            })
            .disposed(by: disposeBag)
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
            showProgressView()
            forwardButton.isEnabled = false
            backwardButton.isEnabled = false

        case .loading:
            playButton.isHidden = true
            pauseButton.isHidden = true
            showProgressView()
            forwardButton.isEnabled = true
            backwardButton.isEnabled = true

        case .speaking:
            hideProgressView()
            playButton.isHidden = true
            pauseButton.isHidden = false
            forwardButton.isEnabled = true
            backwardButton.isEnabled = true

        case .paused:
            hideProgressView()
            pauseButton.isHidden = true
            playButton.isHidden = false
            forwardButton.isEnabled = true
            backwardButton.isEnabled = true

        case .stopped, .outOfCredits:
            hideProgressView()
            pauseButton.isHidden = true
            playButton.isHidden = false
            forwardButton.isEnabled = false
            backwardButton.isEnabled = false
        }
    }

    /// Shows the progress view, seeding it with the latest reported extraction progress (falling back to an
    /// indeterminate spinner while progress is unknown).
    private func showProgressView() {
        progressView.isHidden = false
        updateProgress(currentProgress)
    }

    private func hideProgressView() {
        progressView.stopIndeterminateAnimation()
        progressView.progress = 0
        progressView.isHidden = true
    }

    /// Reflects the extraction progress in the progress view: a determinate arc when a value is known, an indeterminate
    /// spinner otherwise. No-op while the progress view is hidden.
    private func updateProgress(_ progress: Double?) {
        currentProgress = progress
        guard !progressView.isHidden else { return }
        if let progress {
            progressView.stopIndeterminateAnimation()
            progressView.progress = CGFloat(progress)
        } else {
            progressView.startIndeterminateAnimation()
        }
    }
}
