//
//  Threading+Extras.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

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

func logPerformance(logMessage: String? = nil, action: () -> Void) {
    let start = CFAbsoluteTimeGetCurrent()
    action()
    let duration = CFAbsoluteTimeGetCurrent() - start

    if let message = logMessage {
        DDLogInfo("PERF: \(message) \(duration)")
    } else {
        DDLogInfo("PERF: \(duration)")
    }
}
