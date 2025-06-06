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
    private let disposeBag: DisposeBag
    
    private weak var playButton: UIButton!
    private weak var pauseButton: UIButton!
    private weak var backwardButton: UIButton!
    private weak var forwardButton: UIButton!
    private weak var activityIndicator: UIActivityIndicatorView!
    
    init(speechManager: SpeechManager<Delegate>) {
        self.speechManager = speechManager
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        createView()
        observeState()
        
        func createView() {
            var playConfig = UIButton.Configuration.plain()
            playConfig.image = UIImage(systemName: "play.fill")
            let playButton = UIButton(configuration: playConfig)
            playButton.isHidden = speechManager.isSpeaking
            playButton.addAction(UIAction(handler: { [weak self] _ in self?.playOrResume() }), for: .touchUpInside)
            
            var pauseConfig = UIButton.Configuration.plain()
            pauseConfig.image = UIImage(systemName: "pause.fill")
            let pauseButton = UIButton(configuration: pauseConfig)
            pauseButton.isHidden = !speechManager.isSpeaking
            pauseButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.pause() }), for: .touchUpInside)
            
            var forwardConfig = UIButton.Configuration.plain()
            forwardConfig.image = UIImage(systemName: "forward.fill")
            let forwardButton = UIButton(configuration: forwardConfig)
            forwardButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.forward() }), for: .touchUpInside)
            
            var backwardConfig = UIButton.Configuration.plain()
            backwardConfig.image = UIImage(systemName: "backward.fill")
            let backwardButton = UIButton(configuration: backwardConfig)
            backwardButton.addAction(UIAction(handler: { [weak self] _ in self?.speechManager.backward() }), for: .touchUpInside)
            
            let activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.hidesWhenStopped = true

            let stackView = UIStackView(arrangedSubviews: [backwardButton, playButton, pauseButton, activityIndicator, forwardButton])
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.axis = .horizontal
            stackView.alignment = .fill
            stackView.distribution = .fillEqually
            view.addSubview(stackView)
            
            self.playButton = playButton
            self.pauseButton = pauseButton
            self.forwardButton = forwardButton
            self.backwardButton = backwardButton
            self.activityIndicator = activityIndicator
            
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
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
            
        case .stopped, .paused:
            if activityIndicator.isAnimating {
                activityIndicator.stopAnimating()
            }
            pauseButton.isHidden = true
            playButton.isHidden = false
        }
    }
}
