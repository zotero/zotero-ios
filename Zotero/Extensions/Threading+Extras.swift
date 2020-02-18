//
//  Threading+Extras.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

func inMainThread(sync: Bool = false, action: @escaping () -> Void) {
    if Thread.isMainThread {
        action()
        return
    }

    if sync {
        DispatchQueue.main.sync {
            action()
        }
    } else {
        DispatchQueue.main.async {
            action()
        }
    }
}
