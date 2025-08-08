//
//  AccessibilityReaderOverlayView.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class AccessibilityReaderOverlayView<Delegate: SpeechmanagerDelegate>: UIView {
    enum Kind {
        case overlay, toolbar
    }

    private var type: Kind
    private weak var controls: UIView!
    private var width: NSLayoutConstraint!
    private var top: NSLayoutConstraint!
    private var bottom: NSLayoutConstraint!
    private var safeBottom: NSLayoutConstraint?

    init(type: Kind, speechManager: SpeechManager<Delegate>) {
        self.type = type
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Asset.Colors.navbarBackground.color
        if type == .overlay {
            setupRoundedCorners()
        }
        layer.masksToBounds = false
        let controls = AccessibilitySpeechControlsView(speechManager: speechManager)
        addSubview(controls)
        self.controls = controls

        width = widthAnchor.constraint(equalToConstant: 290)
        bottom = bottomAnchor.constraint(equalTo: controls.bottomAnchor)

        var toActivate: [NSLayoutConstraint] = [
            controls.heightAnchor.constraint(equalToConstant: 44),
            controls.topAnchor.constraint(equalTo: topAnchor),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: controls.trailingAnchor)
        ]

        switch type {
        case .overlay:
            toActivate.append(width)
            toActivate.append(bottom)

        case .toolbar:
            break
        }

        NSLayoutConstraint.activate(toActivate)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func connectControlsToSafeBottom(anchor: NSLayoutAnchor<NSLayoutYAxisAnchor>) {
        safeBottom = controls.bottomAnchor.constraint(equalTo: anchor)
        safeBottom?.isActive = true
    }

    func change(toType type: Kind, safeDocumentBottom: NSLayoutAnchor<NSLayoutYAxisAnchor>) {
        guard self.type != type else { return }

        switch type {
        case .overlay:
            width.isActive = true
            bottom.isActive = true
            safeBottom?.isActive = false
            safeBottom = nil
            setupRoundedCorners()

        case .toolbar:
            width.isActive = false
            bottom.isActive = false
            connectControlsToSafeBottom(anchor: safeDocumentBottom)
            removeRoundedCorners()
        }

        self.type = type

        func removeRoundedCorners() {
            layer.cornerRadius = 0
            layer.shadowRadius = 0
            layer.shadowColor = UIColor.clear.cgColor
            layer.shadowOpacity = 0
        }
    }

    private func setupRoundedCorners() {
        layer.cornerRadius = 13
        layer.shadowRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }
}
