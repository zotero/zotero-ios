//
//  EventObservableWindow.swift
//  Zotero
//
//  Created by Michal Rentka on 20.11.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class EventObservableWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        guard !(event.allTouches ?? []).isEmpty else { return }
        (UIApplication.shared.delegate as? AppDelegate)?.controllers.idleTimerController.resetCustomTimer()
    }
}
