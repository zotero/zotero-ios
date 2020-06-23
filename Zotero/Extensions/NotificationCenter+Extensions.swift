//
//  NotificationCenter+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 05/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

extension NotificationCenter {
    var keyboardWillShow: Observable<Notification> {
        return self.rx.notification(UIResponder.keyboardWillShowNotification)
    }

    var keyboardWillHide: Observable<Notification> {
        return self.rx.notification(UIResponder.keyboardWillHideNotification)
    }

    var keyboardDidShow: Observable<Notification> {
        return self.rx.notification(UIResponder.keyboardDidShowNotification)
    }

    var keyboardDidHide: Observable<Notification> {
        return self.rx.notification(UIResponder.keyboardDidHideNotification)
    }
}
