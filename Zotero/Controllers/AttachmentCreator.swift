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

    private enum FileType {
        case contentType(String)
        case `extension`(String)
    }

    private static let mainAttachmentContentTypes: Set<String> = ["text/html", "application/pdf", "image/png", "image/jpeg", "image/gif", "text/plain"]

    static func mainAttachment(for item: RItem, fileStorage: FileStorage) -> Attachment? {
        if item.rawType == ItemTypes.attachment {
            // If item is attachment, create `Attachment` and ignore linked attachments.
            if let attachment = attachment(for: item, fileStorage: fileStorage, urlDetector: nil) {
                switch attachment.type {
                case .url:
                    return attachment

                case .file(_, _, _, let linkType, _) where linkType == .importedFile || linkType == .importedUrl:
                    return attachment

                default:
                    break
                }
            }
            return nil
        }

        var attachmentData = attachmentData(for: item)

        guard !attachmentData.isEmpty else { return nil }

        attachmentData.sort { lData, rData in
            mainAttachmentsAreInIncreasingOrder(lData: (lData.1, lData.3, lData.4), rData: (rData.1, rData.3, rData.4))
        }

        guard let (idx, contentType, linkMode, _, _) = attachmentData.first else { return nil }
        let rAttachment = item.children[idx]
        let linkType: Attachment.FileLinkType = linkMode == .importedFile ? .importedFile : .importedUrl
        guard let libraryId = rAttachment.libraryId else { return nil }
        let type = importedType(for: rAttachment, contentType: contentType, libraryId: libraryId, fileStorage: fileStorage, linkType: linkType, compressed: rAttachment.fileCompressed)
        return Attachment(item: rAttachment, type: type)
    }

    static func mainPdfAttachment(from attachments: [Attachment], parentUrl: String?) -> Attachment? {
        guard !attachments.isEmpty else { return nil }
        return attachments.filter({ attachment in
            switch attachment.type {
            case .file(_, let contentType, _, _, _):
                switch contentType {
                case "application/pdf", "text/html", "application/epub+zip":
                    return true

                default:
                    return false
                }

            default:
                return false
            }
        }).sorted { lAttachment, rAttachment in
            return mainAttachmentsAreInIncreasingOrder(
                lData: ("application/pdf", (lAttachment.url == parentUrl), lAttachment.dateAdded),
                rData: ("application/pdf", (rAttachment.url == parentUrl), rAttachment.dateAdded)
            )
        }.first
    }

    private static func attachmentData(for item: RItem) -> [(Int, String, LinkMode, Bool, Date)] {
        let itemUrl = item.fields.first(where: { $0.key == FieldKeys.Item.url })?.value
        var data: [(Int, String, LinkMode, Bool, Date)] = []

        for (idx, child) in item.children.enumerated() {
            guard (child.rawType == ItemTypes.attachment) && (child.syncState != .dirty) && !child.trash,
                  let linkMode = child.fields.first(where: { $0.key == FieldKeys.Item.Attachment.linkMode }).flatMap({ LinkMode(rawValue: $0.value) }),
                  (linkMode == .importedUrl) || (linkMode == .importedFile),
                  let contentType = contentType(for: child),
                  AttachmentCreator.mainAttachmentContentTypes.contains(contentType) else { continue }

            var hasMatchingUrlWithParent = false
            if let url = itemUrl, let childUrl = child.fields.first(where: { $0.key == FieldKeys.Item.Attachment.url })?.value {
                hasMatchingUrlWithParent = url == childUrl
            }
            data.append((idx, contentType, linkMode, hasMatchingUrlWithParent, child.dateAdded))
        }

        return data
    }

    /// Used for sorting of attachments to get a "Main" attachment which should be opened as a first when multiple attachments are available on one item.
    /// - parameter lData: Content type, indicator whether attachment and parent item has matching URLs, date added of attachment.
    /// - parameter rData: Content type, indicator whether attachment and parent item has matching URLs, date added of attachment.
    /// returns: `true` if lData and rData are in increasing order (lData < rData)
    private static func mainAttachmentsAreInIncreasingOrder(lData: (String, Bool, Date), rData: (String, Bool, Date)) -> Bool {
        let lPriority = priority(for: lData.0)
        let rPriority = priority(for: rData.0)

        guard lPriority == rPriority else {
            // Sort based on content type priority
            return lPriority < rPriority
        }

        guard lData.1 == rData.1 else {
            // Sort based on whether attachment and parent item have matching urls
            return lData.1 && !rData.1
        }

        // Sort based on `dateAdded`.
        return lData.2.compare(rData.2) == .orderedAscending
    }

    private static func priority(for contentType: String) -> Int {
        switch contentType {
        case "application/pdf":
            return 0

        case "application/epub+zip":
            return 1

        case "text/html":
            return 2

        case "image/gif", "image/jpeg", "image/png":
            return 3

        case "text/plain":
            return 4

        default:
            return 5
        }
    }

    /// Returns attachment based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - parameter urlDetector: Url detector to validate url attachment.
    /// - returns: Attachment if recognized. Nil otherwise.
    static func attachment(for item: RItem, options: Options = .light, fileStorage: FileStorage?, urlDetector: UrlDetector?) -> Attachment? {
        return attachmentType(for: item, options: options, fileStorage: fileStorage, urlDetector: urlDetector).flatMap({ Attachment(item: item, type: $0) })
    }

    /// Returns attachment content type type based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - parameter urlDetector: Url detector to validate url attachment.
    /// - returns: Attachment content type if recognized. Nil otherwise.
    static func attachmentType(for item: RItem, options: Options = .light, fileStorage: FileStorage?, urlDetector: UrlDetector?) -> Attachment.Kind? {
        guard let linkMode = item.fields.first(where: { $0.key == FieldKeys.Item.Attachment.linkMode }).flatMap({ LinkMode(rawValue: $0.value) }) else {
            DDLogError("AttachmentCreator: missing link mode for item \(item.key)")
            return nil
        }
        guard let libraryId = item.libraryId else {
            DDLogError("AttachmentCreator: missing library for item (\(item.key))")
            return nil
        }

        switch linkMode {
        case .importedFile:
            return importedType(for: item, libraryId: libraryId, fileStorage: fileStorage, linkType: .importedFile, compressed: item.fileCompressed)

        case .embeddedImage:
            return importedType(for: item, libraryId: libraryId, fileStorage: fileStorage, linkType: .embeddedImage, compressed: false)

        case .importedUrl:
            return importedType(for: item, libraryId: libraryId, fileStorage: fileStorage, linkType: .importedUrl, compressed: item.fileCompressed)

        case .linkedFile:
            return linkedFileType(item: item, libraryId: libraryId)

        case .linkedUrl:
            guard let urlDetector = urlDetector else { return nil }
            return linkedUrlType(for: item, libraryId: libraryId, urlDetector: urlDetector)
        }
    }

    private static func importedType(for item: RItem, libraryId: LibraryIdentifier, fileStorage: FileStorage?, linkType: Attachment.FileLinkType, compressed: Bool) -> Attachment.Kind? {
        guard let contentType = contentType(for: item) else { return nil }
        return importedType(for: item, contentType: contentType, libraryId: libraryId, fileStorage: fileStorage, linkType: linkType, compressed: compressed)
    }

    private static func importedType(
        for item: RItem,
        contentType: String,
        libraryId: LibraryIdentifier,
        fileStorage: FileStorage?,
        linkType: Attachment.FileLinkType,
        compressed: Bool
    ) -> Attachment.Kind {
        let filename = filename(for: item, ext: contentType.extensionFromMimeType)
        let file = Files.attachmentFile(in: libraryId, key: item.key, filename: filename, contentType: contentType)
        let location = location(for: item, file: file, fileStorage: fileStorage)
        return .file(filename: filename, contentType: contentType, location: location, linkType: linkType, compressed: compressed)
    }

    private static func linkedFileType(item: RItem, libraryId: LibraryIdentifier) -> Attachment.Kind? {
        guard let contentType = item.fields.first(where: { $0.key == FieldKeys.Item.Attachment.contentType })?.value, !contentType.isEmpty else {
            DDLogError("AttachmentCreator: content type missing for item \(item.key)")
            return nil
        }
        guard let path = item.fields.first(where: { $0.key == FieldKeys.Item.Attachment.path })?.value, !path.isEmpty else {
            DDLogError("AttachmentCreator: path missing for item \(item.key)")
            return nil
        }
        let filename = filename(for: item, ext: URL(fileURLWithPath: path).pathExtension)
        return .file(filename: filename, contentType: contentType, location: .local, linkType: .linkedFile, compressed: false)
    }

    private static func linkedUrlType(for item: RItem, libraryId: LibraryIdentifier, urlDetector: UrlDetector) -> Attachment.Kind? {
        guard let urlString = item.fields.first(where: { $0.key == FieldKeys.Item.Attachment.url })?.value else {
            DDLogError("AttachmentCreator: url missing for item \(item.key)")
            return nil
        }
        guard let url = URL(string: urlString), urlDetector.isUrl(string: urlString) else {
            DDLogError("AttachmentCreator: url invalid '\(urlString)'")
            return nil
        }
        return .url(url)
    }

    // MARK: - Helpers

    private static func filename(for item: RItem, ext: String?) -> String {
        if let filename = item.fields.first(where: { $0.key == FieldKeys.Item.Attachment.filename })?.value {
            return filename
        }
        if let ext = ext {
            return item.displayTitle + "." + ext
        }
        return item.displayTitle
    }

    static func contentType(for item: RItem) -> String? {
        if let contentType = item.fields.first(where: { $0.key == FieldKeys.Item.Attachment.contentType })?.value, !contentType.isEmpty {
            return contentType
        }

        if let filename = item.fields.first(where: { $0.key == FieldKeys.Item.Attachment.filename })?.value {
            let split = filename.split(separator: ".")
            if split.count > 1, let ext = split.last.flatMap(String.init), let contentType = ext.mimeTypeFromExtension {
                return contentType
            }
        }

        if let title = item.fields.first(where: { $0.key == FieldKeys.Item.Attachment.title })?.value {
            let split = title.split(separator: ".")
            if split.count > 1, let ext = split.last.flatMap(String.init), let contentType = ext.mimeTypeFromExtension {
                return contentType
            }
        }

        DDLogError("AttachmentCreator: contentType can't be found for \(item.key)")

        return nil
    }

    private static func location(for item: RItem, file: File, fileStorage: FileStorage?) -> Attachment.FileLocation {
        // If file storage is not specified, we don't care about location anyway. Let's just return `.remote`.
        guard let fileStorage = fileStorage else { return .remote }

        let webDavEnabled = Defaults.shared.webDavEnabled

        if fileStorage.has(file) || (webDavEnabled && fileStorage.has(file.copy(withExt: "zip"))) {
            if !item.backendMd5.isEmpty, let md5 = cachedMD5(from: file.createUrl(), using: fileStorage.fileManager), item.backendMd5 != md5 {
                return .localAndChangedRemotely
            } else {
                return .local
            }
        } else if webDavEnabled || item.links.contains(where: { $0.type == LinkType.enclosure.rawValue }) {
            return .remote
        } else {
            return .remoteMissing
        }
    }
}
