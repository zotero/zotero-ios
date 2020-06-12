//
//  Notification+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 05/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension Notification {
    var keyboardData: KeyboardData? {
        switch self.name {
        case UIResponder.keyboardWillHideNotification, UIResponder.keyboardWillShowNotification,
             UIResponder.keyboardDidHideNotification, UIResponder.keyboardDidShowNotification:
            return self.userInfo.flatMap(KeyboardData.init)

        default:
            return nil
        }
    }
}

extension Notification.Name {
    static let attachmentFileDeleted = Notification.Name("org.zotero.AttachmentFileDeleted")
}
