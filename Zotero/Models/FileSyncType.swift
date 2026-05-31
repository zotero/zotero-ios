//
//  FileSyncType.swift
//  Zotero
//
//  Created by Claude on 30.05.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Backend used to sync attachment files. Library data (items/collections/tags) always syncs through the Zotero API regardless of this value.
/// - `zotero`: Zotero File Storage (ZFS), the default API-backed storage.
/// - `webDav`: a user-provided WebDAV server.
/// - `iCloud`: the app's iCloud Drive ubiquitous container.
enum FileSyncType: String, Codable, Hashable, CaseIterable {
    case zotero
    case webDav
    case iCloud
}
