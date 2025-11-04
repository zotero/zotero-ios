//
//  DeviceInfoProvider.swift
//  Zotero
//
//  Created by Michal Rentka on 12.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct DeviceInfoProvider {
    static var delegateStart: CFAbsoluteTime = 0

    static var crashString: String {
        return "device => \(device), os => \(osVersion), version => \(versionAndBuild ?? "Unknown"), storage => \(deviceStorage), " +
               "lowPowerMode => \(ProcessInfo.processInfo.isLowPowerModeEnabled), isAppOnMac => \(ProcessInfo.processInfo.isiOSAppOnMac), " +
               "systemUptime => \(ProcessInfo.processInfo.systemUptime)"
    }

    static var debugString: String {
        var sceneCount: Int = 0
        var activeSceneCount: Int = 0
        #if MAINAPP
        inMainThread(sync: true) {
            sceneCount = UIApplication.shared.connectedScenes.count
            activeSceneCount = UIApplication.shared.connectedScenes.filter({ $0.activationState == .foregroundActive }).count
        }
        #endif
        return """
        Version: \(versionAndBuild ?? "Unknown")
        Device: \(device)
        OS: \(osVersion)
        System Storage: \(deviceStorage)
        Low Power Mode Enabled: \(ProcessInfo.processInfo.isLowPowerModeEnabled)
        Is iOS App on Mac: \(ProcessInfo.processInfo.isiOSAppOnMac)
        Active Scenes: \(activeSceneCount)
        Total Scenes: \(sceneCount)
        App Uptime: \(CFAbsoluteTimeGetCurrent() - delegateStart)
        System Uptime: \(ProcessInfo.processInfo.systemUptime)
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
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }
    
    static var deviceStorage: String {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let free = attrs[.systemFreeSize] as? Int64 ?? -1
            let total = attrs[.systemSize] as? Int64 ?? -1
            let freeGB = Double(free) / 1_073_741_824
            let totalGB = Double(total) / 1_073_741_824
            return String(format: "%.2f GB / %.2f GB", freeGB, totalGB)
        } catch let error {
            return "Can't get system storage: \(error)"
        }
    }
}
