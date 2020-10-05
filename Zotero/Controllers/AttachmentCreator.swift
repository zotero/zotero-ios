//
//  AttachmentCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 10/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct AttachmentCreator {
    enum Options {
        case light, dark
    }

    /// Returns attachment based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - parameter urlDetector: Url detector to validate url attachment.
    /// - returns: Attachment if recognized. Nil otherwise.
    static func attachment(for item: RItem, options: Options? = nil, fileStorage: FileStorage, urlDetector: UrlDetector) -> Attachment? {
        return attachmentContentType(for: item, options: options, fileStorage: fileStorage, urlDetector: urlDetector).flatMap({ Attachment(item: item, type: $0) })
    }

    /// Returns attachment content type type based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - parameter urlDetector: Url detector to validate url attachment.
    /// - returns: Attachment content type if recognized. Nil otherwise.
    static func attachmentContentType(for item: RItem, options: Options? = nil, fileStorage: FileStorage, urlDetector: UrlDetector) -> Attachment.ContentType? {
        if let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value, !contentType.isEmpty {
            return fileAttachmentType(for: item, options: options, fileStorage: fileStorage)
        }
        return urlAttachmentType(for: item, urlDetector: urlDetector)
    }

    static func file(for item: RItem, options: Options? = nil) -> File? {
        guard let linkMode = item.fields.filter(.key(FieldKeys.Item.Attachment.linkMode)).first.flatMap({ LinkMode(rawValue: $0.value) }),
              let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value, !contentType.isEmpty else { return nil }

        guard let libraryId = item.libraryId else {
            DDLogError("AttachmentCreator: missing library for item (\(item.key))")
            return nil
        }

        switch linkMode {
        case .embeddedImage:
            if let parent = item.parent {
                switch parent.rawType {
                case ItemTypes.annotation:
                    if let attachment = parent.parent {
                        return Files.annotationPreview(annotationKey: parent.key, pdfKey: attachment.key, isDark: (options == .dark))
                    } else {
                        DDLogError("AttachmentCreator: uploading file for embedded image of annotation without parent (\(parent.key), \(item.key))!")
                        // This shouldn't really happen, annotation must always have a pdf parent! But let's not crash and return default attachment file.
                        return Files.attachmentFile(in: libraryId, key: item.key, contentType: contentType)
                    }
                default:
                    DDLogError("AttachmentCreator: uploading file for embedded image with parent of unknown type ('\(parent.rawType)', \(item.key))!")
                    // Embedded image can only be assigned to annotations currently, but return default file just in case.
                    return Files.attachmentFile(in: libraryId, key: item.key, contentType: contentType)
                }
            } else {
                DDLogError("AttachmentCreator: uploading file for embedded image without parent (\(item.key))!")
                // This shouldn't really happen, embedded image must always have a parent! But let's not crash and return default attachment file.
                return Files.attachmentFile(in: libraryId, key: item.key, contentType: contentType)
            }
        default:
            return Files.attachmentFile(in: libraryId, key: item.key, contentType: contentType)
        }
    }

    private static func fileAttachmentType(for item: RItem, options: Options? = nil, fileStorage: FileStorage) -> Attachment.ContentType? {
        guard let file = file(for: item, options: options) else {
            DDLogError("Attachment: missing library for item (\(item.key))")
            return nil
        }

        let filename = item.fields.filter(.key(FieldKeys.Item.Attachment.filename)).first?.value ?? (item.displayTitle + "." + file.ext)
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
