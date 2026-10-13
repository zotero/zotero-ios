//
//  PDFLinkDestinationResolver.swift
//  Zotero
//
//  Created by Victor Puga on 09/10/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import CoreGraphics
import Foundation

import CocoaLumberjackSwift
import PSPDFKit

/// Reads the position of internal link destinations straight from the PDF structure.
/// PSPDFKit's `GoToAction` only exposes the destination page index, and PDFKit doesn't report a point for many destinations.
enum PDFLinkDestinationResolver {
    private static let maxNameResolutionDepth = 4
    private static let maxNameTreeDepth = 8
    /// Allowed difference between the requested and the annotation rect, summed over all edges, in PDF points.
    private static let rectTolerance: CGFloat = 10

    /// Resolves how far from the top of the destination page a link points to.
    /// - parameter linkRect: Rect of the link annotation in PDF coordinates.
    /// - parameter pageIndex: Index of the page containing the link.
    /// - parameter url: Location of the PDF file.
    /// - returns: Distance from the top of the destination page's crop box in PDF points, or `nil` if the destination has no vertical position.
    static func destinationOffsetFromTop(of linkRect: CGRect, on pageIndex: PageIndex, in url: URL) -> CGFloat? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: Int(pageIndex) + 1), let pageDictionary = page.dictionary, let catalog = document.catalog else {
            DDLogWarn("PDFLinkDestinationResolver: can't open page \(pageIndex)")
            return nil
        }
        guard let annotation = linkAnnotation(matching: linkRect, in: pageDictionary),
              let destination = destinationObject(of: annotation),
              let (destinationPage, top) = resolve(destination: destination, catalog: catalog, document: document)
        else {
            DDLogWarn("PDFLinkDestinationResolver: can't resolve destination of link on page \(pageIndex)")
            return nil
        }
        return destinationPage.getBoxRect(.cropBox).maxY - top
    }

    private static func linkAnnotation(matching linkRect: CGRect, in pageDictionary: CGPDFDictionaryRef) -> CGPDFDictionaryRef? {
        var annotations: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations else { return nil }

        var best: (distance: CGFloat, annotation: CGPDFDictionaryRef)?
        for index in 0..<CGPDFArrayGetCount(annotations) {
            var annotation: CGPDFDictionaryRef?
            var rectArray: CGPDFArrayRef?
            guard CGPDFArrayGetDictionary(annotations, index, &annotation), let annotation,
                  CGPDFDictionaryGetArray(annotation, "Rect", &rectArray), let rectArray,
                  let values = numbers(in: rectArray), values.count == 4
            else { continue }
            let rect = CGRect(x: min(values[0], values[2]), y: min(values[1], values[3]), width: abs(values[2] - values[0]), height: abs(values[3] - values[1]))
            let distance = abs(rect.minX - linkRect.minX) + abs(rect.minY - linkRect.minY) + abs(rect.width - linkRect.width) + abs(rect.height - linkRect.height)
            if distance < (best?.distance ?? rectTolerance) {
                best = (distance, annotation)
            }
        }
        return best?.annotation
    }

    private static func destinationObject(of annotation: CGPDFDictionaryRef) -> CGPDFObjectRef? {
        var object: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(annotation, "Dest", &object) {
            return object
        }
        var action: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(annotation, "A", &action), let action, CGPDFDictionaryGetObject(action, "D", &object) {
            return object
        }
        return nil
    }

    /// Resolves explicit, named (catalog `Dests` or `Names` tree) and dictionary-wrapped destinations.
    private static func resolve(destination object: CGPDFObjectRef, catalog: CGPDFDictionaryRef, document: CGPDFDocument, depth: Int = 0) -> (page: CGPDFPage, top: CGFloat)? {
        guard depth < maxNameResolutionDepth else { return nil }

        var array: CGPDFArrayRef?
        if CGPDFObjectGetValue(object, .array, &array), let array {
            return explicitDestination(array, document: document)
        }

        var dictionary: CGPDFDictionaryRef?
        var inner: CGPDFObjectRef?
        if CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary {
            guard CGPDFDictionaryGetObject(dictionary, "D", &inner), let inner else { return nil }
            return resolve(destination: inner, catalog: catalog, document: document, depth: depth + 1)
        }

        guard let key = nameKey(of: object) else { return nil }

        var dests: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Dests", &dests), let dests,
           CGPDFDictionaryGetObject(dests, String(decoding: key, as: UTF8.self), &inner), let inner {
            return resolve(destination: inner, catalog: catalog, document: document, depth: depth + 1)
        }

        var names: CGPDFDictionaryRef?
        var tree: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names,
           CGPDFDictionaryGetDictionary(names, "Dests", &tree), let tree,
           let value = lookup(key: key, in: tree) {
            return resolve(destination: value, catalog: catalog, document: document, depth: depth + 1)
        }
        return nil
    }

    /// Reads `[page /Type args...]`. Only types with a vertical position are supported.
    private static func explicitDestination(_ array: CGPDFArrayRef, document: CGPDFDocument) -> (page: CGPDFPage, top: CGFloat)? {
        var pageDictionary: CGPDFDictionaryRef?
        var typeName: UnsafePointer<CChar>?
        guard CGPDFArrayGetDictionary(array, 0, &pageDictionary), let pageDictionary,
              CGPDFArrayGetName(array, 1, &typeName), let typeName,
              let page = (1...max(1, document.numberOfPages)).lazy.compactMap({ document.page(at: $0) }).first(where: { $0.dictionary == pageDictionary })
        else { return nil }

        let topIndex: Int
        switch String(cString: typeName) {
        case "XYZ":
            topIndex = 3

        case "FitH", "FitBH":
            topIndex = 2

        case "FitR":
            topIndex = 5

        default:
            return nil
        }
        var top: CGPDFReal = 0
        guard CGPDFArrayGetNumber(array, topIndex, &top) else { return nil }
        return (page, top)
    }

    private static func nameKey(of object: CGPDFObjectRef) -> [UInt8]? {
        var name: UnsafePointer<CChar>?
        if CGPDFObjectGetValue(object, .name, &name), let name {
            return Array(String(cString: name).utf8)
        }
        var string: CGPDFStringRef?
        if CGPDFObjectGetValue(object, .string, &string), let string {
            return bytes(of: string)
        }
        return nil
    }

    private static func bytes(of string: CGPDFStringRef) -> [UInt8]? {
        guard let pointer = CGPDFStringGetBytePtr(string) else { return nil }
        return Array(UnsafeBufferPointer(start: pointer, count: CGPDFStringGetLength(string)))
    }

    private static func lookup(key: [UInt8], in node: CGPDFDictionaryRef, depth: Int = 0) -> CGPDFObjectRef? {
        var pairs: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &pairs), let pairs {
            for index in stride(from: 0, to: CGPDFArrayGetCount(pairs) - 1, by: 2) {
                var string: CGPDFStringRef?
                guard CGPDFArrayGetString(pairs, index, &string), let string, bytes(of: string) == key else { continue }
                var value: CGPDFObjectRef?
                return CGPDFArrayGetObject(pairs, index + 1, &value) ? value : nil
            }
            return nil
        }

        var kids: CGPDFArrayRef?
        guard depth < maxNameTreeDepth, CGPDFDictionaryGetArray(node, "Kids", &kids), let kids else { return nil }
        for index in 0..<CGPDFArrayGetCount(kids) {
            var kid: CGPDFDictionaryRef?
            if CGPDFArrayGetDictionary(kids, index, &kid), let kid, let value = lookup(key: key, in: kid, depth: depth + 1) {
                return value
            }
        }
        return nil
    }

    private static func numbers(in array: CGPDFArrayRef) -> [CGFloat]? {
        return (0..<CGPDFArrayGetCount(array)).compactMap({ index in
            var value: CGPDFReal = 0
            return CGPDFArrayGetNumber(array, index, &value) ? value : nil
        })
    }
}
