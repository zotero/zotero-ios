//
//  FontMetadata.swift
//  Zotero
//
//  Created by Basil on 18.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import CoreText

struct FontMetadata: Codable, Equatable {
    let fileName: String
    let displayName: String
    let familyName: String
    let postScriptName: String
    let weight: FontWeight
    let isItalic: Bool
    let dateAdded: Date
    let fileSize: Int64
    
    enum FontWeight: String, Codable, Equatable {
        case ultraLight = "UltraLight"
        case thin = "Thin"
        case light = "Light"
        case regular = "Regular"
        case medium = "Medium"
        case semibold = "Semibold"
        case bold = "Bold"
        case heavy = "Heavy"
        case black = "Black"
        
        var displayName: String {
            switch self {
            case .ultraLight: return "Ultra Light"
            case .thin: return "Thin"
            case .light: return "Light"
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .semibold: return "Semibold"
            case .bold: return "Bold"
            case .heavy: return "Heavy"
            case .black: return "Black"
            }
        }
    }
    
    static func extractMetadata(from url: URL) -> FontMetadata? {
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(dataProvider),
              let postScriptName = font.postScriptName as String?,
              let fullName = font.fullName as String? else {
            return nil
        }
        
        // Determine weight from font name
        let weight = determineWeight(from: postScriptName)
        let isItalic = postScriptName.lowercased().contains("italic") || postScriptName.lowercased().contains("oblique")
        
        // Get file size
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? Int64 ?? 0
        
        return FontMetadata(
            fileName: url.lastPathComponent,
            displayName: fullName,
            familyName: extractFamilyName(from: fullName, postScriptName: postScriptName),
            postScriptName: postScriptName,
            weight: weight,
            isItalic: isItalic,
            dateAdded: Date(),
            fileSize: fileSize
        )
    }
    
    private static func determineWeight(from name: String) -> FontWeight {
        let lowercased = name.lowercased()
        if lowercased.contains("ultralight") { return .ultraLight }
        if lowercased.contains("thin") { return .thin }
        if lowercased.contains("light") { return .light }
        if lowercased.contains("medium") { return .medium }
        if lowercased.contains("semibold") || lowercased.contains("semi-bold") { return .semibold }
        if lowercased.contains("bold") { return .bold }
        if lowercased.contains("heavy") { return .heavy }
        if lowercased.contains("black") { return .black }
        return .regular
    }
    
    private static func extractFamilyName(from fullName: String, postScriptName: String) -> String {
        // Try to extract family name by removing weight and style suffixes
        let suffixes = ["UltraLight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black", "Italic", "Oblique"]
        var family = fullName
        for suffix in suffixes {
            if family.hasSuffix(suffix) {
                family = String(family.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            }
        }
        return family.isEmpty ? fullName : family
    }
}
