//
//  UserDefaults.swift
//  Zotero
//
//  Created by Michal Rentka on 18/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class Defaults {
    static let shared = Defaults()

    static let jsonEncoder = JSONEncoder()
    static let jsonDecoder = JSONDecoder()

    // MARK: - Session

    @UserDefault(key: "username", defaultValue: "")
    var username: String

    @UserDefault(key: "displayName", defaultValue: "")
    var displayName: String

    @UserDefault(key: "userid", defaultValue: 0)
    var userId: Int

    // MARK: - WebDav Session

    @UserDefault(key: "webDavEnabled", defaultValue: false)
    var webDavEnabled: Bool

    @UserDefault(key: "webDavVerified", defaultValue: false)
    var webDavVerified: Bool

    @CodableUserDefault(key: "webDavScheme", defaultValue: .https, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var webDavScheme: WebDavScheme

    @OptionalUserDefault(key: "webDavUsername")
    var webDavUsername: String?

    @OptionalUserDefault(key: "webDavUrl")
    var webDavUrl: String?

    // MARK: - Settings

    @UserDefault(key: "ShareExtensionIncludeTags", defaultValue: true)
    var shareExtensionIncludeTags: Bool

    @UserDefault(key: "ShareExtensionIncludeAttachment", defaultValue: true)
    var shareExtensionIncludeAttachment: Bool

    @UserDefault(key: "ShowSubcollectionItems", defaultValue: false, defaults: .standard, didChangeNotificationName: .showSubcollectionItemsChanged)
    var showSubcollectionItems: Bool

    @UserDefault(key: "ShowCollectionItemCounts", defaultValue: true, defaults: .standard)
    var showCollectionItemCounts: Bool

    @UserDefault(key: "OpenLinksInExternalBrowser", defaultValue: false, defaults: .standard)
    var openLinksInExternalBrowser: Bool

    @UserDefault(key: "QuickCopyStyleId", defaultValue: "http://www.zotero.org/styles/chicago-note-bibliography", defaults: .standard)
    var quickCopyStyleId: String

    // Proper default value is set up in AppDelegate.setupExportDefaults().
    @UserDefault(key: "QuickCopyLocaleId", defaultValue: "en-US", defaults: .standard)
    var quickCopyLocaleId: String

    @UserDefault(key: "QuickCopyAsHtml", defaultValue: false, defaults: .standard)
    var quickCopyAsHtml: Bool

    @UserDefault(key: "TrashAutoEmptyDayThreshold", defaultValue: 30, defaults: .standard)
    var trashAutoEmptyThreshold: Int

    @UserDefault(key: "TrashLastAutoEmptyDate", defaultValue: .distantPast, defaults: .standard)
    var trashLastAutoEmptyDate: Date

    // MARK: - Selection

    @CodableUserDefault(key: "SelectedRawLibraryKey", defaultValue: LibraryIdentifier.custom(.myLibrary), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var selectedLibraryId: LibraryIdentifier

    @CodableUserDefault(key: "SelectedRawCollectionKey", defaultValue: CollectionIdentifier.custom(.all), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var selectedCollectionId: CollectionIdentifier

    #if MAINAPP
    // MARK: - Items Settings
    
    @CodableUserDefault(key: "RawItemsSortType", defaultValue: ItemsSortType.default, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder, defaults: .standard)
    var itemsSortType: ItemsSortType

    // MARK: - Item Detail

    @CodableUserDefault(key: "LastUsedCreatorNamePresentation", defaultValue: .separate, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var creatorNamePresentation: ItemDetailState.Creator.NamePresentation

    // MARK: - PDF Settings

    @UserDefault(key: "PdfReaderLineWidth", defaultValue: 2)
    var activeLineWidth: Float

    @UserDefault(key: "PdfReaderEraserSize", defaultValue: 10)
    var activeEraserSize: Float

    @UserDefault(key: "PdfReaderFontSize", defaultValue: 12)
    var activeFontSize: Float

    @UserDefault(key: "PDFReaderState.highlightColor", defaultValue: AnnotationsConfig.defaultActiveColor)
    var highlightColorHex: String

    @UserDefault(key: "PDFReaderState.noteColor", defaultValue: AnnotationsConfig.defaultActiveColor)
    var noteColorHex: String

    @UserDefault(key: "PDFReaderState.squareColor", defaultValue: AnnotationsConfig.defaultActiveColor)
    var squareColorHex: String

    @UserDefault(key: "PDFReaderState.inkColor", defaultValue: AnnotationsConfig.defaultActiveColor)
    var inkColorHex: String

    @UserDefault(key: "PDFReaderState.underlineColor", defaultValue: AnnotationsConfig.defaultActiveColor)
    var underlineColorHex: String

    @UserDefault(key: "PDFReaderState.textColor", defaultValue: AnnotationsConfig.defaultActiveColor)
    var textColorHex: String

    @CodableUserDefault(key: "PDFReaderSettings", defaultValue: PDFSettings.default, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder, defaults: .standard)
    var pdfSettings: PDFSettings

    @CodableUserDefault(
        key: "PDFReaderAnnotationTools",
        defaultValue: [
            AnnotationToolButton(type: .highlight, isVisible: true),
            AnnotationToolButton(type: .underline, isVisible: true),
            AnnotationToolButton(type: .note, isVisible: true),
            AnnotationToolButton(type: .freeText, isVisible: true),
            AnnotationToolButton(type: .image, isVisible: true),
            AnnotationToolButton(type: .ink, isVisible: true),
            AnnotationToolButton(type: .eraser, isVisible: true)
        ],
        encoder: Defaults.jsonEncoder,
        decoder: Defaults.jsonDecoder,
        defaults: .standard
    )
    var pdfAnnotationTools: [AnnotationToolButton]

    // MARK: - HTML / Epub Settings

    @CodableUserDefault(key: "HtmlEpubReaderSettings", defaultValue: HtmlEpubSettings.default, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder, defaults: .standard)
    var htmlEpubSettings: HtmlEpubSettings

    @CodableUserDefault(
        key: "HtmlEpubReaderAnnotationTools",
        defaultValue: [AnnotationToolButton(type: .highlight, isVisible: true), AnnotationToolButton(type: .underline, isVisible: true), AnnotationToolButton(type: .note, isVisible: true)],
        encoder: Defaults.jsonEncoder,
        decoder: Defaults.jsonDecoder,
        defaults: .standard
    )
    var htmlEpubAnnotationTools: [AnnotationToolButton]

    // MARK: - Speech
    
    @UserDefault(key: "SpeechDefaultLocalVoiceForLanguage", defaultValue: [:])
    var defaultLocalVoiceForLanguage: [String: String]
    
    @CodableUserDefault(key: "SpeechDefaultRemoteVoiceForLanguage", defaultValue: [:], encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var defaultRemoteVoiceForLanguage: [String: RemoteVoice]
    
    @CodableUserDefault(key: "SpeechRemoteVoiceTier", defaultValue: nil, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var remoteVoiceTier: RemoteVoice.Tier?
    
    #endif

    // MARK: - Citation / Bibliography Export

    @UserDefault(key: "exportStyleId", defaultValue: "http://www.zotero.org/styles/chicago-note-bibliography", defaults: .standard)
    var exportStyleId: String

    // Proper default value is set up in AppDelegate.setupExportDefaults().
    @UserDefault(key: "exportLocaleId", defaultValue: "en-US", defaults: .standard)
    var exportLocaleId: String

    #if MAINAPP
    @CodableUserDefault(key: "ExportOutputMethod", defaultValue: .copy, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var exportOutputMethod: CitationBibliographyExportState.OutputMethod

    @CodableUserDefault(key: "ExportOutputMode", defaultValue: .bibliography, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var exportOutputMode: CitationBibliographyExportState.OutputMode
    #endif

    // MARK: - Tag picker

    @UserDefault(key: "TagPickerShowAutomatic", defaultValue: true)
    var tagPickerShowAutomaticTags: Bool

    @UserDefault(key: "TagPickerDisplayAllTags", defaultValue: false)
    var tagPickerDisplayAllTags: Bool

    // MARK: - Helpers

    @OptionalUserDefault(key: "LastLaunchBuildNumber", defaults: .standard)
    var lastBuildNumber: Int?

    @UserDefault(key: "AskForSyncPermission", defaultValue: false)
    var askForSyncPermission: Bool

    // Increment currentPerformFullSyncGuard by 1, whenever the upcoming release should trigger a full sync.
    static let currentPerformFullSyncGuard = 2
    @UserDefault(key: "PerformFullSyncGuard", defaultValue: {
        if UserDefaults.zotero.object(forKey: "DidPerformFullSyncFix") != nil {
            // Existing installation. Since this is the first use of this guard, we return the default value - 1, to be certain to trigger a full sync.
            return currentPerformFullSyncGuard - 1
        }
        // New installation, no need for a full sync.
        return currentPerformFullSyncGuard
    }())
    var performFullSyncGuard: Int

    @UserDefault(key: "DidPerformFullSyncFix", defaultValue: true)
    var didPerformFullSyncFix: Bool

    // Increment currentClearPSPDFKitCacheGuard by 1, whenever the upcoming release should clear the PSPDFKit cache.
    static let currentClearPSPDFKitCacheGuard = 2
    @UserDefault(key: "ClearPSPDFKitCacheGuard", defaultValue: currentClearPSPDFKitCacheGuard - 1)
    var clearPSPDFKitCacheGuard: Int

    // MARK: - Debug

    @UserDefault(key: "DebugReaderUUIDByHash", defaultValue: [:])
    var debugReaderUUIDByHash: [String: String]

    @OptionalUserDefault(key: "LastDebugReaderHashOrURL")
    var lastDebugReaderHashOrURL: String?

    // MARK: - Actions

    func reset() {
        askForSyncPermission = false
        username = ""
        displayName = ""
        userId = 0
        shareExtensionIncludeTags = true
        shareExtensionIncludeAttachment = true
        selectedLibraryId = .custom(.myLibrary)
        selectedCollectionId = .custom(.all)
        webDavUrl = nil
        webDavScheme = .https
        webDavEnabled = false
        webDavUsername = nil
        webDavVerified = false
        quickCopyLocaleId = "en-US"
        quickCopyAsHtml = false
        quickCopyStyleId = "http://www.zotero.org/styles/chicago-note-bibliography"
        showSubcollectionItems = false
        trashAutoEmptyThreshold = 30
        trashLastAutoEmptyDate = .distantPast

        #if MAINAPP
        itemsSortType = .default
        exportOutputMethod = .copy
        exportOutputMode = .bibliography
        activeLineWidth = 1
        inkColorHex = AnnotationsConfig.defaultActiveColor
        squareColorHex = AnnotationsConfig.defaultActiveColor
        noteColorHex = AnnotationsConfig.defaultActiveColor
        highlightColorHex = AnnotationsConfig.defaultActiveColor
        underlineColorHex = AnnotationsConfig.defaultActiveColor
        textColorHex = AnnotationsConfig.defaultActiveColor
        pdfSettings = PDFSettings.default
        #endif
    }
}
