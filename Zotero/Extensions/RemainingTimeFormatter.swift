//
//  RemainingTimeFormatter.swift
//  Zotero
//
//  Created by Michal Rentka on 24.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Formats remaining time for remote voice credits display.
/// Handles the display logic including:
/// - Hiding time when it exceeds 90 days
/// - Showing days + hours for times >= 24 hours (e.g., "2d 2h")
/// - Showing hours + minutes for times < 24 hours (e.g., "2h 30m")
struct RemainingTimeFormatter {
    /// Threshold in seconds above which the remaining time should not be displayed (90 days)
    static let maxDisplayThresholdSeconds: TimeInterval = 90 * 24 * 60 * 60
    /// Number of seconds in 24 hours
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60
    
    private static let formatterWithDays: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()
    
    private static let formatterHoursMinutes: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()
    
    /// Formats the remaining time for display.
    /// - Parameter remainingTime: The remaining time in seconds.
    /// - Returns: A formatted string like "2d 2h", "2h 30m", "<1m", or "0m".
    static func formatted(_ remainingTime: TimeInterval) -> String {
        let roundedUpSeconds = ceil(remainingTime / 60) * 60
        if roundedUpSeconds == 0 {
            return "0m"
        } else if roundedUpSeconds < 60 {
            return "<1m"
        } else if roundedUpSeconds >= secondsPerDay {
            // Use day + hour format for times >= 24 hours
            return formatterWithDays.string(from: roundedUpSeconds) ?? ""
        } else {
            // Use hour + minute format for times < 24 hours
            return formatterHoursMinutes.string(from: roundedUpSeconds) ?? ""
        }
    }
    
    /// Checks if the remaining time should be displayed.
    /// - Parameter remainingTime: The remaining time in seconds.
    /// - Returns: `true` if time should be displayed (less than 90 days), `false` otherwise.
    static func shouldDisplay(_ remainingTime: TimeInterval) -> Bool {
        return remainingTime < maxDisplayThresholdSeconds
    }
}
