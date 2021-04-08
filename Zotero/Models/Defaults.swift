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

    @UserDefault(key: "userid", defaultValue: 0)
    var userId: Int

    // MARK: - Settings

    @UserDefault(key: "ShareExtensionIncludeTags", defaultValue: true)
    var shareExtensionIncludeTags: Bool

    @UserDefault(key: "ShareExtensionIncludeAttachment", defaultValue: true)
    var shareExtensionIncludeAttachment: Bool

    @UserDefault(key: "ShowSubcollectionItems", defaultValue: false, defaults: .standard)
    var showSubcollectionItems: Bool

    // MARK: - Selection

    @CodableUserDefault(key: "SelectedRawLibraryKey", defaultValue: LibraryIdentifier.custom(.myLibrary), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var selectedLibrary: LibraryIdentifier

    @CodableUserDefault(key: "SelectedRawCollectionKey", defaultValue: CollectionIdentifier.custom(.all), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var selectedCollectionId: CollectionIdentifier

    // MARK: - PDF Settings

    #if PDFENABLED && MAINAPP
    @CodableUserDefault(key: "PDFReaderSettings", defaultValue: PDFSettingsState.default, encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder, defaults: .standard)
    var pdfSettings: PDFSettingsState
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
        self.userId = 0
        self.shareExtensionIncludeTags = true
        self.shareExtensionIncludeAttachment = true
        self.selectedLibrary = .custom(.myLibrary)
        self.selectedCollectionId = .custom(.all)
    }
}
