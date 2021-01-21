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

    /// Returns attachment based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - parameter urlDetector: Url detector to validate url attachment.
    /// - returns: Attachment if recognized. Nil otherwise.
    static func attachment(for item: RItem, options: Options = .light, fileStorage: FileStorage, urlDetector: UrlDetector) -> Attachment? {
        return attachmentContentType(for: item, options: options, fileStorage: fileStorage, urlDetector: urlDetector).flatMap({ Attachment(item: item, type: $0) })
    }

    /// Returns attachment content type type based on attachment item.
    /// - parameter item: Attachment item to check.
    /// - parameter fileStorage: File storage to check availability of local attachment.
    /// - parameter urlDetector: Url detector to validate url attachment.
    /// - returns: Attachment content type if recognized. Nil otherwise.
    static func attachmentContentType(for item: RItem, options: Options = .light, fileStorage: FileStorage?, urlDetector: UrlDetector?) -> Attachment.ContentType? {
        guard let linkMode = item.fields.filter(.key(FieldKeys.Item.Attachment.linkMode)).first
                                        .flatMap({ LinkMode(rawValue: $0.value) }) else {
            DDLogError("AttachmentCreator: missing link mode for item \(item.key)")
            return nil
        }
        guard let libraryId = item.libraryId else {
            DDLogError("AttachmentCreator: missing library for item (\(item.key))")
            return nil
        }

        switch linkMode {
        case .importedFile:
            return self.importedFileContentType(for: item, libraryId: libraryId, fileStorage: fileStorage)
        case .embeddedImage:
            return self.embeddedImageContentType(for: item, libraryId: libraryId, options: options, fileStorage: fileStorage)
        case .importedUrl:
            return self.importedUrlContentType(item: item, libraryId: libraryId, fileStorage: fileStorage)
        case .linkedFile:
            return self.linkedFileContentType(item: item, libraryId: libraryId)
        case .linkedUrl:
            guard let urlDetector = urlDetector else { return nil }
            return self.linkedUrlContentType(for: item, libraryId: libraryId, urlDetector: urlDetector)
        }
    }

    private static func embeddedImageContentType(for item: RItem, libraryId: LibraryIdentifier, options: Options, fileStorage: FileStorage?) -> Attachment.ContentType? {
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
        let file = Files.annotationPreview(annotationKey: parent.key, pdfKey: attachmentItem.key, isDark: (options == .dark))
        let location = fileStorage.flatMap({ self.location(for: item, file: file, fileStorage: $0) })
        let filename = self.filename(for: item, file: file)
        return .file(file: file, filename: filename, location: location, linkType: .imported)
    }

    private static func importedFileContentType(for item: RItem, libraryId: LibraryIdentifier, fileStorage: FileStorage?) -> Attachment.ContentType? {
        guard let fileType = self.fileType(for: item) else { return nil }
        return self.fileContentType(for: item, libraryId: libraryId, fileType: fileType, linkType: .imported, fileStorage: fileStorage)
    }

    private static func importedUrlContentType(item: RItem, libraryId: LibraryIdentifier, fileStorage: FileStorage?) -> Attachment.ContentType? {
        guard let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value, !contentType.isEmpty else {
            DDLogError("AttachmentCreator: content type missing for item \(item.key)")
            return nil
        }

        switch contentType {
        case "application/pdf":
            if let fileType = self.fileType(for: item) {
                return self.fileContentType(for: item, libraryId: libraryId, fileType: fileType, linkType: .imported, fileStorage: fileStorage)
            }
            return nil

        case "text/html":
            guard let filename = item.fields.filter(.key(FieldKeys.Item.Attachment.filename)).first?.value else {
                DDLogError("AttachmentCreator: filename missing for item \(item.key)")
                return nil
            }
            let htmlFile = Files.snapshotHtmlFile(in: libraryId, key: item.key, filename: filename)
            let zipFile = Files.snapshotZipFile(in: libraryId, key: item.key)
            let location = fileStorage.flatMap({ self.location(for: item, file: zipFile, fileStorage: $0) })
            return .snapshot(htmlFile: htmlFile, filename: filename, zipFile: zipFile, location: location)

        default:
            DDLogError("AttachmentCreator: content type invalid (\(contentType)) for snapshot \(item.key)")
            return nil
        }
    }

    private static func fileType(for item: RItem) -> FileType? {
        if let title = item.fields.filter(.key(FieldKeys.Item.Attachment.title)).first?.value {
            let split = title.split(separator: ".")
            if split.count > 1, let ext = split.last.flatMap(String.init),
               // Chech whether detected extension is valid
               ext.mimeTypeFromExtension != nil {
                return .extension(ext)
            }
        }

        if let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value, !contentType.isEmpty {
            return .contentType(contentType)
        }

        DDLogError("AttachmentCreator: filename and contentType missing for item \(item.key)")
        return nil
    }

    private static func fileContentType(for item: RItem, libraryId: LibraryIdentifier, fileType: FileType, linkType: Attachment.FileLinkType, fileStorage: FileStorage?) -> Attachment.ContentType {
        let file: File
        switch fileType {
        case .extension(let ext): file = Files.attachmentFile(in: libraryId, key: item.key, ext: ext)
        case .contentType(let contentType): file = Files.attachmentFile(in: libraryId, key: item.key, contentType: contentType)
        }
        let location = fileStorage.flatMap({ self.location(for: item, file: file, fileStorage: $0) })
        let filename = self.filename(for: item, file: file)
        return .file(file: file, filename: filename, location: location, linkType: linkType)
    }

    private static func linkedFileContentType(item: RItem, libraryId: LibraryIdentifier) -> Attachment.ContentType? {
        guard let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value,
              !contentType.isEmpty else {
            DDLogError("AttachmentCreator: content type missing for item \(item.key)")
            return nil
        }
        guard let path = item.fields.filter(.key(FieldKeys.Item.Attachment.path)).first?.value,
              !path.isEmpty else {
            DDLogError("AttachmentCreator: path missing for item \(item.key)")
            return nil
        }
        let file = Files.file(from: URL(fileURLWithPath: path))
        let filename = self.filename(for: item, file: file)
        return .file(file: file, filename: filename, location: .local, linkType: .linked)
    }

    private static func linkedUrlContentType(for item: RItem, libraryId: LibraryIdentifier, urlDetector: UrlDetector) -> Attachment.ContentType? {
        guard let urlString = item.fields.filter("key = %@", "url").first?.value else {
            DDLogError("AttachmentCreator: url missing for item \(item.key)")
            return nil
        }
        guard let url = URL(string: urlString), urlDetector.isUrl(string: urlString) else {
            DDLogError("AttachmentCreator: url invalid '\(urlString)'")
            return nil
        }
        return .url(url)
    }

    private static func filename(for item: RItem, file: File) -> String {
        return item.fields.filter(.key(FieldKeys.Item.Attachment.filename)).first?.value ?? (item.displayTitle + "." + file.ext)
    }

    private static func location(for item: RItem, file: File, fileStorage: FileStorage) -> Attachment.FileLocation? {
        if fileStorage.has(file) {
            return .local
        } else if item.links.filter(.linkType(.enclosure)).first != nil {
            return .remote
        } else {
            return nil
        }
    }
}
