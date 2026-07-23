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
        case annotationToolbar, bottomToolbar, navbar
    }

    let type: Kind
    unowned let controlsView: AccessibilitySpeechControlsStackView<Delegate>
    
    private weak var widthConstraint: NSLayoutConstraint?
    private weak var heightConstraint: NSLayoutConstraint?

    init(type: Kind, speechManager: SpeechManager<Delegate>) {
        let controls = AccessibilitySpeechControlsStackView(speechManager: speechManager)
        self.type = type
        controlsView = controls
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        layer.masksToBounds = false
        
        addSubview(controls)
        
        let height = controls.heightAnchor.constraint(equalToConstant: 44)

        NSLayoutConstraint.activate([
            height,
            controls.topAnchor.constraint(equalTo: topAnchor),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: controls.trailingAnchor)
        ])
        
        heightConstraint = height

        switch type {
        case .annotationToolbar:
            let width = widthAnchor.constraint(equalToConstant: 150)
            backgroundColor = .systemGray6
            NSLayoutConstraint.activate([
                width,
                bottomAnchor.constraint(equalTo: controls.bottomAnchor)
            ])
            layer.cornerRadius = 22
            widthConstraint = width
            
        case .navbar:
            let width = widthAnchor.constraint(equalToConstant: 150)
            backgroundColor = .systemGray6
            NSLayoutConstraint.activate([
                width,
                bottomAnchor.constraint(equalTo: controls.bottomAnchor)
            ])
            layer.cornerRadius = 22
            widthConstraint = width

        case .bottomToolbar:
            backgroundColor = Asset.Colors.navbarBackground.color
            layer.cornerRadius = 0
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
}
