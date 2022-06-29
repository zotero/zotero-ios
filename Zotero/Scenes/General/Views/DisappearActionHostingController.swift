//
//  File.swift
//  Zotero
//
//  Created by Michal Rentka on 09.11.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

final class DisappearActionHostingController<Content>: UIHostingController<Content> where Content : View {
    var willAppear: (() -> Void)?
    var willDisappear: (() -> Void)?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.willAppear?()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.willDisappear?()
    }
}
