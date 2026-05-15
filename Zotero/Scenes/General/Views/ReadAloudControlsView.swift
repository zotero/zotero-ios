//
//  ReadAloudControlsView.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class ReadAloudControlsView<Delegate: SpeechManagerDelegate>: UIView, AnnotationToolbarLeadingView {
    enum Kind {
        case annotationToolbar, bottomToolbar, navbar
    }

    let type: Kind
    unowned let controlsView: ReadAloudControlsStackView<Delegate>

    private weak var widthConstraint: NSLayoutConstraint?
    private weak var heightConstraint: NSLayoutConstraint?
    private weak var settingsButton: UIButton?
    private weak var remainingTimeLabel: UILabel?
    private weak var remainingTimeClockImageView: UIImageView?
    private let disposeBag = DisposeBag()

    init(type: Kind, speechManager: SpeechManager<Delegate>, playAction: @escaping () -> Void, settingsMenu: UIMenu, highlighterAction: (() -> Void)? = nil) {
        let controls = ReadAloudControlsStackView(speechManager: speechManager, playAction: playAction)
        self.type = type
        controlsView = controls
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        layer.masksToBounds = false

        switch type {
        case .annotationToolbar:
            setupAnnotationToolbar(controls: controls)

        case .navbar:
            setupNavbar(controls: controls, speechManager: speechManager, highlighterAction: highlighterAction)

        case .bottomToolbar:
            setupBottomToolbar(controls: controls, speechManager: speechManager, settingsMenu: settingsMenu, highlighterAction: highlighterAction)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(toRotation rotation: AnnotationToolbarViewController.Rotation) {
        switch rotation {
        case .horizontal:
            widthConstraint?.constant = 150
            heightConstraint?.constant = 44
            controlsView.axis = .horizontal

        case .vertical:
            widthConstraint?.constant = 44
            heightConstraint?.constant = 150
            controlsView.axis = .vertical
        }
    }

    // MARK: - Setup

    private func setupAnnotationToolbar(controls: ReadAloudControlsStackView<Delegate>) {
        addSubview(controls)
        let height = controls.heightAnchor.constraint(equalToConstant: 44)
        let width = widthAnchor.constraint(equalToConstant: 150)
        NSLayoutConstraint.activate([
            height,
            width,
            controls.topAnchor.constraint(equalTo: topAnchor),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            bottomAnchor.constraint(equalTo: controls.bottomAnchor)
        ])
        backgroundColor = .systemGray6
        layer.cornerRadius = 22
        heightConstraint = height
        widthConstraint = width
    }

    private func setupNavbar(controls: ReadAloudControlsStackView<Delegate>, speechManager: SpeechManager<Delegate>, highlighterAction: (() -> Void)?) {
        let highlighterButton = createHighlighterButton(action: highlighterAction)

        let outerStack = UIStackView(arrangedSubviews: [controls, highlighterButton])
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.axis = .horizontal
        outerStack.alignment = .center
        outerStack.distribution = .fill
        outerStack.spacing = 4
        addSubview(outerStack)

        let height = outerStack.heightAnchor.constraint(equalToConstant: 38)
        NSLayoutConstraint.activate([
            height,
            controls.playButton.widthAnchor.constraint(equalToConstant: 64),
            controls.pauseButton.widthAnchor.constraint(equalToConstant: 64),
            controls.activityIndicator.widthAnchor.constraint(equalToConstant: 64),
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            trailingAnchor.constraint(equalTo: outerStack.trailingAnchor, constant: 8),
            bottomAnchor.constraint(equalTo: outerStack.bottomAnchor)
        ])
        backgroundColor = .systemGray6
        layer.cornerRadius = 19
        layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        heightConstraint = height
    }

    private func setupBottomToolbar(controls: ReadAloudControlsStackView<Delegate>, speechManager: SpeechManager<Delegate>, settingsMenu: UIMenu, highlighterAction: (() -> Void)?) {
        let (leftView, settingsBtn, timeLabel, clockImage) = createLeftView(settingsMenu: settingsMenu)
        let highlighterButton = createHighlighterButton(action: highlighterAction)

        let outerStack = UIStackView(arrangedSubviews: [leftView, controls, highlighterButton])
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.axis = .horizontal
        outerStack.alignment = .center
        outerStack.distribution = .equalSpacing
        addSubview(outerStack)

        let height = outerStack.heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            height,
            controls.playButton.widthAnchor.constraint(equalToConstant: 64),
            controls.pauseButton.widthAnchor.constraint(equalToConstant: 64),
            controls.activityIndicator.widthAnchor.constraint(equalToConstant: 64),
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            trailingAnchor.constraint(equalTo: outerStack.trailingAnchor, constant: 16),
            safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: outerStack.bottomAnchor)
        ])
        backgroundColor = Asset.Colors.navbarBackground.color
        layer.cornerRadius = 0
        heightConstraint = height

        self.settingsButton = settingsBtn
        self.remainingTimeLabel = timeLabel
        self.remainingTimeClockImageView = clockImage
        observeRemainingTime(speechManager: speechManager)
    }

    // MARK: - Left View (Settings Button / Remaining Time)

    private func createLeftView(settingsMenu: UIMenu) -> (UIView, UIButton, UILabel, UIImageView) {
        let imageConfig = UIImage.SymbolConfiguration(scale: .large)

        // Settings button
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "slider.horizontal.3", withConfiguration: imageConfig)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let settingsButton = UIButton(configuration: config)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.menu = settingsMenu
        settingsButton.showsMenuAsPrimaryAction = true

        // Remaining time views
        let clockImage = UIImageView(image: UIImage(systemName: "clock", withConfiguration: UIImage.SymbolConfiguration(scale: .small)))
        clockImage.translatesAutoresizingMaskIntoConstraints = false
        clockImage.tintColor = .systemRed
        clockImage.isHidden = true

        let timeLabel = UILabel()
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.textColor = .systemRed
        timeLabel.isHidden = true

        let timeStack = UIStackView(arrangedSubviews: [clockImage, timeLabel])
        timeStack.translatesAutoresizingMaskIntoConstraints = false
        timeStack.axis = .horizontal
        timeStack.spacing = 4
        timeStack.alignment = .center

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(settingsButton)
        container.addSubview(timeStack)
        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: container.topAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            timeStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            timeStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            timeStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        ])

        return (container, settingsButton, timeLabel, clockImage)
    }

    // MARK: - Highlighter Button

    private func createHighlighterButton(action: (() -> Void)? = nil) -> UIButton {
        let imageConfig = UIImage.SymbolConfiguration(scale: .large)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "highlighter", withConfiguration: imageConfig)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        if let action {
            button.addAction(UIAction(handler: { _ in action() }), for: .touchUpInside)
        }
        return button
    }

    // MARK: - Remaining Time Observation

    private func observeRemainingTime(speechManager: SpeechManager<Delegate>) {
        speechManager.remainingTime
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] remainingTime in
                self?.updateRemainingTimeDisplay(remainingTime)
            })
            .disposed(by: disposeBag)
    }

    private func updateRemainingTimeDisplay(_ remainingTime: TimeInterval?) {
        guard let remainingTime, RemainingTimeFormatter.isWarning(remainingTime) else {
            settingsButton?.isHidden = false
            remainingTimeLabel?.isHidden = true
            remainingTimeClockImageView?.isHidden = true
            return
        }
        settingsButton?.isHidden = true
        remainingTimeLabel?.isHidden = false
        remainingTimeClockImageView?.isHidden = false
        remainingTimeLabel?.text = RemainingTimeFormatter.formatted(remainingTime)
    }
}
