//
//  RightButton.swift
//  ZShare
//
//  Created by Michal Rentka on 09.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class RightButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        var config = self.configuration ?? UIButton.Configuration.plain()
        config.imagePlacement = .trailing
        self.configuration = config
    }
}
