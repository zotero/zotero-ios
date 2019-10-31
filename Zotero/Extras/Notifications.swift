//
//  Notifications.swift
//  Zotero
//
//  Created by Michal Rentka on 31/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension Notification.Name {

    // MARK: - Modal view management

    static let presentPdf = Notification.Name(rawValue: "org.zotero.PresentPdfAttachment")

    static let presentWeb = Notification.Name(rawValue: "org.zotero.PresentWebAttachment")

    static let presentUnknownAttachment = Notification.Name(rawValue: "org.zotero.PresentUnknownAttachment")

    static let presentNote = Notification.Name(rawValue: "org.zotero.PresentNotification")

    static let presentFilePicker = Notification.Name(rawValue: "org.zotero.PresentFilePicker")

    static let presentCreatorPicker = Notification.Name(rawValue: "org.zotero.PresentCreatorTypePicker")

    static let presentTypePicker = Notification.Name(rawValue: "org.zotero.PresentItemTypePicker")

    static let presentTagPicker = Notification.Name(rawValue: "org.zotero.PresentTagPicker")

    static let presentCollectionsPicker = Notification.Name(rawValue: "org.zotero.PresentCollectionsPicker")

    static let presentSortTypePicker = Notification.Name(rawValue: "org.zotero.PresentSortTypePicker")

    static let presentSettings = Notification.Name(rawValue: "org.zotero.PresentSettings")

    // MARK: - UISplitViewController management

    static let splitViewDetailChanged = Notification.Name("org.zotero.SplitViewDetailChanged")

    static let showDuplicateCreation = Notification.Name(rawValue: "org.zotero.ShowDuplicateCreation")

    // MARK: - Session management

    static let sessionChanged = Notification.Name(rawValue: "org.zotero.SessionChangedNotification")
}
