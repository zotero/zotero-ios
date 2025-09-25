//
//  AccessibilitySpeechControlsView.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class AccessibilitySpeechControlsView<Delegate: SpeechmanagerDelegate>: UIView, AnnotationToolbarLeadingView {
    enum Kind {
        case overlay, toolbar, navbar
    }

    let type: Kind
    unowned let controlsView: UIView

    init(type: Kind, speechManager: SpeechManager<Delegate>) {
        let controls = AccessibilitySpeechControlsStackView(speechManager: speechManager)
        self.type = type
        controlsView = controls
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        layer.masksToBounds = false
        
        addSubview(controls)

        NSLayoutConstraint.activate([
            controls.heightAnchor.constraint(equalToConstant: 44),
            controls.topAnchor.constraint(equalTo: topAnchor),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: controls.trailingAnchor)
        ])

        switch type {
        case .overlay:
            backgroundColor = .systemGray6
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 150),
                bottomAnchor.constraint(equalTo: controls.bottomAnchor)
            ])
            layer.cornerRadius = 22
            
        case .navbar:
            backgroundColor = .systemGray6
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 150),
                bottomAnchor.constraint(equalTo: controls.bottomAnchor)
            ])
            layer.cornerRadius = 22

        case .toolbar:
            backgroundColor = Asset.Colors.navbarBackground.color
            layer.cornerRadius = 0
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(toRotation rotation: AnnotationToolbarViewController.Rotation) {
        // Doesn't need anything, it appears only in .pinned position.
    }
}
