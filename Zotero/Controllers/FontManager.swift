//
//  FontManager.swift
//  Zotero
//
//  Created by Basil on 18.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import UIKit
import CoreText
import CocoaLumberjackSwift

protocol FontManagerDelegate: AnyObject {
    func fontManager(_ manager: FontManager, didUpdateFonts fonts: [FontMetadata])
    func fontManager(_ manager: FontManager, didFailWithError error: Error)
}

final class FontManager {
    static let shared = FontManager()
    
    weak var delegate: FontManagerDelegate?
    
    private let fontDirectory: URL
    private let preferencesKey = "FontPreferences"
    private(set) var installedFonts: [FontMetadata] = []
    private(set) var preferences: FontPreferences
    
    enum FontError: LocalizedError {
        case invalidFontFile
        case fontAlreadyExists
        case copyFailed
        case registrationFailed
        case invalidFontFormat
        
        var errorDescription: String? {
            switch self {
            case .invalidFontFile: return "The selected file is not a valid font file"
            case .fontAlreadyExists: return "A font with this name already exists"
            case .copyFailed: return "Failed to copy font file"
            case .registrationFailed: return "Failed to register font with system"
            case .invalidFontFormat: return "Font format not supported. Please use TTF, OTF, or TTC files."
            }
        }
    }
    
    private init() {
        // Create custom fonts directory in app support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fontDirectory = appSupport.appendingPathComponent("CustomFonts", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: fontDirectory, withIntermediateDirectories: true)
        
        // Load preferences
        if let data = UserDefaults.standard.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode(FontPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = FontPreferences()
        }
        
        // Scan and register existing fonts
        scanInstalledFonts()
    }
    
    // MARK: - Font Installation
    
    func importFont(from url: URL) throws -> FontMetadata {
        DDLogInfo("FontManager: Importing font from \(url.path)")
        
        // Validate file extension
        let ext = url.pathExtension.lowercased()
        guard ext == "ttf" || ext == "otf" || ext == "ttc" else {
            throw FontError.invalidFontFormat
        }
        
        // Extract metadata
        guard let metadata = FontMetadata.extractMetadata(from: url) else {
            throw FontError.invalidFontFile
        }
        
        // Check if font already exists
        if installedFonts.contains(where: { $0.postScriptName == metadata.postScriptName }) {
            throw FontError.fontAlreadyExists
        }
        
        // Copy to fonts directory
        let destinationURL = fontDirectory.appendingPathComponent(metadata.fileName)
        do {
            // If file exists at destination, remove it first
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
        } catch {
            DDLogError("FontManager: Failed to copy font file - \(error)")
            throw FontError.copyFailed
        }
        
        // Register with CoreText
        guard registerFont(at: destinationURL) else {
            // Clean up if registration fails
            try? FileManager.default.removeItem(at: destinationURL)
            throw FontError.registrationFailed
        }
        
        // Add to installed fonts
        installedFonts.append(metadata)
        installedFonts.sort { $0.displayName < $1.displayName }
        
        delegate?.fontManager(self, didUpdateFonts: installedFonts)
        
        DDLogInfo("FontManager: Successfully imported font: \(metadata.displayName)")
        return metadata
    }
    
    func removeFont(_ metadata: FontMetadata) throws {
        DDLogInfo("FontManager: Removing font: \(metadata.displayName)")
        
        let fontURL = fontDirectory.appendingPathComponent(metadata.fileName)
        
        // Remove file
        try FileManager.default.removeItem(at: fontURL)
        
        // Remove from installed fonts
        installedFonts.removeAll { $0.postScriptName == metadata.postScriptName }
        
        // Clean up preferences if this font was set as default
        if preferences.defaultFont == metadata.postScriptName {
            preferences.defaultFont = nil
            savePreferences()
        }
        
        // Clean up document overrides
        let keysToRemove = preferences.documentOverrides.filter { $0.value == metadata.postScriptName }.map { $0.key }
        for key in keysToRemove {
            preferences.documentOverrides.removeValue(forKey: key)
        }
        if !keysToRemove.isEmpty {
            savePreferences()
        }
        
        delegate?.fontManager(self, didUpdateFonts: installedFonts)
        
        DDLogInfo("FontManager: Successfully removed font: \(metadata.displayName)")
    }
    
    // MARK: - Font Registration
    
    private func registerFont(at url: URL) -> Bool {
        guard let fontDataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(fontDataProvider) else {
            DDLogError("FontManager: Failed to create CGFont from \(url.path)")
            return false
        }
        
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterGraphicsFont(font, &error) else {
            if let error = error?.takeRetainedValue() {
                DDLogError("FontManager: Font registration failed - \(error)")
            }
            return false
        }
        
        return true
    }
    
    private func scanInstalledFonts() {
        DDLogInfo("FontManager: Scanning installed fonts")
        
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: fontDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        
        installedFonts = urls.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "ttf" || ext == "otf" else { return nil }
            
            // Register font
            _ = registerFont(at: url)
            
            // Extract metadata
            return FontMetadata.extractMetadata(from: url)
        }.sorted { $0.displayName < $1.displayName }
        
        DDLogInfo("FontManager: Found \(installedFonts.count) installed fonts")
    }
    
    // MARK: - Preferences
    
    func setDefaultFont(_ fontPostScriptName: String?) {
        preferences.defaultFont = fontPostScriptName
        savePreferences()
    }
    
    func setFont(_ fontPostScriptName: String?, forDocument documentKey: String) {
        preferences.setFont(fontPostScriptName, for: documentKey)
        savePreferences()
    }
    
    func font(forDocument documentKey: String) -> String? {
        return preferences.font(for: documentKey)
    }
    
    func setDefaultTypesettingSettings(_ settings: TypesettingSettings) {
        preferences.defaultTypesetting = settings
        savePreferences()
    }
    
    func setTypesettingSettings(_ settings: TypesettingSettings, forDocument documentKey: String) {
        preferences.setTypesettingSettings(settings, for: documentKey)
        savePreferences()
    }
    
    func typesettingSettings(forDocument documentKey: String) -> TypesettingSettings {
        return preferences.typesettingSettings(for: documentKey)
    }
    
    func clearDocumentOverrides(forDocument documentKey: String) {
        preferences.clearOverrides(for: documentKey)
        savePreferences()
    }
    
    private func savePreferences() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: preferencesKey)
        }
    }
    
    // MARK: - Font Access
    
    func getFontMetadata(for postScriptName: String) -> FontMetadata? {
        return installedFonts.first { $0.postScriptName == postScriptName }
    }
    
    func getAllFonts() -> [FontMetadata] {
        return installedFonts
    }
    
    func getFontsByFamily() -> [String: [FontMetadata]] {
        return Dictionary(grouping: installedFonts) { $0.familyName }
    }
}
