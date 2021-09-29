//
//  File.swift
//  Zotero
//
//  Created by Michal Rentka on 29.09.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import UIKit
import CocoaLumberjackSwift

final class IdleTimerController {
    /// Processes which require idle timer disabled
    private var activeProcesses: Int = 0

    func disable() {
        self.activeProcesses += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func enable() {
        guard self.activeProcesses > 0 else {
            DDLogWarn("IdleTimerController: tried to enable idle timer with no active processes")
            return
        }

        self.activeProcesses -= 1

        guard self.activeProcesses == 0 else { return }
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
