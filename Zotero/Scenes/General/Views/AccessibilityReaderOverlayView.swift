//
//  AccessibilityReaderOverlayView.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class AccessibilityReaderOverlayView<Delegate: SpeechmanagerDelegate>: UIView {
    init(speechManager: SpeechManager<Delegate>) {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        layer.cornerRadius = 13
        layer.shadowRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.masksToBounds = false
        let controls = AccessibilitySpeechControlsView(speechManager: speechManager)
        addSubview(controls)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            widthAnchor.constraint(equalToConstant: 290),
            controls.topAnchor.constraint(equalTo: topAnchor),
            bottomAnchor.constraint(equalTo: controls.bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingAnchor.constraint(equalTo: controls.trailingAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
