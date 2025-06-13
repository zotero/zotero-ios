//
//  SpeechPopupViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 30.05.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

final class SpeechPopupViewController<Delegate: SpeechmanagerDelegate>: UIViewController {
    private unowned let speechManager: SpeechManager<Delegate>
    private let speedNumberFormatter: NumberFormatter
    private let disposeBag: DisposeBag

    private weak var speedButton: UIButton!
    private weak var playButton: UIButton!
    private weak var pauseButton: UIButton!
    private weak var backwardButton: UIButton!
    private weak var forwardButton: UIButton!
    private weak var activityIndicator: UIActivityIndicatorView!

    init(speechManager: SpeechManager<Delegate>) {
        self.speechManager = speechManager
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

        createView()
        observeState()

        func createView() {
            let titleLabel = UILabel()
            titleLabel.text = "Listen to Document"
            titleLabel.font = .preferredFont(forTextStyle: .headline)

            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let speedActions = [2, 1.75, 1.5, 1.25, 1, 0.75].map({ [unowned self] val in UIAction(title: formatted(modifier: val), handler: { [weak self] _ in self?.set(rateModifier: val) }) })
            var speedConfiguration = UIButton.Configuration.filled()
            speedConfiguration.title = formatted(modifier: Defaults.shared.speechRateModifier)
            speedConfiguration.baseBackgroundColor = .systemGray4
            speedConfiguration.baseForegroundColor = .label
            speedConfiguration.cornerStyle = .capsule
            speedConfiguration.contentInsets = .init(top: 8, leading: 16, bottom: 8, trailing: 16)
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
            view.addSubview(titleStackView)

            let imageConfiguration = UIImage.SymbolConfiguration.init(scale: .large)

            var playConfig = UIButton.Configuration.plain()
            playConfig.image = UIImage(systemName: "play.fill", withConfiguration: imageConfiguration)
            playConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 22, bottom: 8, trailing: 22)
            let playButton = UIButton(configuration: playConfig)
            playButton.isHidden = speechManager.isSpeaking
            playButton.addAction(UIAction(handler: { [weak self] _ in self?.playOrResume() }), for: .touchUpInside)

            var pauseConfig = UIButton.Configuration.plain()
            pauseConfig.image = UIImage(systemName: "pause.fill", withConfiguration: imageConfiguration)
            let pauseButton = UIButton(configuration: pauseConfig)
            pauseButton.isHidden = !speechManager.isSpeaking
            pauseButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.pause() }), for: .touchUpInside)

            var forwardConfig = UIButton.Configuration.plain()
            forwardConfig.image = UIImage(systemName: "plus.arrow.trianglehead.clockwise", withConfiguration: imageConfiguration)
            let forwardButton = UIButton(configuration: forwardConfig)
            forwardButton.isEnabled = speechManager.isSpeaking
            forwardButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.forward() }), for: .touchUpInside)

            var backwardConfig = UIButton.Configuration.plain()
            backwardConfig.image = UIImage(systemName: "minus.arrow.trianglehead.counterclockwise", withConfiguration: imageConfiguration)
            let backwardButton = UIButton(configuration: backwardConfig)
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
            view.addSubview(controlsStackView)

            self.playButton = playButton
            self.pauseButton = pauseButton
            self.forwardButton = forwardButton
            self.backwardButton = backwardButton
            self.activityIndicator = activityIndicator
            self.speedButton = speedButton

            NSLayoutConstraint.activate([
                titleStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor, constant: 20),
                controlsStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: controlsStackView.trailingAnchor, constant: 20),
                titleStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                titleStackView.bottomAnchor.constraint(equalTo: controlsStackView.topAnchor),
                view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: controlsStackView.bottomAnchor, constant: 6)
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

    private func process(state: SpeechManager<Delegate>.State) {
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
