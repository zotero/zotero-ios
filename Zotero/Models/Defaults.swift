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

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    @UserDefault(key: "AskForSyncPermission", defaultValue: false)
    var askForSyncPermission: Bool

    @UserDefault(key: "username", defaultValue: "")
    var username: String

    @UserDefault(key: "userid", defaultValue: 0)
    var userId: Int

    @UserDefault(key: "TranslatorsNeedUpdate", defaultValue: true)
    var updateTranslators: Bool

    @UserDefault(key: "ShowCollectionItemCount", defaultValue: true)
    var showCollectionItemCount: Bool

    @UserDefault(key: "ShareExtensionIncludeTags", defaultValue: true)
    var shareExtensionIncludeTags: Bool

    @UserDefault(key: "ShareExtensionIncludeAttachment", defaultValue: true)
    var shareExtensionIncludeAttachment: Bool

    var selectedLibrary: LibraryIdentifier {
        get {
            let data = UserDefaults.zotero.data(forKey: "SelectedRawLibraryKey")
            return data.flatMap({ try? self.jsonDecoder.decode(LibraryIdentifier.self, from: $0) }) ?? LibraryIdentifier.custom(.myLibrary)
        }

        set {
            guard let data = try? self.jsonEncoder.encode(newValue) else { return }
            UserDefaults.zotero.setValue(data, forKey: "SelectedRawLibraryKey")
        }
    }

    var selectedCollectionId: CollectionIdentifier {
        get {
            let data = UserDefaults.zotero.data(forKey: "SelectedRawCollectionKey")
            return data.flatMap({ try? self.jsonDecoder.decode(CollectionIdentifier.self, from: $0) }) ?? CollectionIdentifier.custom(.all)
        }

        set {
            guard let data = try? self.jsonEncoder.encode(newValue) else { return }
            UserDefaults.zotero.setValue(data, forKey: "SelectedRawCollectionKey")
        }
    }

    #if PDFENABLED && MAINAPP
    var pdfSettings: PDFSettingsState {
        get {
            let data = UserDefaults.standard.data(forKey: "PDFReaderSettings")
            return data.flatMap({ try? self.jsonDecoder.decode(PDFSettingsState.self, from: $0) }) ?? PDFSettingsState.default
        }

        set {
            guard let data = try? self.jsonEncoder.encode(newValue) else { return }
            UserDefaults.standard.setValue(data, forKey: "PDFReaderSettings")
        }
    }
    #endif

    func reset() {
        self.askForSyncPermission = false
        self.username = ""
        self.userId = 0
        self.updateTranslators = false
        self.shareExtensionIncludeTags = true
        self.shareExtensionIncludeAttachment = true
        self.selectedLibrary = .custom(.myLibrary)
        self.selectedCollectionId = .custom(.all)
    }
}
