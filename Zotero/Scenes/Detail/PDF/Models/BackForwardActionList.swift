//
//  BackForwardActionList.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 24/3/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKit

class BackForwardActionList: PSPDFKit.BackForwardActionList {
    var duringBackForwardActionExecution: Bool = false
    var actualPagesForwardList: [Action] = []

    override func register(_ action: PSPDFKit.Action) {
        let forwardListCountBeforeRegistration = forwardList.count
        super.register(action)
        let forwardListCountAfterRegistration = forwardList.count
        // PSPDFKit resets the forward actions list every time the page changes, similar to a web browser reseting forward navigation when the user goes to another page.
        // However, it does so even when the page change is the result of a back action execution, which is a mistake.
        // Additionally, it does so when the the user scrolls to a different page, which is also not desirable for our case.
        // To overcome this, we maintain the actual forward list ourselves instead, and reset the original forward list.
        if !duringBackForwardActionExecution, forwardListCountAfterRegistration == forwardListCountBeforeRegistration {
            // If not during a back/forward action execution, and if not registering a forward action , then reset actual pages forward list.
            actualPagesForwardList.removeAll()
            resetForwardList()
        }
    }
}
