//
//  TypesettingSettings.swift
//  Zotero
//
//  Created by Basil on 18.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Comprehensive typesetting settings inspired by KOReader's functionality
struct TypesettingSettings: Codable, Equatable {
    // Font settings
    var fontFamily: String?
    var fontSize: CGFloat
    var fontWeight: FontWeight
    var fontHinting: FontHinting
    var fontKerning: FontKerning
    var contrast: CGFloat // Text boldness via rendering (0.5 to 2.0)
    
    // Text formatting
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var wordSpacing: WordSpacing
    var wordExpansion: WordExpansion // How much words can expand for justification
    var letterSpacing: CGFloat
    var textAlignment: TextAlignment
    var firstLineIndent: CGFloat
    var monospaceScale: CGFloat // Scale for monospace fonts (percentage)
    
    // Margins and layout
    var topMargin: CGFloat
    var bottomMargin: CGFloat
    var leftMargin: CGFloat
    var rightMargin: CGFloat
    var columnCount: Int
    var columnGap: CGFloat
    
    // Advanced typography
    var hyphenation: Bool
    var ligatures: Bool
    var justification: Justification
    var widowOrphanControl: Bool
    
    // Document-specific overrides
    var ignorePublisherStyles: Bool
    var ignorePublisherFonts: Bool
    
    enum FontWeight: String, Codable, Equatable, CaseIterable {
        case lighter = "Lighter"
        case normal = "Normal"
        case medium = "Medium"
        case semibold = "Semibold"
        case bold = "Bold"
        case bolder = "Bolder"
        
        var multiplier: CGFloat {
            switch self {
            case .lighter: return 0.85
            case .normal: return 1.0
            case .medium: return 1.1
            case .semibold: return 1.2
            case .bold: return 1.3
            case .bolder: return 1.4
            }
        }
    }
    
    enum FontHinting: String, Codable, Equatable, CaseIterable {
        case none = "None"
        case slight = "Slight"
        case medium = "Medium"
        case full = "Full"
        case native = "Native"
    }
    
    enum FontKerning: String, Codable, Equatable, CaseIterable {
        case none = "None"
        case minimal = "Minimal"
        case normal = "Normal"
        case enhanced = "Enhanced"
    }
    
    enum WordSpacing: String, Codable, Equatable, CaseIterable {
        case veryCompressed = "Very Compressed"
        case compressed = "Compressed"
        case normal = "Normal"
        case expanded = "Expanded"
        case veryExpanded = "Very Expanded"
        
        var multiplier: CGFloat {
            switch self {
            case .veryCompressed: return 0.75
            case .compressed: return 0.875
            case .normal: return 1.0
            case .expanded: return 1.125
            case .veryExpanded: return 1.25
            }
        }
    }
    
    enum WordExpansion: String, Codable, Equatable, CaseIterable {
        case none = "None"
        case minimal = "Minimal"
        case normal = "Normal"
        case enhanced = "Enhanced"
        case maximum = "Maximum"
        
        var multiplier: CGFloat {
            switch self {
            case .none: return 0.0
            case .minimal: return 0.25
            case .normal: return 0.5
            case .enhanced: return 0.75
            case .maximum: return 1.0
            }
        }
    }
    
    enum TextAlignment: String, Codable, Equatable, CaseIterable {
        case left = "Left"
        case right = "Right"
        case center = "Center"
        case justified = "Justified"
        case auto = "Auto"
    }
    
    enum Justification: String, Codable, Equatable, CaseIterable {
        case none = "None"
        case leftRight = "Left & Right"
        case full = "Full"
    }
    
    static var `default`: TypesettingSettings {
        return TypesettingSettings(
            fontFamily: nil,
            fontSize: 16.0,
            fontWeight: .normal,
            fontHinting: .medium,
            fontKerning: .normal,
            contrast: 1.0,
            lineSpacing: 1.2,
            paragraphSpacing: 0.5,
            wordSpacing: .normal,
            wordExpansion: .normal,
            letterSpacing: 0.0,
            textAlignment: .auto,
            firstLineIndent: 1.5,
            monospaceScale: 1.0,
            topMargin: 20.0,
            bottomMargin: 20.0,
            leftMargin: 15.0,
            rightMargin: 15.0,
            columnCount: 1,
            columnGap: 20.0,
            hyphenation: true,
            ligatures: true,
            justification: .leftRight,
            widowOrphanControl: true,
            ignorePublisherStyles: false,
            ignorePublisherFonts: false
        )
    }
}
