//
//  TypesettingApplicator.swift
//  Zotero
//
//  Created by Basil on 18.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift

/// Applies typesetting settings to HTML/EPUB documents
final class TypesettingApplicator {
    /// Generate CSS from typesetting settings
    static func generateCSS(from settings: TypesettingSettings, appearance: ReaderSettingsState.Appearance) -> String {
        DDLogInfo("TypesettingApplicator: Generating CSS with font: \(settings.fontFamily ?? "none")")
        var css = ""
        
        // Font family - apply to all text elements
        if let fontFamily = settings.fontFamily {
            // Apply to body and all common text elements with high specificity
            css += "* { font-family: \(fontFamily), -apple-system, system-ui, sans-serif !important; }\n"
            css += "body, p, div, span, h1, h2, h3, h4, h5, h6, li, td, th { font-family: \(fontFamily), -apple-system, system-ui, sans-serif !important; }\n"
        }
        
        // Font size
        css += "body { font-size: \(settings.fontSize)pt !important; }\n"
        css += "p, div, span { font-size: \(settings.fontSize)pt !important; }\n"
        
        // Font weight
        let weightValue = settings.fontWeight.multiplier
        css += "body { font-weight: \(Int(weightValue * 400)) !important; }\n"
        
        // Contrast (text boldness via stroke)
        if settings.contrast != 1.0 {
            let strokeWidth = (settings.contrast - 1.0) * 0.5
            css += "body { -webkit-text-stroke-width: \(strokeWidth)px; }\n"
            // For better contrast on dark backgrounds
            css += "body { paint-order: stroke fill; }\n"
        }
        
        // Line spacing
        css += "p, div, span { line-height: \(settings.lineSpacing) !important; }\n"
        
        // Paragraph spacing
        if settings.paragraphSpacing > 0 {
            css += "p { margin-top: \(settings.paragraphSpacing)em !important; margin-bottom: \(settings.paragraphSpacing)em !important; }\n"
        }
        
        // Word spacing
        let wordSpacingValue = settings.wordSpacing.multiplier
        if wordSpacingValue != 1.0 {
            css += "body { word-spacing: \(wordSpacingValue - 1.0)em !important; }\n"
        }
        
        // Word expansion (for justification)
        let wordExpansionValue = settings.wordExpansion.multiplier
        if wordExpansionValue > 0 {
            css += "p { word-spacing: 0 \(wordExpansionValue * 0.1)em !important; }\n"
        }
        
        // Letter spacing
        if settings.letterSpacing != 0 {
            css += "body { letter-spacing: \(settings.letterSpacing)em !important; }\n"
        }
        
        // Text alignment
        switch settings.textAlignment {
        case .left:
            css += "p, div { text-align: left !important; }\n"

        case .right:
            css += "p, div { text-align: right !important; }\n"

        case .center:
            css += "p, div { text-align: center !important; }\n"

        case .justified:
            css += "p, div { text-align: justify !important; }\n"

        case .auto:
            break
        }
        
        // First line indent
        if settings.firstLineIndent > 0 {
            css += "p { text-indent: \(settings.firstLineIndent)em !important; }\n"
        }
        
        // Monospace font scaling
        if settings.monospaceScale != 1.0 {
            css += "code, pre, tt, kbd, samp { font-size: \(settings.monospaceScale * 100)% !important; }\n"
        }
        
        // Margins
        css += "body { "
        css += "margin-top: \(settings.topMargin)pt !important; "
        css += "margin-bottom: \(settings.bottomMargin)pt !important; "
        css += "margin-left: \(settings.leftMargin)pt !important; "
        css += "margin-right: \(settings.rightMargin)pt !important; "
        css += "}\n"
        
        // Multi-column layout
        if settings.columnCount > 1 {
            css += "body { "
            css += "column-count: \(settings.columnCount) !important; "
            css += "column-gap: \(settings.columnGap)pt !important; "
            css += "}\n"
        }
        
        // Hyphenation
        if settings.hyphenation {
            css += "p, div { hyphens: auto !important; -webkit-hyphens: auto !important; }\n"
        } else {
            css += "p, div { hyphens: none !important; -webkit-hyphens: none !important; }\n"
        }
        
        // Ligatures
        if settings.ligatures {
            css += "body { font-variant-ligatures: common-ligatures !important; }\n"
        } else {
            css += "body { font-variant-ligatures: none !important; }\n"
        }
        
        // Widow/Orphan control
        if settings.widowOrphanControl {
            css += "p { widows: 2; orphans: 2; }\n"
        }
        
        // Justification
        switch settings.justification {
        case .none:
            break

        case .leftRight:
            css += "p { text-align: justify; text-justify: inter-word; }\n"

        case .full:
            css += "p { text-align: justify; text-justify: inter-character; }\n"
        }
        
        // Font rendering hints
        switch settings.fontHinting {
        case .none:
            css += "body { -webkit-font-smoothing: none; }\n"

        case .slight:
            css += "body { -webkit-font-smoothing: antialiased; }\n"

        case .medium:
            css += "body { -webkit-font-smoothing: subpixel-antialiased; }\n"

        case .full:
            css += "body { -webkit-font-smoothing: auto; }\n"

        case .native:
            css += "body { -webkit-font-smoothing: auto; text-rendering: optimizeLegibility; }\n"
        }
        
        // Ignore publisher styles if requested
        if settings.ignorePublisherStyles {
            css += """
            * {
                font-family: inherit !important;
                line-height: inherit !important;
                font-size: inherit !important;
                margin: 0 !important;
                padding: 0 !important;
            }
            p, div { margin-top: 0.5em !important; margin-bottom: 0.5em !important; }
            """
        }
        
        // Appearance-specific styles
        switch appearance {
        case .dark:
            css += """
            body {
                background-color: #1a1a1a !important;
                color: #e0e0e0 !important;
            }
            """

        case .sepia:
            css += """
            body {
                background-color: #f4ecd8 !important;
                color: #5f4b32 !important;
            }
            """

        default:
            break
        }
        
        return css
    }
    
