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

    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

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

    // MARK: - Items Settings

    #if MAINAPP
    @CodableUserDefault(key: "RawItemsSortType", defaultValue: ItemsSortType.default, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder, defaults: .standard)
    var itemsSortType: ItemsSortType
    #endif

    // MARK: - Item Detail

    #if MAINAPP
    @CodableUserDefault(key: "LastUsedCreatorNamePresentation", defaultValue: .separate, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var creatorNamePresentation: ItemDetailState.Creator.NamePresentation
    #endif

    // MARK: - PDF Settings

    @UserDefault(key: "PdfReaderLineWidth", defaultValue: 2)
    var activeLineWidth: Float

    #if PDFENABLED && MAINAPP
    @UserDefault(key: "PDFReaderState.activeColor", defaultValue: AnnotationsConfig.defaultActiveColor)
    var activeColorHex: String

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

    // MARK: - Helpers

    @OptionalUserDefault(key: "LastLaunchBuildNumber", defaults: .standard)
    var lastBuildNumber: Int?

    @UserDefault(key: "AskForSyncPermission", defaultValue: false)
    var askForSyncPermission: Bool

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

        #if PDFENABLED
        self.activeColorHex = AnnotationsConfig.defaultActiveColor
        self.pdfSettings = PDFSettings.default
        #endif
        #endif
    }
}
