//
//  DocumentPreviewController.swift
//  Zotero
//
//  Created by Michal Rentka on 16.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import ImageIO
import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import RxSwift
import ZIPFoundation

/// Creates and stores cover/preview images of documents (PDF, EPUB). Used as artwork for Now Playing and CarPlay.
final class DocumentPreviewController {
    enum Error: Swift.Error {
        case unsupportedContentType
        case cantCreateImageData
    }

    /// Longest side of stored preview, in pixels.
    private static let maxPixelSize: CGFloat = 1024
    private static let jpegQuality: CGFloat = 0.85

    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let fileStorage: FileStorage

    init(fileStorage: FileStorage) {
        queue = DispatchQueue(label: "org.zotero.DocumentPreviewController.queue", qos: .utility)
        scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.DocumentPreviewController.scheduler")
        self.fileStorage = fileStorage
    }

    static func supports(contentType: String) -> Bool {
        switch contentType {
        case "application/pdf", "application/epub+zip":
            return true

        default:
            return false
        }
    }

    /// Returns already stored preview for given attachment, if available.
    func storedPreview(key: String, libraryId: LibraryIdentifier) -> File? {
        let file = Files.documentPreview(key: key, libraryId: libraryId)
        return fileStorage.has(file) ? file : nil
    }

