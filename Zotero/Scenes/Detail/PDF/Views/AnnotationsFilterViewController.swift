//
//  AnnotationsFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationsFilterViewController: UIViewController {
    @IBOutlet private weak var colorContainer: UIStackView!
    @IBOutlet private weak var tagsLabel: UILabel!

    private let completionAction: (AnnotationsFilter?) -> Void

    init(completion: @escaping (AnnotationsFilter?) -> Void) {
        self.completionAction = completion
        super.init(nibName: "AnnotationsFilterViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupColorPicker()
    }

    // MARK: - Setups

    private func setupColorPicker() {
        AnnotationsConfig.colors.forEach { hexColor in
            let circleView = ColorPickerCircleView(hexColor: hexColor)
            circleView.contentInsets = UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11)
            circleView.backgroundColor = .clear
//            circleView.tap.bind(to: self.colorChange).disposed(by: self.disposeBag)
            circleView.backgroundColor = .white
            circleView.isAccessibilityElement = true
            self.colorContainer.addArrangedSubview(circleView)
        }
    }
}
