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
        return "device => \(device), os => \(osVersion), version => \(versionAndBuild ?? "Unknown")"
    }

    static var debugString: String {
        return """
        Version: \(versionAndBuild ?? "Unknown")
        Device: \(device)
        OS: \(osVersion)
        """
    }

    static var versionAndBuild: String? {
        guard let version = self.versionString, let build = self.buildString else { return nil }
        return "\(version) (\(build))"
    }

    static var versionString: String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static var buildString: String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    static var buildNumber: Int? {
        return self.buildString.flatMap(Int.init)
    }

    static var osVersion: String {
        return UIDevice.current.systemName + " " + UIDevice.current.systemVersion
    }

    static var device: String {
        return UIDevice.current.localizedModel
    }
}
