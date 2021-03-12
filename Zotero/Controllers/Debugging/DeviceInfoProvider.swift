//
//  DeviceInfoProvider.swift
//  Zotero
//
//  Created by Michal Rentka on 12.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct DeviceInfoProvider {
    static var crashString: String {
        return "device => \(device), os => \(osVersion), version => \(version ?? "Unknown")"
    }

    static var debugString: String {
        return """
        Version: \(version ?? "Unknown")
        Device: \(device)
        OS: \(osVersion)
        """
    }

    static var version: String? {
        guard let infoDictionary = Bundle.main.infoDictionary,
              let version = infoDictionary["CFBundleShortVersionString"] as? String,
              let build = infoDictionary["CFBundleVersion"] as? String else { return nil }
        return "\(version) (\(build))"
    }

    static var osVersion: String {
        return UIDevice.current.systemName + " " + UIDevice.current.systemVersion
    }

    static var device: String {
        return UIDevice.current.localizedModel
    }
}
