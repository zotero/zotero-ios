//
//  ObjectChangeViewControllerObserver.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ObjectChangeReporter {
    private weak var controller: UIViewController?

    init(controller: UIViewController) {
        self.controller = controller
    }

    func report(changed: [String], hasDeletions: Bool) {
        guard let controller = self.controller else { return }
    }
}

protocol ObjectChangeResponder: AnyObject {
}