    /// Apply typesetting settings to a web view
    static func applySettings(_ settings: TypesettingSettings, appearance: ReaderSettingsState.Appearance, to webView: WKWebView) {
        DDLogInfo("TypesettingApplicator: Applying settings to webview")
        let css = generateCSS(from: settings, appearance: appearance)
        DDLogInfo("TypesettingApplicator: Generated CSS length: \(css.count) characters")
        DDLogInfo("TypesettingApplicator: CSS content:\n\(css)")
        
        let fontFamily = settings.fontFamily ?? ""
        let javascript = """
        (function() {
            // Function to apply styles to a document
            function applyStylesToDocument(doc) {
                // Remove existing custom style if present
                var existingStyle = doc.getElementById('zotero-custom-typesetting');
                if (existingStyle) {
                    existingStyle.remove();
                }
                
                // Create new style element
                var style = doc.createElement('style');
                style.id = 'zotero-custom-typesetting';
                style.textContent = `\(css)`;
                doc.head.appendChild(style);
                
                // Also apply font directly as inline style for maximum priority
                if ("\(fontFamily)") {
                    doc.body.style.setProperty('font-family', '\(fontFamily), -apple-system, system-ui, sans-serif', 'important');
                    // Apply to all elements
                    var allElements = doc.body.getElementsByTagName('*');
                    for (var i = 0; i < allElements.length; i++) {
                        allElements[i].style.setProperty('font-family', '\(fontFamily), -apple-system, system-ui, sans-serif', 'important');
                    }
                }
            }
            
            // Apply to main document
            applyStylesToDocument(document);
            
            // Find and apply to all iframes (EPUB content is typically in an iframe)
            var iframes = document.getElementsByTagName('iframe');
            for (var i = 0; i < iframes.length; i++) {
                try {
                    var iframeDoc = iframes[i].contentDocument || iframes[i].contentWindow.document;
                    if (iframeDoc) {
                        applyStylesToDocument(iframeDoc);
                    }
                } catch (e) {
                    console.log('Could not access iframe ' + i + ': ' + e);
                }
            }
        })();
        """
        
        webView.evaluateJavaScript(javascript) { _, error in
            if let error = error {
                DDLogError("TypesettingApplicator: Error applying typesetting: \(error)")
            } else {
                DDLogInfo("TypesettingApplicator: Successfully applied typesetting")
            }
        }
    }
    
    /// Create configuration object for passing to reader JavaScript
    static func createConfigurationObject(from settings: TypesettingSettings) -> [String: Any] {
        return [
            "fontFamily": settings.fontFamily ?? "",
            "fontSize": settings.fontSize,
            "fontWeight": settings.fontWeight.rawValue,
            "lineSpacing": settings.lineSpacing,
            "paragraphSpacing": settings.paragraphSpacing,
            "wordSpacing": settings.wordSpacing.rawValue,
            "letterSpacing": settings.letterSpacing,
            "textAlignment": settings.textAlignment.rawValue,
            "firstLineIndent": settings.firstLineIndent,
            "margins": [
                "top": settings.topMargin,
                "bottom": settings.bottomMargin,
                "left": settings.leftMargin,
                "right": settings.rightMargin
            ],
            "columnCount": settings.columnCount,
            "columnGap": settings.columnGap,
            "hyphenation": settings.hyphenation,
            "ligatures": settings.ligatures,
            "justification": settings.justification.rawValue,
            "widowOrphanControl": settings.widowOrphanControl,
            "ignorePublisherStyles": settings.ignorePublisherStyles,
            "ignorePublisherFonts": settings.ignorePublisherFonts
        ]
    }
}
