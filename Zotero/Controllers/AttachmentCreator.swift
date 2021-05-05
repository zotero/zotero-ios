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
            return self.attachment(for: item, fileStorage: fileStorage, urlDetector: nil)
        }

        var attachmentData = self.attachmentData(for: item)

        guard !attachmentData.isEmpty else { return nil }

        self.sortForMainAttachment(data: &attachmentData)

        guard let (idx, contentType, linkMode, _, _) = attachmentData.first else { return nil }
        let rAttachment = item.children[idx]
        let linkType: Attachment.FileLinkType = linkMode == .importedFile ? .importedFile : .importedUrl
        guard let libraryId = rAttachment.libraryId,
              let type = self.importedType(for: rAttachment, contentType: contentType, libraryId: libraryId, fileStorage: fileStorage, linkType: linkType) else { return nil }
        return Attachment(item: rAttachment, type: type)
    }

    private static func attachmentData(for item: RItem) -> [(Int, String, LinkMode, Bool, Date)] {
        let itemUrl = item.fields.first(where: { $0.key == FieldKeys.Item.url })?.value
        var data: [(Int, String, LinkMode, Bool, Date)] = []

        for (idx, child) in item.children.enumerated() {
            guard (child.rawType == ItemTypes.attachment && child.syncState != .dirty && !child.trash),
                  let linkMode = child.fields.first(where: { $0.key == FieldKeys.Item.Attachment.linkMode }).flatMap({ LinkMode(rawValue: $0.value) }),
                  (linkMode == .importedUrl || linkMode == .importedFile),
                  let contentType = self.contentType(for: child),
                  AttachmentCreator.mainAttachmentContentTypes.contains(contentType) else { continue }

            var hasMatchingUrlWithParent = false
            if let url = itemUrl, let childUrl = child.fields.first(where: { $0.key == FieldKeys.Item.Attachment.url })?.value {
                hasMatchingUrlWithParent = url == childUrl
            }
            data.append((idx, contentType, linkMode, hasMatchingUrlWithParent, child.dateAdded))
        }

        return data
    }

    private static func sortForMainAttachment(data: inout [(Int, String, LinkMode, Bool, Date)]) {
        data.sort { lData, rData in
            let lPriority = self.priority(for: lData.1)
            let rPriority = self.priority(for: rData.1)
            guard lPriority == rPriority else {
                // Sort based on content type priority
                return lPriority < rPriority
            }

            guard lData.3 == rData.3 else {
                // Sort based on whether attachment and parent item have matching urls
                return lData.3 && !rData.3
            }

            // Sort based on `dateAdded`.
            return lData.4.compare(rData.4) == .orderedAscending
        }
    }

    private static func priority(for contentType: String) -> Int {
        switch contentType {
        case "application/pdf": return 0
        case "text/html": return 1
        case "image/gif", "image/jpeg", "image/png": return 2
        case "text/plain": return 3
        default: return 4
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
            return self.importedType(for: item, libraryId: libraryId, fileStorage: fileStorage, linkType: .importedFile)
        case .embeddedImage:
            return self.embeddedImageType(for: item, libraryId: libraryId, options: options, fileStorage: fileStorage)
        case .importedUrl:
            return self.importedType(for: item, libraryId: libraryId, fileStorage: fileStorage, linkType: .importedUrl)
        case .linkedFile:
            return self.linkedFileType(item: item, libraryId: libraryId)
        case .linkedUrl:
            guard let urlDetector = urlDetector else { return nil }
            return self.linkedUrlType(for: item, libraryId: libraryId, urlDetector: urlDetector)
        }
    }

    private static func embeddedImageType(for item: RItem, libraryId: LibraryIdentifier, options: Options, fileStorage: FileStorage?) -> Attachment.Kind? {
        guard let parent = item.parent else {
            DDLogError("AttachmentCreator: embedded image without parent \(item.key)")
            return nil
        }
        guard parent.rawType == ItemTypes.annotation else {
            DDLogError("AttachmentCreator: embedded image with non-attachment parent \(item.key)")
            return nil
        }
        guard let attachmentItem = parent.parent else {
            DDLogError("AttachmentCreator: embedded image (\(item.key)) annotation without assigned parent \(parent.key)")
            return nil
        }
        let file = Files.annotationPreview(annotationKey: parent.key, pdfKey: attachmentItem.key, libraryId: libraryId, isDark: (options == .dark))
        let location = self.location(for: item, file: file, fileStorage: fileStorage)
        let filename = self.filename(for: item, ext: "png")
        return .file(filename: filename, contentType: "image/png", location: location, linkType: .embeddedImage)
    }

    private static func importedType(for item: RItem, libraryId: LibraryIdentifier, fileStorage: FileStorage?, linkType: Attachment.FileLinkType) -> Attachment.Kind? {
        guard let contentType = self.contentType(for: item) else { return nil }
        return self.importedType(for: item, contentType: contentType, libraryId: libraryId, fileStorage: fileStorage, linkType: linkType)
    }

    private static func importedType(for item: RItem, contentType: String, libraryId: LibraryIdentifier, fileStorage: FileStorage?, linkType: Attachment.FileLinkType) -> Attachment.Kind? {
        let filename = self.filename(for: item, ext: contentType.extensionFromMimeType)
        let file = Files.newAttachmentFile(in: libraryId, key: item.key, filename: filename, contentType: contentType)
        let location = self.location(for: item, file: file, fileStorage: fileStorage)
        return .file(filename: filename, contentType: contentType, location: location, linkType: linkType)
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
        let filename = self.filename(for: item, ext: URL(fileURLWithPath: path).pathExtension)
        return .file(filename: filename, contentType: contentType, location: .local, linkType: .linkedFile)
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

    private static func contentType(for item: RItem) -> String? {
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

        if fileStorage.has(file) {
            return .local
        } else if item.links.contains(where: { $0.type == LinkType.enclosure.rawValue }) {
            return .remote
        } else {
            return .remoteMissing
        }
    }
}
