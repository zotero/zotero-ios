//
//  AccessibilitySpeechControlsStackView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class AccessibilitySpeechControlsStackView<Delegate: SpeechManagerDelegate>: UIStackView {
    private let disposeBag: DisposeBag = DisposeBag()

    weak var playButton: UIButton!
    weak var pauseButton: UIButton!
    weak var backwardButton: UIButton!
    weak var forwardButton: UIButton!
    weak var activityIndicator: UIActivityIndicatorView!

    convenience init(speechManager: SpeechManager<Delegate>) {
        let imageConfiguration = UIImage.SymbolConfiguration.init(scale: .large)

        var playConfig = UIButton.Configuration.plain()
        playConfig.image = UIImage(systemName: "play.fill", withConfiguration: imageConfiguration)
        playConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 22, bottom: 8, trailing: 22)
        let playButton = UIButton(configuration: playConfig)
        playButton.accessibilityLabel = L10n.Accessibility.Speech.play
        playButton.isHidden = speechManager.isSpeaking

        var pauseConfig = UIButton.Configuration.plain()
        pauseConfig.image = UIImage(systemName: "pause.fill", withConfiguration: imageConfiguration)
        let pauseButton = UIButton(configuration: pauseConfig)
        pauseButton.accessibilityLabel = L10n.Accessibility.Speech.pause
        pauseButton.isHidden = !speechManager.isSpeaking

        var forwardConfig = UIButton.Configuration.plain()
        forwardConfig.image = UIImage(systemName: "plus.arrow.trianglehead.clockwise", withConfiguration: imageConfiguration)
        let forwardButton = UIButton(configuration: forwardConfig)
        forwardButton.accessibilityLabel = L10n.Accessibility.Speech.forward
        forwardButton.isEnabled = speechManager.isSpeaking

        var backwardConfig = UIButton.Configuration.plain()
        backwardConfig.image = UIImage(systemName: "minus.arrow.trianglehead.counterclockwise", withConfiguration: imageConfiguration)
        let backwardButton = UIButton(configuration: backwardConfig)
        backwardButton.accessibilityLabel = L10n.Accessibility.Speech.backward
        backwardButton.isEnabled = speechManager.isSpeaking

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.hidesWhenStopped = true

        self.init(arrangedSubviews: [backwardButton, playButton, pauseButton, activityIndicator, forwardButton])

        translatesAutoresizingMaskIntoConstraints = false
        axis = .horizontal
        alignment = .center
        distribution = .fillEqually
        playButton.addAction(UIAction(handler: { [weak speechManager] _ in playOrResume(speechManager: speechManager) }), for: .touchUpInside)
        pauseButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.pause() }), for: .touchUpInside)
        forwardButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.forward() }), for: .touchUpInside)
        backwardButton.addAction(UIAction(handler: { [weak speechManager] _ in speechManager?.backward() }), for: .touchUpInside)
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

        func playOrResume(speechManager: SpeechManager<Delegate>?) {
            guard let speechManager else { return }
            if speechManager.isPaused {
                speechManager.resume()
            } else {
                speechManager.start()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func update(state: SpeechState) {
        switch state {
        case .loading:
            playButton.isHidden = true
            pauseButton.isHidden = true
            activityIndicator.startAnimating()
            activityIndicator.isHidden = false

        case .speaking:
            if activityIndicator.isAnimating {
                activityIndicator.stopAnimating()
            }
            playButton.isHidden = true
            pauseButton.isHidden = false
            forwardButton.isEnabled = true
            backwardButton.isEnabled = true

        case .stopped, .paused:
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
