//
//  ToolbarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ToolbarViewController: UIViewController {
    private(set) var rootViewController: UIViewController
    private(set) weak var toolbar: UIToolbar!

    init(rootViewController: UIViewController) {
        self.rootViewController = rootViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()

        self.rootViewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.rootViewController.view)

        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(toolbar)
        self.toolbar = toolbar

        let safeBottomAnchor: NSLayoutYAxisAnchor
        if #available(iOS 11.0, *) {
            safeBottomAnchor = self.view.safeAreaLayoutGuide.bottomAnchor
        } else {
            safeBottomAnchor = self.view.bottomAnchor
        }

        NSLayoutConstraint.activate([
            toolbar.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            toolbar.rightAnchor.constraint(equalTo: self.view.rightAnchor),
            toolbar.bottomAnchor.constraint(equalTo: safeBottomAnchor),
            self.rootViewController.view.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            self.rootViewController.view.rightAnchor.constraint(equalTo: self.view.rightAnchor),
            self.rootViewController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.rootViewController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }
}
