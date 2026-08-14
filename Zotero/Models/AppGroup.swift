//
//  AppGroup.swift
//  Zotero
//
//  Created by Michal Rentka on 26/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AppGroup {
    /// Identifier of the container shared between the app and the share extension. Comes from `ZOTERO_APP_GROUP` in `FeatureGates.xcconfig`, which can be
    /// overridden in an uncommitted `Local.xcconfig` to build with an Apple Developer account outside of the Zotero organization.
    static let identifier: String = {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "ZoteroAppGroupIdentifier") as? String, !identifier.isEmpty else {
            return "group.org.zotero.ios.Zotero"
        }
        return identifier
    }()
}
