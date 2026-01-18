//
//  Notifications.swift
//  Zotero
//
//  Created by Michal Rentka on 12/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension Notification.Name {
    // Sent when attachment file is deleted. Used to update `FileAttachmentView`s.
    static let attachmentFileDeleted = Notification.Name("org.zotero.AttachmentFileDeleted")
    // Sent when attachment (`RItem`) is completely removed from the app (not just trashed). Used to remove attachment files of deleted attachments.
    static let attachmentDeleted = Notification.Name(rawValue: "org.zotero.AttachmentsDeleted")
    // Sent when Defaults.shared.showSubcollectionItems changes.
    static let showSubcollectionItemsChanged = Notification.Name(rawValue: "org.zotero.Defaults.shared.showSubcollectionItemsChanged")
    // Sent when WebDAV certificate changes (possible MITM attack). Used to alert user to re-verify.
    static let webDavCertificateChanged = Notification.Name(rawValue: "org.zotero.WebDavCertificateChanged")
    // Sent when WebDAV certificate is expired. Used to alert user to update certificate.
    static let webDavCertificateExpired = Notification.Name(rawValue: "org.zotero.WebDavCertificateExpired")
}
