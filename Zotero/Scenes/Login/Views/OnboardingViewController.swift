//
//  OnboardingViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 09/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class OnboardingViewController: UIViewController {
    @IBOutlet private weak var spacer: UIView!
    @IBOutlet private weak var scrollView: UIScrollView!

    init() {
        super.init(nibName: "OnboardingViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupPages()
    }

    private func setupPages() {
        let page1 = OnboardingPageView(attributedString: NSAttributedString(string: L10n.Onboarding.access),
                                       imageName: "onboarding_access")
        let page2 = OnboardingPageView(attributedString: NSAttributedString(string: L10n.Onboarding.annotate),
                                       imageName: "onboarding_annotate")
        let page3 = OnboardingPageView(attributedString: NSAttributedString(string: L10n.Onboarding.share),
                                       imageName: "onboarding_share")
        let page4 = OnboardingPageView(attributedString: NSAttributedString(string: L10n.Onboarding.sync),
                                       imageName: "onboarding_sync")

        let stackView = UIStackView(arrangedSubviews: [page1, page2, page3, page4])
        stackView.translatesAutoresizingMaskIntoConstraints = false

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.scrollView.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: self.scrollView.heightAnchor),
            page1.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor),
            page2.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor),
            page3.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor),
            page4.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor),
            page1.spacer.heightAnchor.constraint(equalTo: self.spacer.heightAnchor),
            page2.spacer.heightAnchor.constraint(equalTo: self.spacer.heightAnchor),
            page3.spacer.heightAnchor.constraint(equalTo: self.spacer.heightAnchor),
            page4.spacer.heightAnchor.constraint(equalTo: self.spacer.heightAnchor)
        ])
    }

}
