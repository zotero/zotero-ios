//
//  ICloudFileProvider.swift
//
//  Created to provide a minimal bridge between your existing File/FileData
//  abstraction and iCloud Drive (ubiquity container) storage.
//
//  Use this helper to decide whether to store under iCloud or local Documents,
//  construct FileData with the right root path, and ensure directories exist
//  before writing.
//

import Foundation

/// Preference for where files should be stored.
/// - iCloudIfAvailable: Use iCloud Drive if available, otherwise fall back to local.
/// - localOnly: Always use local Documents directory.
enum StoragePreference {
    case iCloudIfAvailable
    case localOnly
}

/// Resolves iCloud (ubiquity container) and local roots and helps create FileData
/// instances that point to the chosen storage location.
struct ICloudFileProvider {
    /// Pass a specific container identifier (e.g., "iCloud.com.yourcompany.yourapp").
    /// If nil, the default container will be used (must be configured in Capabilities).
    let ubiquityContainerIdentifier: String?

    init(ubiquityContainerIdentifier: String? = nil) {
        self.ubiquityContainerIdentifier = ubiquityContainerIdentifier
    }

    /// Indicates whether iCloud is available for this device/account and container.
    /// Note: The first call can be relatively expensive; consider calling off the main thread.
    var iCloudAvailable: Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier) != nil
    }

    /// The iCloud container's Documents directory URL, if available.
    var iCloudRootURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents", isDirectory: true)
    }

    /// The app's local Documents directory URL.
    var localRootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Returns the root URL matching the given storage preference.
    func rootURL(preference: StoragePreference) -> URL {
        switch preference {
        case .iCloudIfAvailable:
            return iCloudRootURL ?? localRootURL

        case .localOnly:
            return localRootURL
        }
    }

    /// Returns the root path (string) matching the given storage preference.
    func rootPath(preference: StoragePreference) -> String {
        rootURL(preference: preference).path
    }

    /// Creates a FileData instance rooted at the selected storage location.
    func makeFile(relativeComponents: [String], name: String, type: FileData.ContentType, preference: StoragePreference = .iCloudIfAvailable) -> FileData {
        let root = rootPath(preference: preference)
        return FileData(rootPath: root, relativeComponents: relativeComponents, name: name, type: type)
    }

    /// Ensures that the parent directory for the given File exists on disk.
    /// Call before writing the file's contents.
    func ensureParentDirectory(for file: File) throws {
        let dirURL = file.createUrl().deletingLastPathComponent()
        try ensureDirectoryExists(at: dirURL)
    }

    /// Ensures the directory exists at the provided URL.
    func ensureDirectoryExists(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

extension ICloudFileProvider {
    static let shared = ICloudFileProvider(
        ubiquityContainerIdentifier: "iCloud.org.zotero.ios.Zotero"
    )
}
