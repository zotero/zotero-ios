//
//  AttachmentCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 10/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

struct AttachmentCreator {

    /// Returns attachment based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - parameter urlDetector: Url detector to validate url attachment.
    /// - returns: Attachment if recognized. Nil otherwise.
    static func attachment(for item: RItem, fileStorage: FileStorage, urlDetector: UrlDetector) -> Attachment? {
        return attachmentContentType(for: item, fileStorage: fileStorage, urlDetector: urlDetector).flatMap({ Attachment(item: item, type: $0) })
    }

    /// Returns attachment content type type based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - parameter urlDetector: Url detector to validate url attachment.
    /// - returns: Attachment content type if recognized. Nil otherwise.
    static func attachmentContentType(for item: RItem, fileStorage: FileStorage, urlDetector: UrlDetector) -> Attachment.ContentType? {
        if let contentType = item.fields.filter(.key(FieldKeys.contentType)).first?.value, !contentType.isEmpty {
            return fileAttachmentType(for: item, contentType: contentType, fileStorage: fileStorage)
        }
        return urlAttachmentType(for: item, urlDetector: urlDetector)
    }

    private static func fileAttachmentType(for item: RItem, contentType: String, fileStorage: FileStorage) -> Attachment.ContentType? {
        guard let ext = contentType.extensionFromMimeType?.lowercased() else {
            DDLogError("Attachment: mimeType/extension unknown (\(contentType)) for item (\(item.key))")
            return nil
        }
        guard let libraryId = item.libraryObject?.identifier else {
            DDLogError("Attachment: missing library for item (\(item.key))")
            return nil
        }

        let filename = item.fields.filter(.key(FieldKeys.filename)).first?.value ?? (item.displayTitle + "." + ext)
        let file = Files.attachmentFile(in: libraryId, key: item.key, ext: ext)
        let location: Attachment.FileLocation?
        if fileStorage.has(file) {
            location = .local
        } else if item.links.filter(.linkType(.enclosure)).first != nil {
            location = .remote
        } else {
            location = nil
        }

        return .file(file: file, filename: filename, location: location)
    }

    private static func urlAttachmentType(for item: RItem, urlDetector: UrlDetector) -> Attachment.ContentType? {
        if let urlString = item.fields.filter("key = %@", "url").first?.value,
           let url = URL(string: urlString),
           urlDetector.isUrl(string: urlString) {
            return .url(url)
        }

        DDLogError("Attachment: unknown attachment, fields: \(item.fields.map({ $0.key }))")
        return nil
    }
}