    /// Returns stored preview for given attachment, or creates and stores a new one. Requests are processed serially.
    /// - parameter url: Url of attachment file.
    /// - parameter contentType: Content type of attachment file.
    /// - parameter key: Attachment item key.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter overwrite: If `true`, existing preview is regenerated.
    /// - returns: File with stored preview image, or `nil` if document doesn't have a suitable preview.
    func preview(for url: URL, contentType: String, key: String, libraryId: LibraryIdentifier, overwrite: Bool = false) -> Single<File?> {
        return Single.create { [weak self] subscriber in
            guard let self else {
                subscriber(.success(nil))
                return Disposables.create()
            }

            let file = Files.documentPreview(key: key, libraryId: libraryId)
            if !overwrite && fileStorage.has(file) {
                subscriber(.success(file))
                return Disposables.create()
            }

            do {
                let image: CGImage?
                switch contentType {
                case "application/pdf":
                    image = try autoreleasepool { try PDFPreviewRenderer.render(url: url, maxPixelSize: Self.maxPixelSize) }

                case "application/epub+zip":
                    image = try autoreleasepool { try EPUBCoverExtractor.extract(url: url, maxPixelSize: Self.maxPixelSize) }

                default:
                    throw Error.unsupportedContentType
                }

                guard let image else {
                    DDLogInfo("DocumentPreviewController: no preview available; key=\(key); library=\(libraryId)")
                    try? fileStorage.remove(file)
                    subscriber(.success(nil))
                    return Disposables.create()
                }

                guard let data = autoreleasepool(invoking: { Self.jpegData(from: image) }) else { throw Error.cantCreateImageData }
                try fileStorage.write(data, to: file, options: .atomicWrite)
                subscriber(.success(file))
            } catch let error {
                DDLogError("DocumentPreviewController: can't create preview; key=\(key); library=\(libraryId); contentType=\(contentType); error=\(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
        .subscribe(on: scheduler)
    }

    func delete(key: String, libraryId: LibraryIdentifier) {
        queue.async { [weak self] in
            try? self?.fileStorage.remove(Files.documentPreview(key: key, libraryId: libraryId))
        }
    }

    /// Draws image into an opaque white context, so that transparent images don't end up with black background, and encodes it as JPEG.
    private static func jpegData(from image: CGImage) -> Data? {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: jpegQuality) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - PDF

/// Picks a page suitable for a cover image from the first few pages of a PDF document and renders it.
///
/// Each candidate page is rendered as a small thumbnail and measured for ink coverage (non-white pixels), color coverage
/// (saturated pixels), number of text glyphs and presence of large (title-sized) text. Then:
/// 1. The first non-blank page is chosen if it looks like a cover (lots of ink or color and not much text) or a title page (large text).
///    Covers and title pages are almost always the first page, so we prefer it over an image found later.
/// 2. Otherwise the first later page which looks strongly like a cover (mostly image, little text) is chosen. This handles documents
///    which start with a publisher/repository sheet, blank or copyright page, followed by an actual cover.
/// 3. Otherwise the first non-blank page is chosen. For text-heavy documents (papers) the first page with title is the most recognizable.
private enum PDFPreviewRenderer {
    private struct PageMetrics {
        let pageIndex: PageIndex
        let inkCoverage: Double
        let colorCoverage: Double
        let glyphCount: Int
        let hasLargeText: Bool

        var isBlank: Bool {
            return inkCoverage < 0.005 && glyphCount < 20
        }

        var isCoverLike: Bool {
            return (inkCoverage >= 0.3 || colorCoverage >= 0.1) && glyphCount < 1500
        }

        var isStrongCover: Bool {
            return (inkCoverage >= 0.5 || colorCoverage >= 0.2) && glyphCount < 300
        }
    }

    private static let maxCandidatePages: PageCount = 5
    private static let analysisPixelSize: CGFloat = 128
    /// Minimal glyph height, relative to page height, to be considered large title text. ~20pt on a letter-sized page.
    private static let largeTextRelativeHeight: CGFloat = 0.025
    private static let minLargeGlyphCount = 5

    static func render(url: URL, maxPixelSize: CGFloat) throws -> CGImage? {
        let document = Document(url: url)
        guard document.isValid, !document.isLocked, document.pageCount > 0 else { return nil }
        guard let pageIndex = pickPage(in: document), let pageInfo = document.pageInfoForPage(at: pageIndex) else { return nil }
        let image = try document.imageForPage(
            at: pageIndex,
            size: fittedSize(of: pageInfo.size, maxPixelSize: maxPixelSize),
            clippedTo: .zero,
            annotations: [],
            options: nil
        )
        return image.cgImage
    }

    private static func pickPage(in document: Document) -> PageIndex? {
        let metrics = (0..<min(document.pageCount, maxCandidatePages)).compactMap({ pageIndex in
            autoreleasepool { measure(pageIndex: pageIndex, in: document) }
        })
        guard let first = metrics.first(where: { !$0.isBlank }) else { return nil }
        if first.isCoverLike || first.hasLargeText {
            return first.pageIndex
        }
        if let cover = metrics.first(where: { $0.pageIndex > first.pageIndex && $0.isStrongCover }) {
            return cover.pageIndex
        }
        return first.pageIndex
    }

    private static func measure(pageIndex: PageIndex, in document: Document) -> PageMetrics? {
        guard let pageInfo = document.pageInfoForPage(at: pageIndex), pageInfo.size.height > 0 else { return nil }
        let size = fittedSize(of: pageInfo.size, maxPixelSize: analysisPixelSize)
        guard let image = try? document.imageForPage(at: pageIndex, size: size, clippedTo: .zero, annotations: [], options: nil),
              let coverage = image.cgImage.flatMap(coverage(of:))
        else { return nil }

        let glyphs = (document.textParserForPage(at: pageIndex)?.glyphs ?? []).filter({ !$0.isWordOrLineBreaker })
        let minLargeHeight = pageInfo.size.height * largeTextRelativeHeight
        let largeGlyphCount = glyphs.reduce(0, { $0 + ($1.frame.height >= minLargeHeight ? 1 : 0) })

        return PageMetrics(
            pageIndex: pageIndex,
            inkCoverage: coverage.ink,
            colorCoverage: coverage.color,
            glyphCount: glyphs.count,
            hasLargeText: largeGlyphCount >= minLargeGlyphCount
        )
    }

    /// Returns fraction of non-white pixels and fraction of saturated (colored) pixels in image.
    private static func coverage(of image: CGImage) -> (ink: Double, color: Double)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(UIColor.white.cgColor)
            context.fill(rect)
            context.draw(image, in: rect)
            return true
        }
        guard didDraw else { return nil }

        var inkCount = 0
        var colorCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let chroma = max(red, green, blue) - min(red, green, blue)
            let luma = (299 * red + 587 * green + 114 * blue) / 1000
            if chroma > 40 {
                colorCount += 1
                inkCount += 1
            } else if luma < 230 {
                inkCount += 1
            }
        }
        let pixelCount = Double(width * height)
        return (Double(inkCount) / pixelCount, Double(colorCount) / pixelCount)
    }

    private static func fittedSize(of size: CGSize, maxPixelSize: CGFloat) -> CGSize {
        let scale = maxPixelSize / max(size.width, size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

// MARK: - EPUB

/// Finds cover image of EPUB document based on its package metadata.
///
/// Looks for cover in following order:
/// 1. EPUB 3 manifest item with `cover-image` property.
/// 2. EPUB 2 `<meta name="cover" content="{item id}"/>`.
/// 3. Manifest image item with "cover" in its id or href.
/// 4. First image in cover page XHTML (`<guide>` reference with type "cover", or manifest item with "cover" id).
private enum EPUBCoverExtractor {
    /// Protects against decompressing unreasonably large entries.
    private static let maxEntrySize: UInt64 = 50 * 1024 * 1024
    private static let minImagePixelSize = 64

    static func extract(url: URL, maxPixelSize: CGFloat) throws -> CGImage? {
        let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        guard let containerData = data(at: "META-INF/container.xml", in: archive),
              let packagePath = ContainerParser.packagePath(from: containerData),
              let packageData = data(at: packagePath, in: archive)
        else { return nil }

        let package = PackageParser.parse(data: packageData)
        let packageDirectory = (packagePath as NSString).deletingLastPathComponent

        for href in imageCandidates(in: package) {
            guard let path = resolve(href: href, relativeTo: packageDirectory) else { continue }
            if let image = image(at: path, in: archive, maxPixelSize: maxPixelSize) {
                return image
            }
        }

        for href in coverPageCandidates(in: package) {
            guard let pagePath = resolve(href: href, relativeTo: packageDirectory),
                  let pageData = data(at: pagePath, in: archive),
                  let imageHref = CoverPageParser.firstImageHref(from: pageData),
                  let imagePath = resolve(href: imageHref, relativeTo: (pagePath as NSString).deletingLastPathComponent)
            else { continue }
            if let image = image(at: imagePath, in: archive, maxPixelSize: maxPixelSize) {
                return image
            }
        }

        return nil
    }

    private static func imageCandidates(in package: PackageParser.Package) -> [String] {
        let images = package.items.filter({ $0.mediaType.hasPrefix("image/") })
        var candidates: [String] = []
        candidates += images.filter({ $0.properties.contains("cover-image") }).map(\.href)
        if let coverId = package.coverId, let item = images.first(where: { $0.id == coverId }) {
            candidates.append(item.href)
        }
        candidates += images.filter({ $0.id.lowercased().contains("cover") || $0.href.lowercased().contains("cover") }).map(\.href)
        return candidates.removingDuplicates()
    }

    private static func coverPageCandidates(in package: PackageParser.Package) -> [String] {
        let pages = package.items.filter({ $0.mediaType == "application/xhtml+xml" && $0.id.lowercased().contains("cover") }).map(\.href)
        return (package.guideCoverHrefs + pages).removingDuplicates()
    }

    private static func image(at path: String, in archive: Archive, maxPixelSize: CGFloat) -> CGImage? {
        guard let data = data(at: path, in: archive), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              min(image.width, image.height) >= minImagePixelSize
        else { return nil }
        return image
    }

    private static func data(at path: String, in archive: Archive) -> Data? {
        guard let entry = archive[path], entry.type == .file, entry.uncompressedSize <= maxEntrySize else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry, skipCRC32: true, consumer: { data.append($0) })
            return data
        } catch let error {
            DDLogWarn("DocumentPreviewController: can't extract epub entry; path=\(path); error=\(error)")
            return nil
        }
    }

    /// Resolves (possibly relative and percent-encoded) href to an archive path.
    private static func resolve(href: String, relativeTo directory: String) -> String? {
        let base = URL(fileURLWithPath: "/" + directory, isDirectory: true)
        guard let url = URL(string: href, relativeTo: base) ?? href.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap({ URL(string: $0, relativeTo: base) }),
              url.isFileURL
        else { return nil }
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    // MARK: - Parsers

    private final class ContainerParser: NSObject, XMLParserDelegate {
        private var packagePath: String?

        static func packagePath(from data: Data) -> String? {
            let delegate = ContainerParser()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = delegate
            parser.parse()
            return delegate.packagePath
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            guard elementName == "rootfile", let path = attributeDict["full-path"], !path.isEmpty else { return }
            packagePath = path
            parser.abortParsing()
        }
    }

    private final class PackageParser: NSObject, XMLParserDelegate {
        struct Item {
            let id: String
            let href: String
            let mediaType: String
            let properties: [String]
        }

        struct Package {
            let items: [Item]
            let coverId: String?
            let guideCoverHrefs: [String]
        }

        private var items: [Item] = []
        private var coverId: String?
        private var guideCoverHrefs: [String] = []

        static func parse(data: Data) -> Package {
            let delegate = PackageParser()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = delegate
            parser.parse()
            return Package(items: delegate.items, coverId: delegate.coverId, guideCoverHrefs: delegate.guideCoverHrefs)
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "item":
                guard let id = attributeDict["id"], let href = attributeDict["href"] else { return }
                let properties = (attributeDict["properties"] ?? "").split(separator: " ").map(String.init)
                items.append(Item(id: id, href: href, mediaType: attributeDict["media-type"] ?? "", properties: properties))

            case "meta":
                guard attributeDict["name"] == "cover", let content = attributeDict["content"] else { return }
                coverId = content

            case "reference":
                guard attributeDict["type"]?.lowercased() == "cover", let href = attributeDict["href"] else { return }
                guideCoverHrefs.append(href)

            default:
                break
            }
        }
    }

    private final class CoverPageParser: NSObject, XMLParserDelegate {
        private var href: String?

        static func firstImageHref(from data: Data) -> String? {
            let delegate = CoverPageParser()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = delegate
            parser.parse()
            return delegate.href
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let href: String?
            switch elementName {
            case "img":
                href = attributeDict["src"]

            case "image":
                href = attributeDict["xlink:href"] ?? attributeDict["href"]

            default:
                href = nil
            }
            guard let href, !href.isEmpty else { return }
            self.href = href
            parser.abortParsing()
        }
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen: Set<String> = []
        return filter({ seen.insert($0).inserted })
    }
}
