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

    @UserDefault(key: "ShowSubcollectionItems", defaultValue: false, defaults: .standard)
    var showSubcollectionItems: Bool

    @UserDefault(key: "ShowCollectionItemCounts", defaultValue: true, defaults: .standard)
    var showCollectionItemCounts: Bool

    @UserDefault(key: "QuickCopyStyleId", defaultValue: "http://www.zotero.org/styles/chicago-note-bibliography", defaults: .standard)
    var quickCopyStyleId: String

    // Proper default value is set up in AppDelegate.setupExportDefaults().
    @UserDefault(key: "QuickCopyLocaleId", defaultValue: "en-US", defaults: .standard)
    var quickCopyLocaleId: String

    @UserDefault(key: "QuickCopyAsHtml", defaultValue: false, defaults: .standard)
    var quickCopyAsHtml: Bool

    // MARK: - Selection

    @CodableUserDefault(key: "SelectedRawLibraryKey", defaultValue: LibraryIdentifier.custom(.myLibrary), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var selectedLibrary: LibraryIdentifier

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

    @UserDefault(key: "DidPerformFullSyncFix", defaultValue: false)
    var didPerformFullSyncFix: Bool

    // MARK: - Actions

    func reset() {
        self.askForSyncPermission = false
        self.username = ""
        self.displayName = ""
        self.userId = 0
        self.shareExtensionIncludeTags = true
        self.shareExtensionIncludeAttachment = true
        self.selectedLibrary = .custom(.myLibrary)
        self.selectedCollectionId = .custom(.all)
        self.webDavUrl = nil
        self.webDavScheme = .https
        self.webDavEnabled = false
        self.webDavUsername = nil
        self.webDavVerified = false
        self.quickCopyLocaleId = "en-US"
        self.quickCopyAsHtml = false
        self.quickCopyStyleId = "http://www.zotero.org/styles/chicago-note-bibliography"
        self.showSubcollectionItems = false

        #if MAINAPP
        self.itemsSortType = .default
        self.exportOutputMethod = .copy
        self.exportOutputMode = .bibliography

        self.activeLineWidth = 1
        self.inkColorHex = AnnotationsConfig.defaultActiveColor
        self.squareColorHex = AnnotationsConfig.defaultActiveColor
        self.noteColorHex = AnnotationsConfig.defaultActiveColor
        self.highlightColorHex = AnnotationsConfig.defaultActiveColor
        self.pdfSettings = PDFSettings.default
        #endif
    }
}
